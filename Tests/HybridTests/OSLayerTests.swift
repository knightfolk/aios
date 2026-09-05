import Foundation
import Testing
@testable import AIOSCore
@testable import DesktopShell

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
