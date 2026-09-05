import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import DesktopShell

// T7: the Phase 3 depth flow end-to-end against a real journal — checkpoint,
// branch, scrub, health, needs-you resolution, note promotion — as the shell
// view models consume it.

@Test func depthFlowDrivesAllPanelsFromOneJournal() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-depth-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let goal = GoalRevisionID()
    let planA = PlanRevisionID()

    try await journal.append(.projectOpened)
    try await journal.append(.goalCreated(.init(goalRevisionID: goal, originalRequest: "harden the parser", objective: "fix + verify", acceptanceCriteria: ["tests pass", "docs"])))
    try await journal.append(.planProposed(.init(planRevisionID: planA, goalRevisionID: goal, summary: "A")))
    let pendingTask = TaskID()
    try await journal.append(.taskCreated(.init(taskID: pendingTask, planRevisionID: planA, objective: "write docs", owner: .jobs)))
    try await journal.append(.decisionRequested(.init(subject: "api shape", question: "struct or class?", blocking: true)))

    var state = try Projection.replayAll(journal)

    // Needs You: one active, then resolved.
    var needs = NeedsYouViewModel.summary(from: state)
    #expect(needs.active.count == 1)
    try await journal.append(.needsYouResolved(.init(subject: "api shape", question: "struct or class?", answer: "struct")))
    state = try Projection.replayAll(journal)
    needs = NeedsYouViewModel.summary(from: state)
    #expect(needs.active.isEmpty)
    #expect(needs.resolvedCount == 1)

    // Checkpoint → branch → future reflects the branch's lineage.
    let checkpoints = CheckpointStore(journal: journal)
    let cp = try await checkpoints.createCheckpoint(note: "before docs push", artifactRefs: [])
    let branch = try await checkpoints.branch(from: cp.checkpointID, reason: "docs-first approach")
    state = try Projection.replayAll(journal)
    #expect(state.activePlanRevisionID == branch)
    let future = FutureViewModel.items(from: state)
    #expect(future.map(\.objective) == ["write docs"]) // still projected, not done

    // Health reflects the queue and the plan.
    let health = ProjectHealth.compute(from: state)
    #expect(health.goalCriteriaTotal == 2)
    #expect(health.unresolvedDecisions == 0)
    let lines = HealthViewModel.lines(from: health)
    #expect(lines.contains { $0.contains("Goal criteria covered: 0/2") })

    // Notes promotion journals state the panels can show provenance for.
    let notes = NotesStore(journal: journal, storageRoot: root)
    let note = try await notes.create(text: "ring buffer idea")
    try await notes.promote(noteID: note.id, target: "GOAL", summary: "ring-buffer parser goal")
    state = try Projection.replayAll(journal)
    #expect(state.promotions.count == 1)

    // Historical scrub: state before the resolution still shows the queue.
    let beforeResolution = try Projection.state(at: 5, of: journal)
    let historicalNeeds = NeedsYouViewModel.summary(from: beforeResolution)
    #expect(historicalNeeds.active.count == 1)
    let scrub = ScrubPosition(sequence: beforeResolution.lastSequence, lastSequence: state.lastSequence)
    #expect(scrub.isHistorical)

    // And the journal was never rewritten by any of it.
    let replay = try JournalReader.readAllEvents(at: journal.journalFileURL)
    #expect(!replay.tornTail)
    #expect(replay.records.count == 9) // opened, goal, plan, task, decision, resolve, checkpoint, branch, promote
}
