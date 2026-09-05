import Foundation
import EventJournal

/// Emergency Stop: local, deterministic, always responsive, and completely
/// independent of language models (docs 08). Engaging journals the
/// intervention exactly once and latches until explicitly cleared by the
/// host application.
public actor EmergencyStop {
    private let journal: JournalStore
    private var engagedState = false

    public init(journal: JournalStore) {
        self.journal = journal
    }

    public var engaged: Bool { engagedState }

    public func engage(reason: String) async throws {
        guard !engagedState else { return }
        engagedState = true
        try await journal.append(.userIntervened(.init(
            intervention: "Emergency Stop engaged: \(reason)"
        )))
    }

    /// Host-side clear after the operator has dealt with the situation.
    public func clear() {
        engagedState = false
    }
}
