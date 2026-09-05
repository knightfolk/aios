import Foundation
import AIOSCore
import ProjectKernel

// Pure view models for the Phase 3 panels. Everything derives from
// projections; nothing invents state.

public struct NeedsYouSummary: Sendable, Equatable {
    public var active: [NeedsYouEntry]
    public var resolvedCount: Int
}

public enum NeedsYouViewModel {
    public static func summary(from state: ProjectState) -> NeedsYouSummary {
        NeedsYouSummary(active: state.needsUser, resolvedCount: state.resolvedNeedsYou.count)
    }
}

public enum HealthViewModel {
    /// Concrete coverage lines (docs 06); no composite score line exists.
    public static func lines(from health: ProjectHealth) -> [String] {
        [
            "Goal criteria covered: \(health.goalCriteriaCovered)/\(health.goalCriteriaTotal)",
            String(format: "Verification coverage: %.0f%%", health.verificationCoverage * 100),
            "Blockers: \(health.blockers)",
            "Unresolved decisions: \(health.unresolvedDecisions)",
            "Suspected gaps: \(health.suspectedGaps)",
            "Stale/invalidated evidence: \(health.staleEvidence)",
            "Active failures: \(health.activeFailures)",
            "Live attempts: \(health.activeAttempts)",
        ]
    }
}

public struct FutureItem: Sendable, Equatable, Identifiable {
    public var id: TaskID
    public var objective: String
    public var owner: ExpertRole
    public var dependencyCount: Int
}

public enum FutureViewModel {
    /// The projected future: the active plan's not-yet-started tasks.
    /// Explicitly a projection — it has not happened (Constitution #21).
    public static func items(from state: ProjectState) -> [FutureItem] {
        state.tasks.values
            .filter { $0.state == .pending || $0.state == .ready }
            .sorted { $0.objective < $1.objective }
            .map { task in
                FutureItem(
                    id: task.taskID,
                    objective: task.objective,
                    owner: task.owner,
                    dependencyCount: task.dependencies.count
                )
            }
    }
}

public struct ScrubPosition: Sendable, Equatable {
    public var sequence: UInt64
    public var lastSequence: UInt64

    public var isHistorical: Bool { sequence < lastSequence }
}
