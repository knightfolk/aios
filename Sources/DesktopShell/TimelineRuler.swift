import Foundation
import AIOSCore
import EventJournal
import ProjectKernel

// Step 2: the timeline as a living surface. The ruler is a pure projection
// of journal events; branch lanes show every lineage explicitly (docs 06:
// concurrent branches as lanes, never one false global percentage).

public struct TimelineMark: Sendable, Equatable, Identifiable {
    public var id: UInt64 { sequence }
    public var sequence: UInt64
    public var label: String

    public init(sequence: UInt64, label: String) {
        self.sequence = sequence
        self.label = label
    }
}

public struct BranchLane: Sendable, Equatable, Identifiable {
    public var id: String { branchID ?? "mainline" }
    /// nil for the mainline.
    public var branchID: String?
    public var startsAtSequence: UInt64
    public var endsAtSequence: UInt64?
    public var label: String

    public init(branchID: String?, startsAtSequence: UInt64, endsAtSequence: UInt64?, label: String) {
        self.branchID = branchID
        self.startsAtSequence = startsAtSequence
        self.endsAtSequence = endsAtSequence
        self.label = label
    }
}

public struct TimelineRuler: Sendable, Equatable {
    public var totalEvents: UInt64
    public var marks: [TimelineMark]
    public var lanes: [BranchLane]
}

public enum TimelineRulerViewModel {
    public static func build(from journal: JournalStore) -> TimelineRuler {
        let replay = (try? JournalReader.readAllEvents(at: journal.journalFileURL)) ?? .init(records: [], tornTail: false)
        let records = replay.records
        var marks: [TimelineMark] = []
        var lanes: [BranchLane] = [BranchLane(branchID: nil, startsAtSequence: 1, endsAtSequence: nil, label: "mainline")]

        for record in records {
            switch record.event {
            case .goalCreated:
                marks.append(TimelineMark(sequence: record.sequence, label: "Goal"))
            case .goalCompleted:
                marks.append(TimelineMark(sequence: record.sequence, label: "Goal done"))
            case .taskCreated:
                marks.append(TimelineMark(sequence: record.sequence, label: "Task"))
            case .verificationPassed:
                marks.append(TimelineMark(sequence: record.sequence, label: "Verified"))
            case .verificationFailed:
                marks.append(TimelineMark(sequence: record.sequence, label: "Verification failed"))
            case .checkpointCreated(let p):
                marks.append(TimelineMark(sequence: record.sequence, label: "Checkpoint"))
                _ = p
            case .branchCreated(let p):
                marks.append(TimelineMark(sequence: record.sequence, label: "Branch"))
                lanes.append(BranchLane(
                    branchID: p.newPlanRevisionID.rawValue.uuidString,
                    startsAtSequence: record.sequence,
                    endsAtSequence: nil,
                    label: "branch: \(p.reason)"
                ))
            case .restoredFromCheckpoint:
                marks.append(TimelineMark(sequence: record.sequence, label: "Restored"))
            case .workerCrashed:
                marks.append(TimelineMark(sequence: record.sequence, label: "Crash"))
            case .workerRecovered:
                marks.append(TimelineMark(sequence: record.sequence, label: "Recovered"))
            case .evidenceCreated:
                marks.append(TimelineMark(sequence: record.sequence, label: "Evidence"))
            default:
                break
            }
        }
        return TimelineRuler(totalEvents: UInt64(records.count), marks: marks, lanes: lanes)
    }

    /// The mark closest to a scrub position — snaps the playhead to
    /// meaningful history.
    public static func nearestMark(to sequence: UInt64, in marks: [TimelineMark]) -> TimelineMark? {
        guard !marks.isEmpty else { return nil }
        return marks.min { lhs, rhs in
            abs(Int64(lhs.sequence) - Int64(sequence)) < abs(Int64(rhs.sequence) - Int64(sequence))
        }
    }
}
