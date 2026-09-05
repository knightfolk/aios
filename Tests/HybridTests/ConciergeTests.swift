import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import DesktopShell

// Item: Concierge input routing — the front desk parses free text into
// deterministic destinations (goal / note / inbox / question). Deterministic
// v1: prefixes; unknown input lands in the inbox, never guessed.

@Test func conciergeRoutesPrefixesDeterministically() throws {
    #expect(ConciergeRouter.route("goal: ship the parser fix")?.destination == .goal)
    #expect(ConciergeRouter.route("note: try ring buffer")?.destination == .note)
    #expect(ConciergeRouter.route("inbox: EPG caching someday")?.destination == .inbox)
    #expect(ConciergeRouter.route("ask: what changed?")?.destination == .question)
    #expect(ConciergeRouter.route("  GOAL:  trim whitespace case")?.destination == .goal)
    // Unknown shapes fall to inbox — captured, not guessed.
    #expect(ConciergeRouter.route("random thought")?.destination == .inbox)
    #expect(ConciergeRouter.route("")?.destination == .inbox)
}

@Test func conciergeRoutesHaveJournaledOrStoredEffects() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-concierge-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    let notes = NotesStore(journal: journal, storageRoot: root)
    let inbox = InboxStore(journal: journal, storageRoot: root)

    try await ConciergeRouter.deliver("goal: fix the flaky timer test", journal: journal, notes: notes, inbox: inbox)
    try await ConciergeRouter.deliver("note: benchmark the lexer", journal: journal, notes: notes, inbox: inbox)
    try await ConciergeRouter.deliver("some vague musing", journal: journal, notes: notes, inbox: inbox)

    let state = try Projection.replayAll(journal)
    #expect(state.goals.count == 1)
    #expect(state.goals.values.first?.originalRequest == "fix the flaky timer test")
    #expect(state.promotions.count == 1) // the note promotion
    let inboxItems = try await inbox.load()
    #expect(inboxItems.map(\.text) == ["some vague musing"])
}

@Test func keyboardShortcutsAreDeclared() {
    let shortcuts = KeyboardShortcuts.all
    #expect(shortcuts.contains { $0.action == .switchProject(0) && $0.key == "cmd+1" })
    #expect(shortcuts.contains { $0.action == .fullScreen && $0.key == "cmd+ctrl+f" })
    #expect(shortcuts.contains { $0.action == .returnToNow && $0.key == "escape" })
    #expect(shortcuts.allSatisfy { !$0.key.isEmpty })
}
