import Foundation
import AIOSCore
import EventJournal
import ProjectKernel

/// Creates revision-bound evidence and runs the staleness cascade when
/// artifacts change after verification.
public actor EvidenceRecorder {
    private let journal: JournalStore

    public init(journal: JournalStore) {
        self.journal = journal
    }

    public func record(evidence: Evidence) async throws {
        try await journal.append(.evidenceCreated(.init(evidence: evidence)))
    }

    public func invalidate(evidenceID: EvidenceID, reason: String) async throws {
        try await journal.append(.evidenceInvalidated(.init(evidenceID: evidenceID, reason: reason, mark: .invalidated)))
    }

    public func recordArtifact(
        artifactID: ArtifactID,
        kind: ArtifactKind,
        path: String,
        revision: String,
        contentHash: String
    ) async throws {
        try await journal.append(.artifactCreated(.init(
            artifactID: artifactID, kind: kind, path: path, revision: revision, contentHash: contentHash
        )))
    }

    /// Records a new revision of an artifact and invalidates every piece of
    /// evidence still bound to an older revision of that artifact.
    public func recordArtifactChange(artifactID: ArtifactID, newRevision: String, contentHash: String) async throws {
        let state = try Projection.replayAll(journal)

        try await journal.append(.artifactChanged(.init(
            artifactID: artifactID, newRevision: newRevision, contentHash: contentHash
        )))

        for (evidenceID, evidence) in state.evidence where evidence.status == .valid {
            let boundToOldRevision = evidence.artifactRevisionRefs.contains { ref in
                ref.artifactID == artifactID && ref.revision != newRevision
            }
            if boundToOldRevision {
                try await journal.append(.evidenceInvalidated(.init(
                    evidenceID: evidenceID,
                    reason: "artifact \(artifactID) changed to revision \(newRevision) after verification",
                    mark: .stale
                )))
            }
        }
    }
}
