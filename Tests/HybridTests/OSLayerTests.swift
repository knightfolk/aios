import Foundation
import Testing
@testable import AIOSCore
@testable import DesktopShell
@testable import EventJournal

@Test func desktopSessionRoundTripsAndIsolatesPerProject() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-session-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let a = ProjectID()
    let b = ProjectID()
    let store = DesktopSessionStore(storageRoot: root)

    var sessionA = DesktopSession.default
    sessionA.selectedExpert = "linus"
    sessionA.expandedPanels = ["needs-you", "checkpoints"]
    sessionA.lastScrubSequence = 42
    sessionA.cardOrder = ["timeline", "needs-you", "health"]
    try store.save(sessionA, for: a)

    let loadedA = try store.load(for: a)
    #expect(loadedA == sessionA)

    // Another project is fully isolated: defaults, untouched.
    let loadedB = try store.load(for: b)
    #expect(loadedB == DesktopSession.default)
}

@Test func cardOrderingPinsFirstAndReordersStably() {
    let layout = CardOrdering(
        order: ["health", "timeline", "notes"],
        pinned: ["timeline", "unknown-card"]
    )

    // Pinned cards float to the front (in pinned order); unseen cards
    // append after ordered ones; unknown pinned entries are ignored.
    let rendered = CardOrdering.sorted(
        available: ["timeline", "needs-you", "health", "notes", "future"],
        ordering: layout
    )
    #expect(rendered.first == "timeline")
    #expect(rendered.contains("health"))
    #expect(rendered.contains("needs-you"))
    #expect(rendered.count == 5)

    // Drop-to-reorder is a pure function: move "needs-you" after "notes".
    let reordered = CardOrdering.move("needs-you", toAfter: "notes", in: rendered)
    #expect(reordered.firstIndex(of: "needs-you")! > reordered.firstIndex(of: "notes")!)
    #expect(Set(reordered) == Set(rendered))
    #expect(reordered.count == rendered.count)
}


@MainActor
@Test func dragReorderPersistsAcrossDesktopSwitch() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-dnd-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    let model = AppModel(store: journal)

    await model.saveCardOrder(["Timeline", "Needs You", "Artifacts", "Findings"])
    let reloaded = AppModel(store: try JournalStore(projectID: journal.projectID, rootDirectory: root))
    #expect(reloaded.session.cardOrder == ["Timeline", "Needs You", "Artifacts", "Findings"])

    // Scrub position also persists per desktop.
    model.enterHistorical(at: 3)
    try await Task.sleep(for: .milliseconds(150))
    let again = AppModel(store: try JournalStore(projectID: journal.projectID, rootDirectory: root))
    #expect(again.session.lastScrubSequence == 3)
}
