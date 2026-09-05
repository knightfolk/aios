import Foundation
import ApplicationServices
import ScreenCaptureKit
import AIOSCore

// Chloe depth (Item 4): a pure selector engine over an injectable element
// tree, real AXPress execution, and a real ScreenCaptureKit permission
// probe. Matching is testable offline; execution stays honest about trust.

public protocol AXSelectableElement {
    var role: String? { get }
    var title: String? { get }
    func childElements() -> [Self]
}

public struct AXSelector: Sendable, Equatable {
    public var role: String?
    public var titleContains: String?

    public init(role: String?, titleContains: String?) {
        self.role = role
        self.titleContains = titleContains
    }

    /// Parses selector strings like "role=button;title=Sav".
    public static func parse(_ raw: String) -> AXSelector {
        var role: String?
        var title: String?
        for pair in raw.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if key == "role" { role = value }
            if key == "title" { title = value }
        }
        return AXSelector(role: role, titleContains: title)
    }
}

public enum AXSelectorEngine {
    public static func matches<E: AXSelectableElement>(_ selector: AXSelector, element: E) -> Bool {
        if let role = selector.role, element.role?.localizedCaseInsensitiveCompare(role) != .orderedSame {
            return false
        }
        if let fragment = selector.titleContains {
            guard let title = element.title,
                  title.localizedCaseInsensitiveContains(fragment) else {
                return false
            }
        }
        return true
    }

    public static func all<E: AXSelectableElement>(matching selector: AXSelector, in root: E) -> [E] {
        var results: [E] = []
        if matches(selector, element: root) {
            results.append(root)
        }
        for child in root.childElements() {
            results.append(contentsOf: all(matching: selector, in: child))
        }
        return results
    }

    public static func first<E: AXSelectableElement>(matching selector: AXSelector, in root: E) -> E? {
        if matches(selector, element: root) { return root }
        for child in root.childElements() {
            if let hit = first(matching: selector, in: child) { return hit }
        }
        return nil
    }
}

/// Real AX element wrapper conforming to the selectable protocol; children
/// are loaded lazily by the accessibility API.
public struct AXElementNode: AXSelectableElement {
    let backing: AXUIElement

    public var role: String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(backing, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    public var title: String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(backing, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    public func childElements() -> [AXElementNode] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(backing, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return []
        }
        return children.map { AXElementNode(backing: $0) }
    }

    /// Real press via the AX API.
    public func press() -> Bool {
        AXUIElementPerformAction(backing, kAXPressAction as CFString) == .success
    }
}

extension AXAdapter {
    /// Resolves a selector against the focused application's tree and
    /// presses the first match. Requires the Accessibility trust.
    public func click(matching rawSelector: String) async -> ChloeResult {
        guard await isAvailable() else {
            return ChloeResult(executed: false, detail: "accessibility trust not granted; refusing to click")
        }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focused) == .success,
              let app = focused else {
            return ChloeResult(executed: false, detail: "no focused application")
        }
        let appNode = AXElementNode(backing: unsafeDowncast(app, to: AXUIElement.self))
        guard let hit = AXSelectorEngine.first(matching: AXSelector.parse(rawSelector), in: appNode) else {
            return ChloeResult(executed: false, detail: "selector matched no element: \(rawSelector)")
        }
        guard hit.press() else {
            return ChloeResult(executed: false, detail: "AXPress failed on matched element")
        }
        return ChloeResult(executed: true, detail: "pressed element matching \(rawSelector)")
    }
}

/// Real ScreenCaptureKit availability probe. Capture itself needs an
/// entitled app shell; the probe reports the actual permission state.
public struct ScreenCaptureProbe {
    public enum Status: Sendable, Equatable {
        case available
        case requiresPermission
        case notImplemented
    }

    public init() {}

    public func availability() async -> Status {
        // ScreenCaptureKit's authorization surfaces live behind
        // CGPreflightScreenCaptureAccess / CGRequestScreenCaptureAccess.
        if CGPreflightScreenCaptureAccess() {
            .available
        } else {
            .requiresPermission
        }
    }
}
