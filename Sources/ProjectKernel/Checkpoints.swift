import Foundation
import AIOSCore
import EventJournal

/// Checkpoints record enough position to branch or restore from. They are
/// pointers into the journal, not copies of reality: restoring never claims
/// to undo external side effects (docs 05).
public struct CheckpointRecord: Codable, Sendable, Hashable {
    public var checkpointID: String
    public var atSequence: UInt64
    public var note: String
    public var artifactRefs: [String]

    public init(checkpointID: String, atSequence: UInt64, note: String, artifactRefs: [String]) {
        self.checkpointID = checkpointID
        self.atSequence = atSequence
        self.note = note
        self.artifactRefs = artifactRefs
    }
}

public actor CheckpointStore {
    private let journal: JournalStore

    public init(journal: JournalStore) {
        self.journal = journal
    }

    @discardableResult
    public func createCheckpoint(note: String, artifactRefs: [String]) async throws -> CheckpointRecord {
        let state = try Projection.replayAll(journal)
        let id = "cp-\(UUID().uuidString.prefix(8))"
        let record = CheckpointRecord(
            checkpointID: id,
            atSequence: state.lastSequence,
            note: note,
            artifactRefs: artifactRefs
        )
        try await journal.append(.checkpointCreated(.init(checkpointID: id, note: note)))
        return record
    }

    /// Creates a new execution lineage from a checkpoint: a fresh
    /// PlanRevision recorded via `branchCreated`. Explicit, journaled.
    @discardableResult
    public func branch(from checkpointID: String, reason: String) async throws -> PlanRevisionID {
        let state = try Projection.replayAll(journal)
        guard state.checkpoints.contains(checkpointID) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "checkpoint \(checkpointID)"])
        }
        guard let previous = state.activePlanRevisionID else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "active plan revision"])
        }
        let newRevision = PlanRevisionID()
        try await journal.append(.branchCreated(.init(
            fromCheckpointID: checkpointID,
            newPlanRevisionID: newRevision,
            previousPlanRevisionID: previous,
            reason: reason
        )))
        return newRevision
    }

    /// Explicit restore. The note must describe the local changes the user
    /// reviewed — the engine surfaces it; it never rewrites history.
    public func restore(checkpointID: String, note: String) async throws {
        let state = try Projection.replayAll(journal)
        guard state.checkpoints.contains(checkpointID) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "checkpoint \(checkpointID)"])
        }
        try await journal.append(.restoredFromCheckpoint(.init(
            checkpointID: checkpointID,
            note: "local changes reviewed: \(note)"
        )))
    }

    public func list() throws -> [CheckpointRecord] {
        let state = try Projection.replayAll(journal)
        return state.checkpoints.map { id in
            CheckpointRecord(checkpointID: id, atSequence: 0, note: "", artifactRefs: [])
        }
    }
}
