import Foundation
import AIOSCore
import EventJournal
import ProjectKernel

// Concierge front-desk routing (docs 07): deterministic v1. Prefixes name
// the destination; anything unrecognized lands in the Project Inbox —
// captured, never guessed. Question routing requires a model brain, which
// the runtime does not assume: questions surface as Needs You entries.

public enum ConciergeDestination: String, Sendable, Equatable {
    case goal
    case note
    case inbox
    case question
}

public struct ConciergeRouting: Sendable, Equatable {
    public var destination: ConciergeDestination
    public var payload: String
}

public enum ConciergeRouter {
    public static func route(_ raw: String) -> ConciergeRouting? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ConciergeRouting(destination: .inbox, payload: "")
        }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("goal:") {
            return ConciergeRouting(destination: .goal, payload: payload(after: "goal:", in: trimmed))
        }
        if lowered.hasPrefix("note:") {
            return ConciergeRouting(destination: .note, payload: payload(after: "note:", in: trimmed))
        }
        if lowered.hasPrefix("inbox:") {
            return ConciergeRouting(destination: .inbox, payload: payload(after: "inbox:", in: trimmed))
        }
        if lowered.hasPrefix("ask:") {
            return ConciergeRouting(destination: .question, payload: payload(after: "ask:", in: trimmed))
        }
        return ConciergeRouting(destination: .inbox, payload: trimmed)
    }

    /// Applies a routing: goals journal `goalCreated`, notes are stored and
    /// promoted, questions journal a Needs You decision, everything else
    /// lands in the inbox store.
    public static func deliver(
        _ raw: String,
        journal: JournalStore,
        notes: NotesStore,
        inbox: InboxStore
    ) async throws {
        guard let routing = route(raw) else { return }
        switch routing.destination {
        case .goal:
            try await journal.append(.goalCreated(.init(
                goalRevisionID: GoalRevisionID(),
                originalRequest: routing.payload,
                objective: routing.payload,
                acceptanceCriteria: []
            )))
        case .note:
            let note = try await notes.create(text: routing.payload)
            try await notes.promote(noteID: note.id, target: "TIMELINE_PIN", summary: routing.payload)
        case .inbox:
            _ = try await inbox.create(text: routing.payload)
        case .question:
            try await journal.append(.decisionRequested(.init(
                subject: "question", question: routing.payload, blocking: false
            )))
        }
    }

    private static func payload(after prefix: String, in text: String) -> String {
        let lowered = text.lowercased()
        guard let range = lowered.range(of: prefix) else { return text }
        return String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }
}

/// Declared keyboard-first shortcuts (docs 06 accessibility: structured,
/// non-spatial alternatives). The view layer binds these; tests pin the map.
public enum KeyboardAction: Sendable, Equatable {
    case switchProject(Int)
    case fullScreen
    case returnToNow
}

public struct KeyboardShortcut: Sendable, Equatable {
    public var key: String
    public var action: KeyboardAction
}

public enum KeyboardShortcuts {
    public static let all: [KeyboardShortcut] = [
        .init(key: "cmd+1", action: .switchProject(0)),
        .init(key: "cmd+2", action: .switchProject(1)),
        .init(key: "cmd+3", action: .switchProject(2)),
        .init(key: "cmd+ctrl+f", action: .fullScreen),
        .init(key: "escape", action: .returnToNow),
    ]
}
