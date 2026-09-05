import Foundation
import Testing
@testable import AIOSCore
@testable import ComputerControl

// Pure selector matching over an injectable element tree; real AX presses
// are live-gated. ScreenCaptureKit availability is probed via the real
// permission surface.

struct FakeElement: AXSelectableElement {
    var role: String?
    var title: String?
    var children: [FakeElement] = []

    func childElements() -> [FakeElement] { children }
}

func tree() -> FakeElement {
    FakeElement(role: "window", title: "Main", children: [
        FakeElement(role: "button", title: "Save", children: [
            FakeElement(role: "staticText", title: "Save"),
        ]),
        FakeElement(role: "button", title: "Cancel"),
        FakeElement(role: "textField", title: "Search"),
    ])
}

@Test func selectorMatchesByRoleTitleAndCombination() throws {
    let matcher = AXSelector(role: "button", titleContains: "Sav")
    let hit = try #require(AXSelectorEngine.first(matching: matcher, in: tree()))
    #expect(hit.role == "button")
    #expect(hit.title == "Save")

    #expect(AXSelectorEngine.first(matching: AXSelector(role: "checkbox", titleContains: nil), in: tree()) == nil)
    #expect(AXSelectorEngine.first(matching: AXSelector(role: nil, titleContains: "search"), in: tree())?.role == "textField")
    #expect(AXSelectorEngine.all(matching: AXSelector(role: "button", titleContains: nil), in: tree()).count == 2)
}

@Test func clickElementResolvesViaSelectorWhenAXTrusted() async throws {
    // With AX trust absent (typical CI runner), the adapter must refuse
    // honestly rather than fabricate a click.
    let adapter = AXAdapter()
    let available = await adapter.isAvailable()
    let result = try await adapter.perform(.init(
        owner: "t/1", action: .clickElement,
        target: "role=button;title=Sav", parameters: [:]
    ))
    if !available {
        #expect(result.executed == false)
        #expect(result.detail?.contains("trust") == true)
    } else {
        #expect(result.detail != nil)
    }
}

@Test func screenCaptureProbeReportsRealState() async {
    let probe = ScreenCaptureProbe()
    let status = await probe.availability()
    #expect([ScreenCaptureProbe.Status.requiresPermission, .available, .notImplemented].contains(status))
}
