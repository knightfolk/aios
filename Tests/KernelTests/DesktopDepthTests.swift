import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel

private func apply(_ state: ProjectState, _ event: EngineEvent, seq: UInt64) -> ProjectState {
    Projection.apply(state, EventRecord(sequence: seq, recordedAt: Date(), projectID: state.projectID, event: event))
}

@Test func needsYouResolutionRemovesFromQueueAndRecordsAnswer() {
    var state = ProjectState(projectID: ProjectID())
    state = apply(state, .decisionRequested(.init(subject: "contract drift", question: "block?", blocking: true)), seq: 1)
    #expect(state.needsUser.count == 1)

    state = apply(state, .needsYouResolved(.init(subject: "contract drift", question: "block?", answer: "block the attempt")), seq: 2)
    #expect(state.needsUser.isEmpty)
    #expect(state.resolvedNeedsYou.count == 1)
    #expect(state.resolvedNeedsYou.first?.answer == "block the attempt")
}

@Test func noteAndInboxPromotionsAreJournaledState() {
    var state = ProjectState(projectID: ProjectID())
    state = apply(state, .notePromoted(.init(noteID: "note-1", target: "GOAL", summary: "ship the parser fix")), seq: 1)
    state = apply(state, .inboxItemPromoted(.init(itemID: "inb-2", target: "TASK", summary: "add EPG cache")), seq: 2)
    state = apply(state, .inboxItemPromoted(.init(itemID: "inb-3", target: "DISCARDED", summary: "stale idea")), seq: 3)

    #expect(state.promotions.count == 3)
    #expect(state.promotions.contains { $0.noteID == "note-1" && $0.target == "GOAL" })
    #expect(state.promotions.filter { $0.itemID == "inb-3" }.first?.target == "DISCARDED")
}

@Test func branchAndRestoreLineageRecorded() {
    var state = ProjectState(projectID: ProjectID())
    let goal = GoalRevisionID()
    let planA = PlanRevisionID()
    let planB = PlanRevisionID()
    state = apply(state, .goalCreated(.init(goalRevisionID: goal, originalRequest: "r", objective: "o", acceptanceCriteria: ["c"])), seq: 1)
    state = apply(state, .planProposed(.init(planRevisionID: planA, goalRevisionID: goal, summary: "A")), seq: 2)
    state = apply(state, .checkpointCreated(.init(checkpointID: "cp1", note: "before refactor")), seq: 3)
    state = apply(state, .branchCreated(.init(fromCheckpointID: "cp1", newPlanRevisionID: planB, previousPlanRevisionID: planA, reason: "try alternate approach")), seq: 4)
    state = apply(state, .restoredFromCheckpoint(.init(checkpointID: "cp1", note: "explicit user restore; local changes reviewed")), seq: 5)

    #expect(state.activePlanRevisionID == planB)
    #expect(state.branches.count == 1)
    #expect(state.branches.first?.fromCheckpointID == "cp1")
    #expect(state.restorations.count == 1)
    #expect(state.checkpoints == ["cp1"])
}

@Test func historicalScrubIsPurePrefix() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-scrub-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let goal = GoalRevisionID()
    let events: [EngineEvent] = [
        .projectOpened,
        .goalCreated(.init(goalRevisionID: goal, originalRequest: "r", objective: "o", acceptanceCriteria: ["c"])),
        .planProposed(.init(planRevisionID: PlanRevisionID(), goalRevisionID: goal, summary: "A")),
        .taskCreated(.init(taskID: TaskID(), planRevisionID: PlanRevisionID(), objective: "t1", owner: .linus)),
        .checkpointCreated(.init(checkpointID: "cp1", note: "n")),
        .decisionRequested(.init(subject: "s", question: "q", blocking: false)),
    ]
    for event in events {
        _ = try await journal.append(event)
    }

    let before = try Data(contentsOf: journal.journalFileURL)
    let atThree = try Projection.state(at: 3, of: journal)
    let after = try Data(contentsOf: journal.journalFileURL)

    #expect(atThree.lastSequence == 3)
    #expect(before == after) // scrubbing is inspection, not rollback
}

@Test func stateAtZeroIsEmpty() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-scrub-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try await journal.append(.projectOpened)

    let empty = try Projection.state(at: 0, of: journal)
    #expect(empty.lastSequence == 0)
    #expect(empty.goals.isEmpty)
}
