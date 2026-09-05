import Foundation
import Testing
@testable import AIOSCore
@testable import DesktopShell

// Step 3: layout persistence + design tokens. Layouts are per-project
// (docs 06: the desktop restores its layout when reopened); the design
// language is a typed token set applied across the shell.

@Test func projectLayoutRoundTripsWithPinnedCards() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-layout-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let projectID = ProjectID()
    let store = ProjectLayoutStore(storageRoot: root)

    var layout = ProjectLayout.default
    layout.pinnedCardIDs = ["needs-you", "timeline"]
    layout.cardScale = .comfortable
    try store.save(layout, for: projectID)

    let loaded = try store.load(for: projectID)
    #expect(loaded == layout)
    #expect(loaded.pinnedCardIDs.contains("needs-you"))

    // Per-project isolation: another project gets defaults.
    let other = try store.load(for: ProjectID())
    #expect(other == ProjectLayout.default)
}

@Test func designTokensAreConsistentAndDistinct() {
    // Semantic roles, not raw colors sprinkled through views.
    #expect(AIOSDesign.tokens.count >= 6)
    #expect(Set(AIOSDesign.tokens.map(\.role)).count == AIOSDesign.tokens.count) // unique roles
    #expect(AIOSDesign.token(.surfaceLive) != AIOSDesign.token(.surfaceHistory)) // past ≠ now
    #expect(AIOSDesign.spacingSteps.contains(8))
    #expect(AIOSDesign.fontRole("cardTitle").weight == .semibold)
}
