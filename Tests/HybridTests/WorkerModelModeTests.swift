import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ExecutionFabric
@testable import ModelRuntime

private func workerBinary() throws -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = packageRoot.appendingPathComponent(".build/debug/InferenceWorker")
    #expect(FileManager.default.fileExists(atPath: url.path), "missing worker binary: \(url.path)")
    return url
}

private func dummyModelDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-dummymodel-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
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
            objective: "summarize the fixture",
            inputs: [], allowedScope: [], mustPreserve: [], forbiddenScope: [],
            expectedOutputs: [], verificationRequirements: [],
            dependencyAssumptions: [], stalenessConditions: []
        ),
        contextBundle: ContextBundle(
            selections: [ContextSelection(path: "ws/readme.md", reason: "contract input")],
            tokenBudget: 200
        ),
        capabilities: [.observe],
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

private func echoSession(modelDir: URL, heartbeatTimeout: TimeInterval = 10) throws -> WorkerSession {
    WorkerSession(
        configuration: .init(
            executableURL: try workerBinary(),
            arguments: ["--model", modelDir.path],
            heartbeatTimeoutSeconds: heartbeatTimeout
        ),
        journal: nil
    )
}

@Test func modelModeStreamsAndReportsHonestIdentity() async throws {
    TestEnvGate.lock()
    defer { TestEnvGate.unlock() }
    TestEnvGate.set("AIOS_FAKE_LLM", "1")
    TestEnvGate.set("AIOS_FAKE_LLM_ACTIONS", nil)
    TestEnvGate.set("AIOS_ECHO_ACTION_TARGET", nil)
    TestEnvGate.set("AIOS_FAKE_LLM_DELAY_MS", nil)

    let modelDir = try dummyModelDir()
    defer { try? FileManager.default.removeItem(at: modelDir) }
    let session = try echoSession(modelDir: modelDir)
    try await session.start()
    try await session.sendWorkPackage(makePackage())

    var chunks = 0
    var generationDone: GenerationResult?
    var workResult: WorkResult?
    let deadline = Date().addingTimeInterval(15)
    loop: while Date() < deadline {
        let events = await session.eventHistory()
        for event in events {
            switch event {
            case .generationChunk:
                chunks += 1
            case .generationDone(let result):
                generationDone = result
            case .workResult(let result):
                workResult = result
                if generationDone != nil { break loop }
            default:
                break
            }
        }
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(chunks > 0)
    let done = try #require(generationDone)
    #expect(done.outcome == .succeeded)
    #expect(done.text.contains("ECHO"))

    let result = try #require(workResult)
    // Honest identity: the echo engine is declared scripted, never mlx.
    #expect(result.worker.runtime == .scripted)
    #expect(result.worker.model == "echo-engine")
    #expect(result.claims.allSatisfy { $0.statementType == .generatedContent })

    await session.terminate()
}

@Test func killMidGenerationFollowsCrashPath() async throws {
    TestEnvGate.lock()
    defer { TestEnvGate.unlock() }
    TestEnvGate.set("AIOS_FAKE_LLM", "1")
    TestEnvGate.set("AIOS_FAKE_LLM_DELAY_MS", "100") // slow chunks → a real mid-generation window
    TestEnvGate.set("AIOS_FAKE_LLM_ACTIONS", nil)
    TestEnvGate.set("AIOS_ECHO_ACTION_TARGET", nil)

    let modelDir = try dummyModelDir()
    defer { try? FileManager.default.removeItem(at: modelDir) }
    let session = try echoSession(modelDir: modelDir)
    try await session.start()
    try await session.sendWorkPackage(makePackage())

    // Wait for the first streamed chunk, then hard-kill the worker.
    _ = try await session.waitFor({ if case .generationChunk = $0 { true } else { false } }, timeout: 10)
    await session.killForTesting()

    let crash = try await session.waitFor({ if case .crashed = $0 { true } else { false } }, timeout: 5)
    guard case .crashed = crash else { return }
    // Host process (this test) is unaffected by construction.
}
