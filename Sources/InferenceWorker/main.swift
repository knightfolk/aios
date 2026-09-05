import Foundation
import AIOSCore
import ExecutionFabric
import ModelRuntime
import MLXRuntime

// InferenceWorker — the Brain-side worker. Two honest modes:
//   --scenario <file>   declared scripted runtime (scenario-driven)
//   --model <dir>       real local MLX runtime (or the declared echo engine
//                       when AIOS_FAKE_LLM=1, reported as scripted)
// In every mode it never touches reality directly: effects are ActionRequests
// to the host broker, and generated output is typed generatedContent.

struct Options {
    var scenarioPath: String?
    var modelDirectory: String?

    init(arguments: [String]) {
        var iterator = arguments.makeIterator()
        while let flag = iterator.next() {
            switch flag {
            case "--scenario":
                scenarioPath = iterator.next()
            case "--model":
                modelDirectory = iterator.next()
            default:
                break
            }
        }
    }
}

final class WorkerContext: @unchecked Sendable {
    let pipe = WorkerPipe()
    let workerID = "inference-\(ProcessInfo.processInfo.processIdentifier)"
    var engine: (any LLMEngine)?
    var runtime: RuntimeKind = .scripted
    var modelName = "unknown"
    var modelRevision = "unknown"
    var scenario: WorkerScenario?
    var usingFakeEngine = ProcessInfo.processInfo.environment["AIOS_FAKE_LLM"] == "1"
}

let ctx = WorkerContext()
let options = Options(arguments: Array(CommandLine.arguments.dropFirst()))
var handshaked = false
signal(SIGPIPE, SIG_IGN) // a dead host pipe must end us via EOF, not a signal mid-write

// Scenario mode (declared scripted runtime).
if let scenarioPath = options.scenarioPath {
    guard let scenarioData = FileManager.default.contents(atPath: scenarioPath) else {
        try? FileHandle.standardError.write(contentsOf: Data("InferenceWorker: cannot read scenario \(scenarioPath)\n".utf8))
        exit(2)
    }
    do {
        ctx.scenario = try JSONDecoder().decode(WorkerScenario.self, from: scenarioData)
    } catch {
        try? FileHandle.standardError.write(contentsOf: Data("InferenceWorker: invalid scenario: \(error)\n".utf8))
        exit(2)
    }
}

// Heartbeats keep the host's hung-worker watchdog honest (also during load).
let heartbeatThread = Thread {
    let interval = ctx.scenario?.heartbeatIntervalSeconds ?? 0.5
    while true {
        Thread.sleep(forTimeInterval: max(0.05, interval))
        try? ctx.pipe.write(.heartbeat(Heartbeat(workerID: ctx.workerID)))
    }
}
heartbeatThread.start()

// Handshake FIRST: the host's session must see hello before a multi-GB
// model load consumes the timeout budget.
if let first = (try? ctx.pipe.readMessage()).flatMap({ $0 }),
   case .helloRequest(let hello) = first {
    try? ctx.pipe.write(.helloResponse(HelloResponse(
        protocolVersion: hello.protocolVersion,
        workerID: ctx.workerID,
        runtime: options.modelDirectory == nil ? .scripted : (ctx.usingFakeEngine ? .scripted : .mlx)
    )))
    handshaked = true
}

// Model mode: load the real engine (or the declared echo engine).
if let modelDirectory = options.modelDirectory {
    let dir = URL(fileURLWithPath: modelDirectory)
    if ctx.usingFakeEngine {
        ctx.engine = EchoEngine()
        ctx.runtime = .scripted
        ctx.modelName = "echo-engine"
        ctx.modelRevision = "1"
    } else {
        let engine = MLXEngine(modelDirectory: dir)
        let loaded = DispatchSemaphore(value: 0)
        // detached: main must not be the executor of its own blocking wait.
        Task.detached {
            do {
                try await engine.load()
            } catch {
                try? FileHandle.standardError.write(contentsOf: Data("InferenceWorker: model load failed: \(error)\n".utf8))
                exit(3)
            }
            loaded.signal()
        }
        loaded.wait()
        ctx.engine = engine
        ctx.runtime = .mlx
    }
    if let data = FileManager.default.contents(atPath: dir.appendingPathComponent("aios-manifest.json").path),
       let manifest = try? JSONDecoder().decode(ModelManifest.self, from: data) {
        ctx.modelName = ctx.usingFakeEngine ? "echo-engine" : manifest.modelID
        ctx.modelRevision = ctx.usingFakeEngine ? "1" : manifest.revision
    }
}

