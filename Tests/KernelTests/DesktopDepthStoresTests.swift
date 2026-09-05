import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel

@Test func checkpointBranchRestoreFlow() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-cp-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = CheckpointStore(journal: journal)
    let goal = GoalRevisionID()
    let planA = PlanRevisionID()

    try await journal.append(.goalCreated(.init(goalRevisionID: goal, originalRequest: "r", objective: "o", acceptanceCriteria: ["c"])))
    try await journal.append(.planProposed(.init(planRevisionID: planA, goalRevisionID: goal, summary: "A")))

    let cp = try await store.createCheckpoint(note: "before refactor", artifactRefs: [])
    var state = try Projection.replayAll(journal)
    #expect(state.checkpoints.contains(cp.checkpointID))

    let branch = try await store.branch(from: cp.checkpointID, reason: "alternate approach")
    #expect(branch != planA)
    state = try Projection.replayAll(journal)
    #expect(state.activePlanRevisionID == branch)
    #expect(state.branches.first?.previousPlanRevisionID == planA)

    try await store.restore(checkpointID: cp.checkpointID, note: "user-reviewed local changes")
    state = try Projection.replayAll(journal)
    #expect(state.restorations.count == 1)
    // Restore is explicit and journaled; it never rewrites history.
    let replay = try JournalReader.readAllEvents(at: journal.journalFileURL)
    #expect(replay.records.count == 5) // goal, plan, checkpoint, branch, restore
}

@Test func notesAndInboxRoundTripAndPromote() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-notes-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let notes = NotesStore(journal: journal, storageRoot: root)
    let note = try await notes.create(text: "try a ring buffer for the parser")
    let loadedNotes = try await notes.load()
    #expect(loadedNotes.map(\.id) == [note.id])

    try await notes.promote(noteID: note.id, target: "GOAL", summary: "ring-buffer parser goal")
    var state = try Projection.replayAll(journal)
    #expect(state.promotions.count == 1)

    let inbox = InboxStore(journal: journal, storageRoot: root)
    let item = try await inbox.create(text: "maybe EPG caching later")
    try await inbox.promote(itemID: item.id, target: "DISCARDED", summary: "stale")
    state = try Projection.replayAll(journal)
    #expect(state.promotions.count == 2)
    let loadedInbox = try await inbox.load() // discarded items stay readable, marked
    #expect(!loadedInbox.isEmpty)
    #expect(loadedInbox.first?.discarded == true)
}

@Test func projectHealthComputesConcreteCoverage() {
    var state = ProjectState(projectID: ProjectID())
    let goal = GoalRevisionID()
    state.goals[goal] = GoalRecord(
        goalRevisionID: goal, originalRequest: "r", objective: "o",
        acceptanceCriteria: ["tests pass", "docs updated", "perf budget"]
    )
    state.activeGoalRevisionID = goal
    let t1 = TaskID()
    let t2 = TaskID()
    state.tasks[t1] = TaskRecord(taskID: t1, planRevisionID: PlanRevisionID(), objective: "impl", owner: .linus, state: .complete)
    state.tasks[t2] = TaskRecord(taskID: t2, planRevisionID: PlanRevisionID(), objective: "docs", owner: .jobs, state: .inProgress)
    state.needsUser.append(NeedsYouEntry(subject: "contract drift", question: "block?", blocking: true))
    state.warnings.append("suspected missing verification coverage")
    let staleEvidence = EvidenceID()
    state.evidence[staleEvidence] = Evidence(
        evidenceID: staleEvidence, projectID: state.projectID, subject: "s", proposition: "p",
        claimType: .verifiedFact, sourceType: .command, sourceReference: "x",
        observedAt: Date(), verificationMethod: .testsPass, strength: .mechanicalCheck, status: .stale
    )
    let running = AttemptID()
    state.attempts[running] = AttemptRecord(attemptID: running, taskID: t1, workPackageID: WorkPackageID(), phase: .running)
    let failed = ActionID()
    state.actions[failed] = ActionEntry(request: ActionRequest(
        actionID: failed, workPackageID: WorkPackageID(), requestedBy: .linus,
        capability: .modifyWorkspace, operation: "shell.run", target: "/bin/sh",
        expectedEffect: "x", sideEffectClass: .local, reversibility: .reversible,
        idempotency: .idempotent, requiredPermission: .modifyWorkspace, verificationPlan: "x"
    ), result: ActionResult(actionID: failed, outcome: .failed, startedAt: Date(), endedAt: Date()))

    let health = ProjectHealth.compute(from: state)
    #expect(health.goalCriteriaTotal == 3)
    #expect(health.verificationCoverage == 0.5) // one of two tasks complete
    #expect(health.blockers == 0) // nothing blocked; the queued decision is counted below
    #expect(health.unresolvedDecisions == 1)
    #expect(health.suspectedGaps == 1)
    #expect(health.staleEvidence == 1)
    #expect(health.activeFailures == 1)
    #expect(health.activeAttempts == 1)
}

@Test func emptyProjectHealthIsZeroed() {
    let health = ProjectHealth.compute(from: ProjectState(projectID: ProjectID()))
    #expect(health.goalCriteriaTotal == 0)
    #expect(health.blockers == 0)
    #expect(health.staleEvidence == 0)
    #expect(health.compositeScore == nil) // no fake confidence number, ever
}
