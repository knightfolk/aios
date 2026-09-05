import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import EvidenceEngine
@testable import EvaluationEngine

private func makeRecorder() throws -> (EvidenceRecorder, JournalStore, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-evidence-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    return (EvidenceRecorder(journal: journal), journal, root)
}

private func fixtureEvidence(
    artifact: ArtifactRevisionRef,
    method: VerificationMethod = .testsPass,
    strength: EvidenceStrength = .mechanicalCheck,
    projectID: ProjectID
) -> Evidence {
    Evidence(
        evidenceID: EvidenceID(),
        projectID: projectID,
        subject: "test suite",
        proposition: "tests pass at \(artifact.revision)",
        claimType: .verifiedFact,
        sourceType: .command,
        sourceReference: "swift test",
        observedAt: Date(),
        verificationMethod: method,
        strength: strength,
        artifactRevisionRefs: [artifact]
    )
}

@Test func evidenceGoesStaleWhenBoundArtifactChanges() async throws {
    let (recorder, journal, root) = try makeRecorder()
    defer { try? FileManager.default.removeItem(at: root) }
    let projectID = journal.projectID

    let artifactID = ArtifactID()
    try await recorder.recordArtifact(artifactID: artifactID, kind: .commit, path: "ws/diff.patch", revision: "r1", contentHash: "h1")
    let evidence = fixtureEvidence(artifact: ArtifactRevisionRef(artifactID: artifactID, revision: "r1"), projectID: projectID)
    try await recorder.record(evidence: evidence)

    var state = try Projection.replayAll(journal)
    #expect(state.evidence[evidence.evidenceID]?.status == .valid)

    // The artifact changes after verification: the cascade must fire.
    try await recorder.recordArtifactChange(artifactID: artifactID, newRevision: "r2", contentHash: "h2")

    state = try Projection.replayAll(journal)
    #expect(state.evidence[evidence.evidenceID]?.status == .stale)

    let replay = try JournalReader.readAllEvents(at: journal.journalFileURL)
    let invalidations = replay.records.filter { record in
        if case .evidenceInvalidated = record.event { return true } else { return false }
    }
    #expect(invalidations.count == 1)
}

@Test func directInvalidationMarksInvalidated() async throws {
    let (recorder, journal, root) = try makeRecorder()
    defer { try? FileManager.default.removeItem(at: root) }
    let evidence = fixtureEvidence(artifact: ArtifactRevisionRef(artifactID: ArtifactID(), revision: "r1"), projectID: journal.projectID)
    try await recorder.record(evidence: evidence)
    try await recorder.invalidate(evidenceID: evidence.evidenceID, reason: "verification retracted by evaluator")

    let state = try Projection.replayAll(journal)
    #expect(state.evidence[evidence.evidenceID]?.status == .invalidated)
}

@Test func completionClaimWithoutEvidenceIsRejected() async throws {
    let (recorder, journal, root) = try makeRecorder()
    defer { try? FileManager.default.removeItem(at: root) }
    let taskID = TaskID()
    let evaluator = IndependentEvaluator(journal: journal)

    let claim = WorkResult(
        packageID: WorkPackageID(), attemptID: AttemptID(),
        worker: WorkerIdentity(workerID: "inference-1", runtime: .scripted),
        status: .completed,
        claims: [Claim(statement: "all tests pass", statementType: .generatedContent)]
    )
    let verdict = try await evaluator.evaluate(
        taskID: taskID,
        requirements: [VerificationRequirement(description: "test suite passes", method: .testsPass)],
        evidence: [],
        result: claim
    )
    #expect(verdict.decision == .failed)
    #expect(verdict.unmetRequirements.contains { $0.contains("test suite passes") })

    // The task must not be complete from the self-report alone.
    let state = try Projection.replayAll(journal)
    #expect(state.tasks[taskID] == nil || state.tasks[taskID]?.state != .complete)
}

@Test func evidencedCompletionPassesIndependentReview() async throws {
    let (recorder, journal, root) = try makeRecorder()
    defer { try? FileManager.default.removeItem(at: root) }
    let projectID = journal.projectID
    let taskID = TaskID()
    let evaluator = IndependentEvaluator(journal: journal)

    // Engine context: the task exists and is awaiting verification.
    try await journal.append(.taskCreated(.init(taskID: taskID, planRevisionID: PlanRevisionID(), objective: "fix", owner: .linus)))
    try await journal.append(.taskStateChanged(.init(taskID: taskID, oldState: .pending, newState: .inProgress)))

    let artifactID = ArtifactID()
    try await recorder.recordArtifact(artifactID: artifactID, kind: .commit, path: "ws/diff.patch", revision: "r1", contentHash: "h1")
    let passing = fixtureEvidence(artifact: ArtifactRevisionRef(artifactID: artifactID, revision: "r1"), projectID: projectID)
    try await recorder.record(evidence: passing)

    let claim = WorkResult(
        packageID: WorkPackageID(), attemptID: AttemptID(),
        worker: WorkerIdentity(workerID: "inference-1", runtime: .scripted),
        status: .completed,
        evidenceRefs: [passing.evidenceID]
    )
    let verdict = try await evaluator.evaluate(
        taskID: taskID,
        requirements: [VerificationRequirement(description: "test suite passes", method: .testsPass)],
        evidence: [passing],
        result: claim
    )
    #expect(verdict.decision == .passed)

    let state = try Projection.replayAll(journal)
    #expect(state.tasks[taskID]?.state == .complete)
}

@Test func deterministicCheckLabelsMustMatch() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-evaluator-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let evaluator = IndependentEvaluator(journal: journal)

    let evidence = Evidence(
        evidenceID: EvidenceID(), projectID: journal.projectID,
        subject: "lint", proposition: "lint clean", claimType: .verifiedFact,
        sourceType: .command, sourceReference: "lint", observedAt: Date(),
        verificationMethod: .deterministicCheck("lint"), strength: .mechanicalCheck
    )
    let verdict = try await evaluator.evaluate(
        taskID: TaskID(),
        requirements: [VerificationRequirement(description: "lint clean", method: .deterministicCheck("stylecheck"))],
        evidence: [evidence],
        result: WorkResult(
            packageID: WorkPackageID(), attemptID: AttemptID(),
            worker: WorkerIdentity(workerID: "w", runtime: .scripted), status: .completed
        )
    )
    #expect(verdict.decision == .failed)
}

@Test func staleEvidenceDoesNotSatisfyRequirements() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-evaluator-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let evaluator = IndependentEvaluator(journal: journal)

    var stale = fixtureEvidence(artifact: ArtifactRevisionRef(artifactID: ArtifactID(), revision: "r1"), projectID: journal.projectID)
    stale.status = .stale

    let verdict = try await evaluator.evaluate(
        taskID: TaskID(),
        requirements: [VerificationRequirement(description: "tests pass", method: .testsPass)],
        evidence: [stale],
        result: WorkResult(
            packageID: WorkPackageID(), attemptID: AttemptID(),
            worker: WorkerIdentity(workerID: "w", runtime: .scripted), status: .completed
        )
    )
    #expect(verdict.decision == .failed)
}