outer: while let inbound = (try? ctx.pipe.readMessage()).flatMap({ $0 }) {
    switch inbound {
    case .helloRequest(let hello):
        guard !handshaked else { break }
        handshaked = true
        try? ctx.pipe.write(.helloResponse(HelloResponse(
            protocolVersion: hello.protocolVersion,
            workerID: ctx.workerID,
            runtime: ctx.runtime
        )))

    case .workPackage(let package):
        if let engine = ctx.engine {
            runModelMode(engine: engine, for: package, ctx: ctx)
        } else if let scenario = ctx.scenario {
            runScenario(scenario, for: package, ctx: ctx)
        } else {
            try? FileHandle.standardError.write(contentsOf: Data("InferenceWorker: no --scenario or --model given\n".utf8))
            exit(2)
        }

    case .shutdown:
        break outer

    default:
        break
    }
}

exit(0)

// MARK: - Scenario mode

func runScenario(_ scenario: WorkerScenario, for package: WorkPackage, ctx: WorkerContext) {
    let pipe = ctx.pipe
    stepLoop: for step in scenario.steps {
        switch step {
        case .action(let actionStep):
            let request = scenario.actionRequest(for: actionStep, in: package)
            guard (try? pipe.write(.actionRequest(request))) != nil else { return }
            // Proceed only on the host broker's result for this action.
            while let reply = (try? pipe.readMessage()).flatMap({ $0 }) {
                switch reply {
                case .actionResult(let result) where result.actionID == request.actionID:
                    if result.outcome == .rejected || result.outcome == .stalePrecondition {
                        return // broker refused: the scripted scenario ends here
                    }
                    continue stepLoop
                case .cancel:
                    return
                case .shutdown:
                    exit(0)
                default:
                    continue // heartbeats and other traffic are ignored while waiting
                }
            }
            return // EOF while waiting for the broker

        case .sleepMs(let ms):
            Thread.sleep(forTimeInterval: Double(ms) / 1000.0)

        case .crash:
            exit(9)

        case .finish(let finishStep):
            let claims = finishStep.claims.compactMap { pair -> Claim? in
                guard pair.count == 2,
                      let type = SemanticStatementType(rawValue: pair[1]) else { return nil }
                return Claim(statement: pair[0], statementType: type)
            }
            let result = WorkResult(
                packageID: package.packageID,
                attemptID: package.attemptID,
                worker: WorkerIdentity(workerID: ctx.workerID, model: nil, runtime: .scripted, revision: "1"),
                status: WorkStatus(rawValue: finishStep.status) ?? .completed,
                artifacts: [],
                claims: claims,
                evidenceRefs: [],
                recommendedNextSteps: [finishStep.summary],
                handoff: Handoff(
                    task: package.taskContract.objective,
                    currentState: finishStep.summary,
                    recommendedNextAction: finishStep.summary
                )
            )
            _ = try? pipe.write(.workResult(result))
        }
    }
}

// MARK: - Model mode

