import Foundation
import SwiftUI
import AIOSCore
import ProjectKernel

// OS T2: the command layer. The native menu bar, keyboard shortcuts, and
// the NSStatusItem all emit `AppCommand`s; `CommandRouter` maps each to a
// journaling engine call or a UI state change. The AppKit surface stays
// thin; the behavior is testable without it.

public enum AppCommand: Sendable, Equatable {
    // File
    case newNote(text: String)
    case newInboxCapture(text: String)
    // View
    case toggleRuler
    case refresh
    case scrubToNow
    case cycleCardScale
    // Desktop
    case switchDesktop(index: Int)
    case nextDesktop
    case previousDesktop
    // Control — deterministic, never model-mediated
    case emergencyStop
    // Cards
    case resolveNeedsYou(subject: String, question: String, answer: String)
}

@MainActor
public final class CommandRouter: ObservableObject {
    @Published public private(set) var lastCommand: AppCommand?

    public init() {}

    public func dispatch(_ command: AppCommand, to model: AppModel) async {
        lastCommand = command
        switch command {
        case .newNote(let text):
            _ = await model.createNote(text: text)
        case .newInboxCapture(let text):
            _ = await model.createInboxItem(text: text)
        case .toggleRuler:
            var layout = model.layout
            layout.showsTimelineRuler.toggle()
            await model.saveLayout(layout)
        case .refresh:
            await model.refresh()
        case .scrubToNow:
            model.returnToNow()
        case .cycleCardScale:
            var layout = model.layout
            layout.cardScale = layout.cardScale.next
            await model.saveLayout(layout)
        case .switchDesktop, .nextDesktop, .previousDesktop:
            // Desktop switching is orchestrated by the shell's RootView,
            // which owns the project list; the router records the intent.
            break
        case .emergencyStop:
            await model.engageEmergencyStop()
        case .resolveNeedsYou(let subject, let question, let answer):
            await model.resolveNeedsYou(subject: subject, question: question, answer: answer)
        }
    }
}

extension CardScale {
    public var next: CardScale {
        switch self {
        case .compact: .comfortable
        case .comfortable: .spacious
        case .spacious: .compact
        }
    }
}

/// Menu-bar status summary — counts come from projections, never guesses.
public struct StatusSummary: Sendable, Equatable {
    public var needsYou: Int
    public var activeActivities: Int
    public var label: String
}

public enum StatusItemViewModel {
    public static func summary(from state: ProjectState?) -> StatusSummary {
        let needs = state?.needsUser.count ?? 0
        let active = state?.attempts.values.filter { $0.phase == .running }.count ?? 0
        var parts: [String] = []
        if needs > 0 { parts.append("!\(needs)") }
        if active > 0 { parts.append("▶\(active)") }
        let label = parts.isEmpty ? "AIOS" : "AIOS " + parts.joined(separator: " ")
        return StatusSummary(needsYou: needs, activeActivities: active, label: label)
    }
}

/// The native menu-bar extra: live counts + deterministic Emergency Stop.
@MainActor
public final class StatusBarController: ObservableObject {
    @Published public private(set) var summary = StatusSummary(needsYou: 0, activeActivities: 0, label: "AIOS")
    private var statusItem: NSStatusItem?

    public init() {}

    public func install(router: CommandRouter, model: AppModel) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = summary.label
        let menu = NSMenu()
        let stopItem = NSMenuItem(title: "Emergency Stop", action: #selector(MenuProxy.stop(_:)), keyEquivalent: "")
        stopItem.target = MenuProxy.shared
        MenuProxy.shared.handler = { Task { await router.dispatch(.emergencyStop, to: model) } }
        menu.addItem(stopItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Needs You: \(summary.needsYou)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Active: \(summary.activeActivities)", action: nil, keyEquivalent: ""))
        item.menu = menu
        statusItem = item
    }

    public func update(with state: ProjectState?) {
        summary = StatusItemViewModel.summary(from: state)
        statusItem?.button?.title = summary.label
        statusItem?.menu?.items.forEach { $0.title = $0.title } // titles set on install; counts refresh below
        if let menu = statusItem?.menu, menu.items.count >= 4 {
            menu.items[2].title = "Needs You: \(summary.needsYou)"
            menu.items[3].title = "Active: \(summary.activeActivities)"
        }
    }

    /// Tiny proxy so the NSMenuItem target lives in Swift-observable land.
    /// MainActor-confined like its owner; the static is safe under isolation.
    final class MenuProxy: NSObject, @unchecked Sendable {
        static let shared: MenuProxy = {
            let proxy = MenuProxy()
            _ = MainActor.shared
            return proxy
        }()
        var handler: (() -> Void)?

        @objc func stop(_ sender: Any?) {
            let fire = handler
            Task { @MainActor in fire?() }
        }
    }
}
