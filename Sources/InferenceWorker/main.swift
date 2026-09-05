import Foundation
import AIOSCore
import ExecutionFabric

// InferenceWorker — the Brain-side worker. v1 runs a declared scripted
// runtime (scenario file), honestly journaled as RuntimeKind.scripted. It
// never touches reality directly: every real-world effect is an
// ActionRequest sent to the host broker, and it proceeds only on the
// ActionResults the host sends back.

struct Options {
    var scenarioPath: String?

    init(arguments: [String]) {
        var iterator = arguments.makeIterator()
        while let flag = iterator.next() {
            switch flag {
            case "--scenario":
                scenarioPath = iterator.next()
            default:
                break
            }
        }
    }
}

let options = Options(arguments: Array(CommandLine.arguments.dropFirst()))

guard let scenarioPath = options.scenarioPath,
      let scenarioData = FileManager.default.contents(atPath: scenarioPath) else {
    try? FileHandle.standardError.write(contentsOf: Data("InferenceWorker: --scenario <path> is required\n".utf8))
    exit(2)
}

let scenario: WorkerScenario
do {
    scenario = try JSONDecoder().decode(WorkerScenario.self, from: scenarioData)
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("InferenceWorker: invalid scenario: \(error)\n".utf8))
    exit(2)
}

let pipe = WorkerPipe()
let workerID = "inference-\(ProcessInfo.processInfo.processIdentifier)"

// Heartbeats keep the host's hung-worker watchdog honest.
let heartbeatThread = Thread {
    while true {
        Thread.sleep(forTimeInterval: max(0.05, scenario.heartbeatIntervalSeconds))
        try? pipe.write(.heartbeat(Heartbeat(workerID: workerID)))
    }
}
heartbeatThread.start()

outer: while let inbound = (try? pipe.readMessage()).flatMap({ $0 }) {
    switch inbound {
    case .helloRequest(let hello):
        try? pipe.write(.helloResponse(HelloResponse(
            protocolVersion: hello.protocolVersion,
            workerID: workerID,
            runtime: .scripted
        )))

    case .workPackage(let package):
        runScenario(scenario, for: package, using: pipe)

    case .shutdown:
        break outer

    default:
        break
    }
}

exit(0)

func runScenario(_ scenario: WorkerScenario, for package: WorkPackage, using pipe: WorkerPipe) {
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
                worker: WorkerIdentity(workerID: workerID, model: nil, runtime: .scripted, revision: "1"),
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