/// One bridged async generation over the blocking pipe loop.
func runModelMode(engine: any LLMEngine, for package: WorkPackage, ctx: WorkerContext) {
    let pipe = ctx.pipe
    let profile: HarnessProfile
    do {
        profile = try HarnessProfileStore().load(profileID: "default-v1")
    } catch {
        try? FileHandle.standardError.write(contentsOf: Data("InferenceWorker: harness profile missing: \(error)\n".utf8))
        exit(3)
    }

    let systemPrompt = profile.systemPrompt + "\nRespond with a single JSON object matching this contract:\n" + profile.outputContractJSON
    let contextBlock = package.contextBundle.selections
        .map { "--- \($0.path) (\($0.reason)) ---" }
        .joined(separator: "\n")
    let userPrompt = """
    Objective: \(package.taskContract.objective)
    Allowed scope: \(package.taskContract.allowedScope.joined(separator: ", "))
    Must preserve: \(package.taskContract.mustPreserve.joined(separator: ", "))
    Verification requirements: \(package.taskContract.verificationRequirements.map(\.description).joined(separator: "; "))
    Compiled context:
    \(contextBlock.isEmpty ? "(none)" : contextBlock)
    """

    let request = GenerationRequest(
        messages: [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: userPrompt),
        ],
        maxTokens: 1024,
        temperature: 0,
        harnessProfileID: profile.profileID
    )

    let semaphore = DispatchSemaphore(value: 0)
    // detached: the blocking main loop must not be the task's executor.
    Task.detached {
        let generation = await engine.complete(request) { chunk in
            _ = try? pipe.write(.generationChunk(GenerationChunk(text: chunk)))
        }
        _ = try? pipe.write(.generationDone(generation))

        let workResult = buildWorkResult(from: generation, for: package, ctx: ctx)
        _ = try? pipe.write(.workResult(workResult))
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 600)
}

/// Parses the harness-contract JSON from generated text. When the model does
/// not follow the contract, the raw text becomes a single generatedContent
/// claim with status BLOCKED — never a fabricated structured result.
func buildWorkResult(from generation: GenerationResult, for package: WorkPackage, ctx: WorkerContext) -> WorkResult {
    struct ContractedOutput: Codable {
        struct ContractedClaim: Codable {
            var statement: String
            var statementType: String?
        }
        var status: String?
        var summary: String?
        var claims: [ContractedClaim]?
        var unresolvedAssumptions: [String]?
        var recommendedNextSteps: [String]?
    }

    var text = generation.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```") {
        text = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var status: WorkStatus = .blocked
    var claims: [Claim] = []
    var assumptions: [String] = []
    var nextSteps: [String] = []
    var summary = ""

    if let data = text.data(using: .utf8),
       let decoded = try? JSONDecoder().decode(ContractedOutput.self, from: data) {
        status = WorkStatus(rawValue: decoded.status ?? "BLOCKED") ?? .blocked
        summary = decoded.summary ?? ""
        assumptions = decoded.unresolvedAssumptions ?? []
        nextSteps = decoded.recommendedNextSteps ?? []
        claims = (decoded.claims ?? []).map { claim in
            Claim(
                statement: claim.statement,
                statementType: SemanticStatementType(rawValue: claim.statementType ?? "") ?? .generatedContent
            )
        }
    } else {
        claims = [Claim(statement: String(text.prefix(2000)), statementType: .generatedContent)]
        summary = "model output did not follow the JSON contract; raw text attached as generatedContent"
    }

    return WorkResult(
        packageID: package.packageID,
        attemptID: package.attemptID,
        worker: WorkerIdentity(
            workerID: ctx.workerID,
            model: ctx.modelName,
            runtime: ctx.runtime,
            revision: ctx.modelRevision
        ),
        status: status,
        artifacts: [],
        claims: claims,
        evidenceRefs: [],
        discoveredIssues: generation.outcome == .succeeded ? [] : ["generation outcome: \(generation.outcome.rawValue)"],
        unresolvedAssumptions: assumptions,
        recommendedNextSteps: nextSteps.isEmpty ? [summary] : nextSteps,
        handoff: Handoff(
            task: package.taskContract.objective,
            currentState: summary,
            recommendedNextAction: nextSteps.first ?? summary
        )
    )
}
