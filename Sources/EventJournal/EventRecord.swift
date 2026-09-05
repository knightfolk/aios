import Foundation
import AIOSCore

/// One immutable journaled transition. The sequence is strictly monotonic
/// within a project's journal.
public struct EventRecord: Codable, Sendable, Hashable {
    public var sequence: UInt64
    public var recordedAt: Date
    public var projectID: ProjectID
    public var event: EngineEvent

    public init(sequence: UInt64, recordedAt: Date, projectID: ProjectID, event: EngineEvent) {
        self.sequence = sequence
        self.recordedAt = recordedAt
        self.projectID = projectID
        self.event = event
    }
}
