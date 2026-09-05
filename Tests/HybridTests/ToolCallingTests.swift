import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import SecurityKernel
@testable import CapabilityBroker
@testable import ExecutionFabric

// Item 1: agentic tool-calling, offline end-to-end. The declared echo brain
// proposes a REAL fs.write action; the broker executes it against a scoped
// workspace; the worker consumes the ActionResult, runs a second turn, and
// completes with the action referenced in completedActionRefs.

@Test func echoBrainPerformsRealActionThroughBrokerAndCompletes() async throws {
    let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-tools-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-tools-j-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: workspace)
        try? FileManager.default.removeItem(at: root)
    }
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    let broker = CapabilityBroker(journal: journal)
    let policy = SecurityPolicy(workspaceRoots: [workspace.path], allowedCommands: [], localOnly: true)

    let target = workspace.appendingPathComponent("brain-output.txt").path
    await TestEnvGate.lock()
    defer { TestEnvGate.unlock() }
    TestEnvGate.set("AIOS_FAKE_LLM", "1")
    TestEnvGate.set("AIOS_FAKE_LLM_ACTIONS", "1")
    TestEnvGate.set("AIOS_ECHO_ACTION_TARGET", target)

    let session = WorkerSession(
        configuration: .init(executableURL: try workerBinary(),
                             arguments: ["--model", "/tmp/any-model-dir"],
                             heartbeatTimeoutSeconds: 10),
        journal: journal
    )
    try await session.start()

    let package = WorkPackage(
        packageID: WorkPackageID(), projectID: journal.projectID,
        goalRevisionID: GoalRevisionID(), planRevisionID: PlanRevisionID(),
        taskID: TaskID(), attemptID: AttemptID(), role: .linus,
        taskContract: TaskContract(
            objective: "write the marker file via a real action",
            inputs: [], allowedScope: [workspace.path], mustPreserve: [],
            forbiddenScope: [], expectedOutputs: [],
            verificationRequirements: [], dependencyAssumptions: [],
            stalenessConditions: []
        ),
        contextBundle: ContextBundle(selections: [], tokenBudget: 100),
        capabilities: [.modifyWorkspace], executionTargets: [.singleAgent],
        resourceBudget: ResourceBudget(), timeBudget: TimeBudget(),
        privacyPolicy: .localOnly, spendPolicy: SpendPolicy(),
        expectedOutputs: [], verificationRequirements: [],
        handoffPolicy: .continuation, failurePolicy: .failFast,
        harnessProfile: HarnessProfileID(value: "default-v1")
    )
    try await session.sendWorkPackage(package)

    var workResult: WorkResult?
    var proposedActions: [ActionRequest] = []
    var collector = await SessionEventCollector(session: session)
    let deadline = Date().addingTimeInterval(30)
    loop: while Date() < deadline {
        let events = await collector.drain(from: session)
        for event in events {
            switch event {
            case .actionRequest(let request):
                proposedActions.append(request)
                let result = await broker.execute(request, policy: policy)
                try await session.sendActionResult(result)
            case .workResult(let result):
                workResult = result
                break loop
            default:
                break
            }
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    await session.terminate()

    let result = try #require(workResult, "no work result")
    #expect(proposedActions.count == 1)
    #expect(proposedActions[0].operation == "fs.write")
    #expect(proposedActions[0].target == target)

    // The action really happened, through the broker.
    let written = try String(contentsOfFile: target, encoding: .utf8)
    #expect(written == "ECHO_ACTION_OK")
    #expect(result.completedActionRefs == [proposedActions[0].actionID])
    #expect(result.claims.allSatisfy { $0.statementType == .generatedContent })

    // And the journal saw the full transaction.
    let state = try Projection.replayAll(journal)
    #expect(state.actions.values.first?.authorized == true)
    #expect(state.actions.values.first?.result?.outcome == .succeeded)
}
