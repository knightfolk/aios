import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import SecurityKernel
@testable import CapabilityBroker
@testable import ExecutionFabric

// Item: prove the agentic loop with a REAL brain. The resident Qwen 7B must
// read the objective, propose an fs.write action through the harness
// contract, receive the broker's outcome, and complete. Skipped unless
// AIOS_LIVE_TOOLS=1.

private func workerBinary() throws -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = packageRoot.appendingPathComponent(".build/debug/InferenceWorker")
    #expect(FileManager.default.fileExists(atPath: url.path), "missing worker binary: \(url.path)")
    return url
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AIOS_LIVE_TOOLS"] == "1"))
func realBrainProposesActionAndCompletes() async throws {
    let modelDir = try #require(try liveModelDirectory(), "model not resident — run: swift run ModelFetch qwen25-7b-instruct-4bit")

    let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-livetools-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-livetools-j-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: workspace)
        try? FileManager.default.removeItem(at: root)
    }
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    let broker = CapabilityBroker(journal: journal)
    let policy = SecurityPolicy(workspaceRoots: [workspace.path], allowedCommands: [], localOnly: true)

    let target = workspace.appendingPathComponent("brain-notes.txt").path
    TestEnvGate.lock()
    defer { TestEnvGate.unlock() }
    TestEnvGate.set("AIOS_FAKE_LLM", nil) // real brain, no echo

    let session = WorkerSession(
        configuration: .init(executableURL: try workerBinary(),
                             arguments: ["--model", modelDir.path],
                             heartbeatTimeoutSeconds: 240),
        journal: journal
    )
    try await session.start()

    try await session.sendWorkPackage(WorkPackage(
        packageID: WorkPackageID(), projectID: journal.projectID,
        goalRevisionID: GoalRevisionID(), planRevisionID: PlanRevisionID(),
        taskID: TaskID(), attemptID: AttemptID(), role: .linus,
        taskContract: TaskContract(
            objective: "Create the file \(target) containing exactly the text READY (one line, nothing else) by proposing a write action.",
            inputs: [], allowedScope: [workspace.path], mustPreserve: [],
            forbiddenScope: [], expectedOutputs: [],
            verificationRequirements: [], dependencyAssumptions: [],
            stalenessConditions: []
        ),
        contextBundle: ContextBundle(selections: [], tokenBudget: 200),
        capabilities: [.modifyWorkspace], executionTargets: [.singleAgent],
        resourceBudget: ResourceBudget(maxMemoryGB: 8, maxComputeCores: 4),
        timeBudget: TimeBudget(timeoutSeconds: 300),
        privacyPolicy: .localOnly, spendPolicy: SpendPolicy(),
        expectedOutputs: [], verificationRequirements: [],
        handoffPolicy: .continuation, failurePolicy: .failFast,
        harnessProfile: HarnessProfileID(value: "default-v1")
    ))

    var workResult: WorkResult?
    var proposedActions: [ActionRequest] = []
    var generations: [String] = []
    var cursor = await session.eventHistory().count
    let deadline = Date().addingTimeInterval(300)
    loop: while Date() < deadline {
        let events = await session.eventHistory()
        while cursor < events.count {
            let event = events[cursor]
            cursor += 1
            switch event {
            case .actionRequest(let request):
                proposedActions.append(request)
                let result = await broker.execute(request, policy: policy)
                try await session.sendActionResult(result)
            case .generationDone(let generation):
                generations.append(generation.text)
            case .workResult(let result):
                workResult = result
                break loop
            default:
                break
            }
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    await session.terminate()

    let result = try #require(workResult, "no work result; generations: \(generations)")
    #expect(!proposedActions.isEmpty, "real brain proposed no actions; generations: \(generations)")
    #expect(proposedActions.allSatisfy { $0.operation == "fs.write" })

    // The write really happened, through the broker.
    let written = try String(contentsOfFile: target, encoding: .utf8)
    #expect(written.trimmingCharacters(in: .whitespacesAndNewlines).contains("READY"))
    #expect(!result.completedActionRefs.isEmpty)
    print("live tools: turns=\(generations.count) actions=\(proposedActions.count) status=\(result.status.rawValue) file=\(written.prefix(40))")
}
