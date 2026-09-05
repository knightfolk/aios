import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import DesktopShell
import SwiftUI

// Step 1: cards that ACT — every button maps to a journaling engine call,
// and the projected state changes accordingly.

@MainActor @Test func resolvingNeedsYouFromUIJournalsAndClearsQueue() async throws {
    let root = FileManager.currentDirectoryForTesting
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(store: journal)
    await model.refresh()

    try await journal.append(.decisionRequested(.init(subject: "api shape", question: "struct or class?", blocking: true)))
    await model.refresh()
    #expect(model.state?.needsUser.count == 1)

    await model.resolveNeedsYou(subject: "api shape", question: "struct or class?", answer: "struct")
    #expect(model.state?.needsUser.isEmpty == true)
    #expect(model.state?.resolvedNeedsYou.first?.answer == "struct")
}

@MainActor @Test func notesAndInboxPanelsExposePromotableItems() async throws {
    let root = FileManager.currentDirectoryForTesting
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(store: journal)

    let note = await model.createNote(text: "ring buffer idea")
    await model.promoteNote(id: note.id, target: "GOAL")
    var state = try Projection.replayAll(journal)
    #expect(state.promotions.count == 1)

    let item = await model.createInboxItem(text: "EPG cache someday")
    await model.promoteInboxItem(id: item.id, target: "TASK")
    state = try Projection.replayAll(journal)
    #expect(state.promotions.count == 2)

    let notes = await model.loadNotes()
    #expect(notes.map(\.id) == [note.id])
    let inbox = await model.loadInbox()
    #expect(inbox.map(\.id) == [item.id])
}

@MainActor @Test func checkpointActionsFromUICreateBranchAndRestore() async throws {
    let root = FileManager.currentDirectoryForTesting
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(store: journal)

    let goal = GoalRevisionID()
    let planA = PlanRevisionID()
    try await journal.append(.goalCreated(.init(goalRevisionID: goal, originalRequest: "r", objective: "o", acceptanceCriteria: [])))
    try await journal.append(.planProposed(.init(planRevisionID: planA, goalRevisionID: goal, summary: "A")))

    let checkpoint = await model.createCheckpoint(note: "before push")
    let branch = await model.branchFrom(checkpointID: checkpoint.checkpointID, reason: "alternate route")
    await model.restore(checkpointID: checkpoint.checkpointID, note: "reviewed local changes")

    let state = try Projection.replayAll(journal)
    #expect(state.activePlanRevisionID == branch)
    #expect(state.branches.count == 1)
    #expect(state.restorations.count == 1)
}

@MainActor @Test func stoppingAnActivityJournalsIntervention() async throws {
    let root = FileManager.currentDirectoryForTesting
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(store: journal)

    await model.cancelAttempt(attemptID: AttemptID(), reason: "user pressed stop")
    let state = try Projection.replayAll(journal)
    #expect(state.interventions.contains { $0.contains("stop requested") })
}

extension FileManager {
    /// Unique temp dir usable as a journal root in tests.
    static var currentDirectoryForTesting: URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aios-uiaction-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
