import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import ModelRuntime
@testable import Router
@testable import EvidenceEngine
@testable import EvaluationEngine

private func mlxRegistry() -> RuntimeRegistry {
    RuntimeRegistry(
        mlxManifest: ModelManifest(
            modelID: "m", family: "f", revision: "1", quantization: "4bit",
            sourceURL: "https://example.invalid/m", files: [ModelFile(filename: "w", sha256: String(repeating: "a", count: 64))],
            license: "mit", modalities: ["text"], contextWindowTokens: 1024,
            estimatedMemoryGB: 1, supportedRuntimes: [.mlx],
            recommendedRoles: [], knownLimitations: [], requiresRemoteCode: false
        ),
        cloudConfigured: true
    )
}

@Test func cloudToLocalFallbackIsAlwaysAllowed() {
    let decision = Router.planFallback(
        current: .cloudAPI,
        after: .runtimeFailed,
        registry: mlxRegistry(),
        policy: .localOnly,
        budget: SpendPolicy()
    )
    #expect(decision?.runtime == .mlx)
}

@Test func localToCloudRequiresPolicyAndBudget() {
    // Local fails but policy is Local Only: no cloud fallback, scripted instead.
    let localOnly = Router.planFallback(
        current: .mlx, after: .runtimeFailed,
        registry: mlxRegistry(), policy: .localOnly, budget: SpendPolicy(maxSpendUSD: 10)
    )
    #expect(localOnly?.runtime == .scripted)

    // Hybrid + budget: cloud is legal.
    let hybrid = Router.planFallback(
        current: .mlx, after: .runtimeFailed,
        registry: mlxRegistry(), policy: .hybridAllowed, budget: SpendPolicy(maxSpendUSD: 10)
    )
    #expect(hybrid?.runtime == .cloudAPI)

    // Hybrid but zero budget: scripted, never silent paid escalation.
    let zeroBudget = Router.planFallback(
        current: .mlx, after: .quotaExhausted,
        registry: mlxRegistry(), policy: .hybridAllowed, budget: SpendPolicy(maxSpendUSD: 0)
    )
    #expect(zeroBudget?.runtime == .scripted)
}

@Test func exhaustedChainReturnsNil() {
    let decision = Router.planFallback(
        current: .scripted, after: .runtimeFailed,
        registry: RuntimeRegistry(mlxManifest: nil, cloudConfigured: false),
        policy: .hybridAllowed, budget: SpendPolicy(maxSpendUSD: 10)
    )
    #expect(decision == nil) // nothing left: escalate to the user
}

@Test func hybridFlowJournalsModelSelectionSwitchesAndCompletes() async throws {
    // Offline end-to-end: local attempt fails at a checkpoint, fallback picks
    // the stubbed cloud runtime, the second attempt completes with evidence.
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-fallback-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    let recorder = EvidenceRecorder(journal: journal)
    let evaluator = IndependentEvaluator(journal: journal)

    let task = TaskID()
    try await journal.append(.taskCreated(.init(taskID: task, planRevisionID: PlanRevisionID(), objective: "produce a finding", owner: .sherlock)))
    try await journal.append(.taskStateChanged(.init(taskID: task, oldState: .pending, newState: .inProgress)))

    // Attempt 1 on mlx: started, selected, then fails.
    let attempt1 = AttemptID()
    try await journal.append(.attemptStarted(.init(attemptID: attempt1, taskID: task, workPackageID: WorkPackageID(),
                                                   worker: WorkerIdentity(workerID: "w1", runtime: .mlx))))
    try await journal.append(.modelSelected(.init(attemptID: attempt1, runtime: .mlx, rationale: "local MLX model resident")))
    try await journal.append(.workerCrashed(.init(workerID: "w1", attemptID: attempt1)))
    try await journal.append(.attemptEnded(.init(attemptID: attempt1, taskID: task, outcome: .failed)))

    // Checkpoint fallback decision (journal-driven).
    let fallback = Router.planFallback(
        current: .mlx, after: .runtimeFailed,
        registry: mlxRegistry(), policy: .hybridAllowed, budget: SpendPolicy(maxSpendUSD: 5)
    )
    #expect(fallback?.runtime == .cloudAPI)

    // Attempt 2 on the cloud runtime (stubbed engine would run here; the
    // engine flow is exercised in the model-mode tests).
    let attempt2 = AttemptID()
    try await journal.append(.attemptStarted(.init(attemptID: attempt2, taskID: task, workPackageID: WorkPackageID(),
                                                   worker: WorkerIdentity(workerID: "w2", model: "glm-4.6", runtime: .cloudAPI))))
    try await journal.append(.modelSelected(.init(attemptID: attempt2, runtime: .cloudAPI, rationale: "fallback from mlx after runtime failure: \(fallback?.rationale.joined(separator: "; ") ?? "")")))
    try await journal.append(.workerRecovered(.init(workerID: "w2", attemptID: attempt2, strategy: "checkpoint handoff to cloud")))

    let workResult = WorkResult(
        packageID: WorkPackageID(), attemptID: attempt2,
        worker: WorkerIdentity(workerID: "w2", model: "glm-4.6", runtime: .cloudAPI),
        status: .completed,
        claims: [Claim(statement: "finding produced", statementType: .generatedContent)]
    )
    let artifactID = ArtifactID()
    try await recorder.recordArtifact(artifactID: artifactID, kind: .report, path: "ws/finding.md", revision: "r1", contentHash: "h1")
    let evidence = Evidence(
        evidenceID: EvidenceID(), projectID: journal.projectID,
        subject: "finding coverage", proposition: "independent review covered the finding",
        claimType: .verifiedFact, sourceType: .tool, sourceReference: "stubbed-review",
        observedAt: Date(), verificationMethod: .independentReview,
        strength: .independentReview,
        artifactRevisionRefs: [ArtifactRevisionRef(artifactID: artifactID, revision: "r1")]
    )
    try await recorder.record(evidence: evidence)

    let verdict = try await evaluator.evaluate(
        taskID: task,
        requirements: [VerificationRequirement(description: "independent review", method: .independentReview)],
        evidence: [evidence],
        result: workResult
    )
    #expect(verdict.decision == .passed)

    let state = try Projection.replayAll(journal)
    #expect(state.tasks[task]?.state == .complete)
    #expect(state.attempts[attempt1]?.crashed == true)
    #expect(state.attempts[attempt2]?.recovered == true)

    // Both runtime selections are journaled: the switch is inspectable.
    let selections = state.attempts.values.compactMap(\.modelSelection).map(\.runtime)
    #expect(selections.contains(.mlx))
    #expect(selections.contains(.cloudAPI))
}
