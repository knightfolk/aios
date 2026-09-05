import Foundation
import AIOSCore
import ProjectKernel

/// Timeline projection for the UI: Past, Now, Future, and Gaps are
/// semantically distinct (Constitution #21) and derived — never invented.
public enum TimelineSegmentKind: String, CaseIterable, Sendable {
    case past = "PAST"
    case now = "NOW"
    case future = "FUTURE"
    case gaps = "GAPS"
}

public struct TimelineSegment: Sendable, Equatable, Identifiable {
    public var id: String { kind.rawValue }
    public var kind: TimelineSegmentKind
    public var count: Int
    public var detail: String

    public init(kind: TimelineSegmentKind, count: Int, detail: String) {
        self.kind = kind
        self.count = count
        self.detail = detail
    }
}

public enum TimelineViewModel {
    public static func segments(from state: ProjectState) -> [TimelineSegment] {
        let completed = state.tasks.values.filter { $0.state == .complete }.count
        let running = state.attempts.values.filter { $0.phase == .running }.count
        let planned = state.tasks.values.filter { $0.state == .pending || $0.state == .ready }.count
        let gaps = state.warnings.count
            + state.evidence.values.filter { $0.status == .stale }.count

        return [
            TimelineSegment(kind: .past, count: completed, detail: "recorded, verified history"),
            TimelineSegment(kind: .now, count: running, detail: "live execution"),
            TimelineSegment(kind: .future, count: planned, detail: "projected plan — has not happened"),
            TimelineSegment(kind: .gaps, count: gaps, detail: "suspected missing work"),
        ]
    }
}

/// Card grammar (docs 06): every card maps to real projected state. No
/// decorative panels, no fake telemetry.
public struct CardSummary: Sendable, Equatable, Identifiable {
    public var id: String { title }
    public var title: String
    public var body: String
    public var whyHere: String
}

public enum CardGridViewModel {
    public static func cards(from state: ProjectState) -> [CardSummary] {
        var cards: [CardSummary] = []

        let tasks = state.tasks.values.sorted { $0.state.rawValue < $1.state.rawValue }
        for task in tasks.prefix(6) {
            cards.append(CardSummary(
                title: "Task",
                body: "\(task.objective) — \(task.state.rawValue.lowercased())",
                whyHere: "owned unit of work"
            ))
        }

        let running = state.attempts.values.filter { $0.phase == .running }
        for attempt in running {
            cards.append(CardSummary(
                title: "Activity",
                body: "\(attempt.worker?.workerID ?? "worker") executing",
                whyHere: "monitorable live process"
            ))
        }

        if !state.needsUser.isEmpty {
            cards.append(CardSummary(
                title: "Needs You",
                body: "\(state.needsUser.count) item(s): \(state.needsUser.map(\.subject).joined(separator: ", "))",
                whyHere: "blocked on a human decision"
            ))
        }

        if !state.warnings.isEmpty {
            cards.append(CardSummary(
                title: "Findings",
                body: state.warnings.prefix(3).joined(separator: " · "),
                whyHere: "engine-reported issues and suspected gaps"
            ))
        }

        if !state.artifacts.isEmpty {
            cards.append(CardSummary(
                title: "Artifacts",
                body: "\(state.artifacts.count) tracked revision(s)",
                whyHere: "produced work products"
            ))
        }

        return cards
    }
}
