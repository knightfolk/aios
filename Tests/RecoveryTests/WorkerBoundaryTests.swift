import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ExecutionFabric
@testable import ProjectKernel

private func workerBinary(_ name: String) throws -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = packageRoot.appendingPathComponent(".build/debug/\(name)")
    #expect(FileManager.default.fileExists(atPath: url.path), "missing worker binary — run swift build first: \(url.path)")
    return url
}

private func makeJournal() throws -> (JournalStore, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-worker-\(UUID().uuidString)", isDirectory: true)
    let store = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    return (store, root)
}

private func writeScenario(_ scenario: WorkerScenario) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-scenario-\(UUID().uuidString).json")
    try JSONEncoder().encode(scenario).write(to: url)
    return url
}

private func makePackage() -> WorkPackage {
    WorkPackage(
        packageID: WorkPackageID(),
        projectID: ProjectID(),
        goalRevisionID: GoalRevisionID(),
        planRevisionID: PlanRevisionID(),
        taskID: TaskID(),
        attemptID: AttemptID(),
        role: .linus,
        taskContract: TaskContract(
            objective: "fix lexer",
            inputs: [], allowedScope: [], mustPreserve: [], forbiddenScope: [],
            expectedOutputs: [], verificationRequirements: [],
            dependencyAssumptions: [], stalenessConditions: []
        ),
        contextBundle: ContextBundle(selections: [], tokenBudget: 1000),
        capabilities: [.modifyWorkspace],
        executionTargets: [.singleAgent],
        resourceBudget: ResourceBudget(),
        timeBudget: TimeBudget(),
        privacyPolicy: .localOnly,
        spendPolicy: SpendPolicy(),
        expectedOutputs: [],
        verificationRequirements: [],
        handoffPolicy: .continuation,
        failurePolicy: .retryIdempotentOnly,
        harnessProfile: HarnessProfileID(value: "default-v1")
    )
}

@Test func scriptedWorkerRoundTripsActionsAndResult() async throws {
    let scenarioURL = try writeScenario(WorkerScenario(
        steps: [
            .action(.init(operation: "fs.write", target: "Sources/Fix.swift", contents: "let a = 1\n", expectedEffect: "file written", verificationPlan: "compile")),
            .sleepMs(30),
            .finish(.init(status: "COMPLETED", claims: [["edit applied", "EXPERT_JUDGMENT"]], summary: "done"))
        ],
        heartbeatIntervalSeconds: 0.5
    ))
    let (journal, root) = try makeJournal()
    defer { try? FileManager.default.removeItem(at: root) }

    let session = WorkerSession(
        configuration: .init(
            executableURL: try workerBinary("InferenceWorker"),
            arguments: ["--scenario", scenarioURL.path],
            heartbeatTimeoutSeconds: 10
        ),
        journal: journal
    )
    try await session.start()
    try await session.sendWorkPackage(makePackage())

    let request = try await session.waitFor({ if case .actionRequest = $0 { true } else { false } }, timeout: 10)
    guard case .actionRequest(let action) = request else { Issue.record("unexpected event"); return }
    #expect(action.operation == "fs.write")
    #expect(action.requestedBy == .linus)

    try await session.sendActionResult(ActionResult(
        actionID: action.actionID,
        outcome: .succeeded,
        startedAt: Date(), endedAt: Date(),
        observedEffects: ["file written by host-side broker stub"]
    ))

    let result = try await session.waitFor({ if case .workResult = $0 { true } else { false } }, timeout: 10)
    guard case .workResult(let work) = result else { Issue.record("unexpected event"); return }
    #expect(work.status == .completed)
    #expect(work.worker.runtime == .scripted)
    let lastPackage = await session.lastWorkPackage
    #expect(work.attemptID == lastPackage?.attemptID)

    await session.terminate()
}

@Test func killNineMidRunIsDetectedAndJournaled() async throws {
    let scenarioURL = try writeScenario(WorkerScenario(
        steps: [.sleepMs(60_000), .finish(.init(status: "COMPLETED", claims: [], summary: "never reached"))],
        heartbeatIntervalSeconds: 1
    ))
    let (journal, root) = try makeJournal()
    defer { try? FileManager.default.removeItem(at: root) }

    let session = WorkerSession(
        configuration: .init(
            executableURL: try workerBinary("InferenceWorker"),
            arguments: ["--scenario", scenarioURL.path],
            heartbeatTimeoutSeconds: 10
        ),
        journal: journal
    )
    try await session.start()
    try await session.sendWorkPackage(makePackage())

    // Let the worker enter its long sleep, then hard-kill it.
    try await Task.sleep(for: .milliseconds(300))
    await session.killForTesting()

    let crash = try await session.waitFor({ if case .crashed = $0 { true } else { false } }, timeout: 5)
    guard case .crashed(let workerID) = crash else { Issue.record("unexpected event"); return }
    #expect(!workerID.isEmpty)

    // The crash is durably journaled and the attempt is recoverable.
    let replay = try JournalReader.readAllEvents(at: journal.journalFileURL)
    guard case .workerCrashed(let payload)? = replay.records.last?.event else {
        Issue.record("journal must end with workerCrashed, got \(String(describing: replay.records.last?.event))")
        return
    }
    #expect(payload.attemptID != nil)
}

@Test func heartbeatTimeoutDetectsHungWorker() async throws {
    let scenarioURL = try writeScenario(WorkerScenario(
        steps: [.sleepMs(400), .finish(.init(status: "COMPLETED", claims: [], summary: "late"))],
        heartbeatIntervalSeconds: 30 // heartbeats effectively never arrive in the window
    ))
    let (journal, root) = try makeJournal()
    defer { try? FileManager.default.removeItem(at: root) }

    let session = WorkerSession(
        configuration: .init(
            executableURL: try workerBinary("InferenceWorker"),
            arguments: ["--scenario", scenarioURL.path],
            heartbeatTimeoutSeconds: 0.3
        ),
        journal: journal
    )
    try await session.start()
    try await session.sendWorkPackage(makePackage())

    let hang = try await session.waitFor({ if case .hungDetected = $0 { true } else { false } }, timeout: 5)
    guard case .hungDetected = hang else { return }
    await session.terminate()
}

@Test func toolWorkerExecutesAuthorizedShellCommand() async throws {
    let (journal, root) = try makeJournal()
    defer { try? FileManager.default.removeItem(at: root) }

    let session = WorkerSession(
        configuration: .init(
            executableURL: try workerBinary("ToolWorker"),
            arguments: [],
            heartbeatTimeoutSeconds: 10
        ),
        journal: journal
    )
    try await session.start()

    let cwd = FileManager.default.temporaryDirectory.path
    try await session.send(.execute(ShellExecutionRequest(
        executionID: "exec-1", cwd: cwd, command: "/bin/echo", arguments: ["hello-from-toolworker"], timeoutSeconds: 10
    )))

    let finished = try await session.waitFor({ if case .executionFinished = $0 { true } else { false } }, timeout: 10)
    guard case .executionFinished(let result) = finished else { Issue.record("unexpected event"); return }
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("hello-from-toolworker"))
    #expect(!result.timedOut)

    await session.terminate()
}
