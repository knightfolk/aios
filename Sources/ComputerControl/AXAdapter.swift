import Foundation
import AppKit
@preconcurrency import ApplicationServices
import AIOSCore

/// Accessibility-first adapter (docs 08 preference order): activate apps via
/// NSWorkspace, read and type through the AX element tree. Real execution —
/// requires the runner to hold the Accessibility trust; `isAvailable`
/// reports honestly instead of pretending.
public struct AXAdapter: InteractionAdapter {
    public var name: String { "accessibility" }

    public init() {}

    public func isAvailable() async -> Bool {
        AXIsProcessTrustedWithOptions(Self.trustOptions())
    }

    private static func trustOptions() -> CFDictionary {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return [key: false] as CFDictionary
    }

    public func perform(_ intent: ChloeIntent) async throws -> ChloeResult {
        switch intent.action {
        case .activateApp:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: intent.target) else {
                return ChloeResult(executed: false, detail: "no app with bundle id \(intent.target)")
            }
            let config = NSWorkspace.OpenConfiguration()
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            return ChloeResult(executed: true, detail: "activated \(app.bundleIdentifier ?? intent.target)")

        case .readFocusedElement:
            let element = try focusedElement()
            let title = (try? stringAttribute(kAXTitleAttribute, of: element)) ?? ""
            let value = (try? stringAttribute(kAXValueAttribute, of: element)) ?? ""
            return ChloeResult(executed: true, detail: "focused: title=\(title) value=\(value)")

        case .typeText:
            guard let text = intent.parameters["text"] else {
                return ChloeResult(executed: false, detail: "typeText requires a text parameter")
            }
            let element = try focusedElement()
            let existing = (try? stringAttribute(kAXValueAttribute, of: element)) ?? ""
            let newValue = existing + text
            let error = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFTypeRef)
            guard error == .success else {
                return ChloeResult(executed: false, detail: "AX set value failed: \(error.rawValue)")
            }
            return ChloeResult(executed: true, detail: "typed \(text.count) chars into focused element")

        case .clickElement:
            // Click via AXPress on a resolved element; resolution by AX
            // identifier arrives with the selector engine. Honest refusal
            // until then.
            return ChloeResult(executed: false, detail: "clickElement pending AX selector resolution; refusing rather than guessing")
        }
    }

    private func focusedElement() throws -> AXUIElement {
        let systemWide = AXUIElementCreateSystemWide()
        var element: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &element)
        guard error == .success, let element else {
            throw NSError(domain: "AXAdapter", code: Int(error.rawValue), userInfo: [
                NSLocalizedDescriptionKey: "no focused element (error \(error.rawValue))",
            ])
        }
        return element as! AXUIElement
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) throws -> String {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else { return "" }
        return value as? String ?? ""
    }
}

/// ScreenCaptureKit observation seam (docs 08 / Phase 4 vision support).
/// The pixel path is the LAST resort; until the real SCStream wiring lands
/// with its permission model, this adapter is honestly unavailable.
public struct ScreenCaptureObserver {
    public enum Availability: Sendable, Equatable {
        case available
        case requiresPermission
        case notImplemented
    }

    public init() {}

    public func availability() -> Availability {
        .notImplemented
    }
}
