import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ExecutionFabric
@testable import ModelRuntime
@testable import MLXRuntime

// Opt-in live gate: real MLX generation in a real worker process. Skipped
// unless AIOS_LIVE_MLX=1 and the model is resident (fetched via ModelFetch).

func liveModelDirectory() throws -> URL? {
    let registry = try ModelRegistry.loadDefault()
    guard let manifest = registry.models.first else { return nil }
    let store = ModelStore()
    guard store.isResident(manifest) else { return nil }
    return store.directory(for: manifest)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AIOS_LIVE_MLX"] == "1"))
func liveMLXGenerationInWorker() async throws {
    let modelDir = try #require(try liveModelDirectory(), "model not resident — run: swift run ModelFetch qwen25-7b-instruct-4bit")

    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let session = WorkerSession(
        configuration: .init(
            executableURL: packageRoot.appendingPathComponent(".build/debug/InferenceWorker"),
            arguments: ["--model", modelDir.path],
            heartbeatTimeoutSeconds: 120
        ),
        journal: nil
    )
    try await session.start()

    try await session.sendWorkPackage(WorkPackage(
        packageID: WorkPackageID(),
        projectID: ProjectID(),
        goalRevisionID: GoalRevisionID(),
        planRevisionID: PlanRevisionID(),
        taskID: TaskID(),
        attemptID: AttemptID(),
        role: .linus,
        taskContract: TaskContract(
            objective: "In one sentence, state what the FIX_MARKER constant is for in a fixed fixture app.",
            inputs: [], allowedScope: [], mustPreserve: [], forbiddenScope: [],
            expectedOutputs: [ExpectedOutput(artifactKind: .report, description: "one-sentence answer")],
            verificationRequirements: [],
            dependencyAssumptions: [], stalenessConditions: []
        ),
        contextBundle: ContextBundle(
            selections: [ContextSelection(path: "Sources/App/main.swift", reason: "the fixture's main file")],
            tokenBudget: 400
        ),
        capabilities: [.observe],
        executionTargets: [.singleAgent],
        resourceBudget: ResourceBudget(maxMemoryGB: 8, maxComputeCores: 4),
        timeBudget: TimeBudget(timeoutSeconds: 240),
        privacyPolicy: .localOnly,
        spendPolicy: SpendPolicy(),
        expectedOutputs: [],
        verificationRequirements: [],
        handoffPolicy: .continuation,
        failurePolicy: .failFast,
        harnessProfile: HarnessProfileID(value: "default-v1")
    ))

    var generation: GenerationResult?
    var work: WorkResult?
    let deadline = Date().addingTimeInterval(240)
    loop: while Date() < deadline {
        for event in await session.eventHistory() {
            switch event {
            case .generationDone(let result):
                generation = result
            case .workResult(let result):
                work = result
                if generation != nil { break loop }
            default:
                break
            }
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    let done = try #require(generation, "no generation result within 240s")
    let result = try #require(work, "no work result within 240s")

    #expect(done.outcome == .succeeded)
    #expect(!done.text.isEmpty)
    #expect(result.worker.runtime == .mlx)
    #expect(result.worker.model == "qwen25-7b-instruct-4bit")
    #expect(!result.claims.isEmpty)
    #expect(result.claims.allSatisfy { $0.statementType == .generatedContent })

    await session.terminate()
}
