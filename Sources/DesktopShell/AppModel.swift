import Foundation
import SwiftUI
import AIOSCore
import EventJournal
import ProjectKernel

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var state: ProjectState?
    /// Non-nil while scrubbing history: the read-only reconstructed state.
    @Published public private(set) var historicalState: ProjectState?
    @Published public private(set) var stopEngaged = false
    @Published public private(set) var lastRouting: String?
    @Published public private(set) var layout: ProjectLayout = .default
    @Published public private(set) var session: DesktopSession = .default

    public let projectID: ProjectID
    private let store: JournalStore
    /// Read-only handle for ruler/projection builders.
    public var storeForRuler: JournalStore { store }
    public let emergencyStop: EmergencyStop
    private let notes: NotesStore
    private let inbox: InboxStore

    public init(store: JournalStore) {
        self.store = store
        self.projectID = store.projectID
        self.emergencyStop = EmergencyStop(journal: store)
        self.notes = NotesStore(journal: store, storageRoot: store.rootDirectory)
        self.inbox = InboxStore(journal: store, storageRoot: store.rootDirectory)
        self.checkpoints = CheckpointStore(journal: store)
        self.layoutStore = ProjectLayoutStore(storageRoot: store.rootDirectory)
        if let stored = try? layoutStore.load(for: store.projectID) {
            layout = stored
        }
        self.sessionStore = DesktopSessionStore(storageRoot: store.rootDirectory)
        if let storedSession = try? sessionStore.load(for: store.projectID) {
            session = storedSession
        }
    }

    private let layoutStore: ProjectLayoutStore
    private let sessionStore: DesktopSessionStore

    /// Drag-and-drop persistence: the new arrangement lands in the session.
    public func saveCardOrder(_ order: [String]) async {
        var updated = session
        updated.cardOrder = order
        session = updated
        try? sessionStore.save(updated, for: store.projectID)
    }

    public func saveScrubPosition(_ sequence: UInt64?) async {
        var updated = session
        updated.lastScrubSequence = sequence
        session = updated
        try? sessionStore.save(updated, for: store.projectID)
    }

    public func saveLayout(_ newLayout: ProjectLayout) async {
        layout = newLayout
        try? layoutStore.save(newLayout, for: store.projectID)
    }

    /// Concierge front desk: deterministic routing, journaled effects.
    public func submitConcierge(_ raw: String) async {
        guard let routing = ConciergeRouter.route(raw) else { return }
        lastRouting = "\(routing.destination.rawValue): \(routing.payload)"
        try? await ConciergeRouter.deliver(raw, journal: store, notes: notes, inbox: inbox)
        await refresh()
    }

    // MARK: - Interactive card actions (each maps to a journaling engine call)

    private let checkpoints: CheckpointStore

    public func resolveNeedsYou(subject: String, question: String, answer: String) async {
        try? await store.append(.needsYouResolved(.init(subject: subject, question: question, answer: answer)))
        await refresh()
    }

    @discardableResult
    public func createNote(text: String) async -> NoteRecord {
        (try? await notes.create(text: text)) ?? NoteRecord(id: "note-error", text: text, createdAt: Date())
    }

    public func promoteNote(id: String, target: String) async {
        let summary = (await loadNotes()).first { $0.id == id }?.text ?? ""
        try? await notes.promote(noteID: id, target: target, summary: String(summary.prefix(120)))
        await refresh()
    }

    @discardableResult
    public func createInboxItem(text: String) async -> InboxItemRecord {
        (try? await inbox.create(text: text)) ?? InboxItemRecord(id: "inb-error", text: text, createdAt: Date())
    }

    public func promoteInboxItem(id: String, target: String) async {
        let summary = (await loadInbox()).first { $0.id == id }?.text ?? ""
        try? await inbox.promote(itemID: id, target: target, summary: String(summary.prefix(120)))
        await refresh()
    }

    public func loadNotes() async -> [NoteRecord] {
        (try? await notes.load()) ?? []
    }

    public func loadInbox() async -> [InboxItemRecord] {
        (try? await inbox.load()) ?? []
    }

    @discardableResult
    public func createCheckpoint(note: String) async -> CheckpointRecord {
        (try? await checkpoints.createCheckpoint(note: note, artifactRefs: []))
            ?? CheckpointRecord(checkpointID: "cp-error", atSequence: 0, note: note, artifactRefs: [])
    }

    @discardableResult
    public func branchFrom(checkpointID: String, reason: String) async -> PlanRevisionID? {
        let result = try? await checkpoints.branch(from: checkpointID, reason: reason)
        await refresh()
        return result ?? nil
    }

    public func restore(checkpointID: String, note: String) async {
        try? await checkpoints.restore(checkpointID: checkpointID, note: note)
        await refresh()
    }

    /// Stop control for a live activity: deterministic, journaled, no models.
    public func cancelAttempt(attemptID: AttemptID, reason: String) async {
        try? await store.append(.userIntervened(.init(
            intervention: "stop requested for attempt \(attemptID.rawValue.uuidString.prefix(8)): \(reason)"
        )))
        await refresh()
    }

    public func refresh() async {
        // Snapshot-accelerated: folds only records past the snapshot
        // checkpoint instead of replaying the whole journal.
        state = try? Projection.loadUsingSnapshot(store)
        stopEngaged = await emergencyStop.engaged
    }

    /// Scrub to a journal position: pure prefix replay, never a rollback.
    public func enterHistorical(at sequence: UInt64) {
        historicalState = try? Projection.state(at: sequence, of: store)
        Task { await saveScrubPosition(sequence) }
    }

    public func returnToNow() {
        historicalState = nil
        Task { await saveScrubPosition(nil) }
    }

    /// The state the UI should render: historical when scrubbing, live now.
    public var displayState: ProjectState? {
        historicalState ?? state
    }

    /// Deterministic emergency path — no models involved.
    public func engageEmergencyStop() async {
        try? await emergencyStop.engage(reason: "user pressed the stop control")
        await refresh()
    }
}
