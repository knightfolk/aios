import Foundation
import AIOSCore

/// Evidence-based project status (docs 06): concrete coverage fields only.
/// `compositeScore` is intentionally always nil — no fake confidence number.
public struct ProjectHealth: Sendable, Equatable {
    public var goalCriteriaTotal: Int
    public var goalCriteriaCovered: Int
    public var verificationCoverage: Double
    public var blockers: Int
    public var unresolvedDecisions: Int
    public var suspectedGaps: Int
    public var staleEvidence: Int
    public var activeFailures: Int
    public var activeAttempts: Int
    public var compositeScore: Double? { nil }

    public init(
        goalCriteriaTotal: Int,
        goalCriteriaCovered: Int,
        verificationCoverage: Double,
        blockers: Int,
        unresolvedDecisions: Int,
        suspectedGaps: Int,
        staleEvidence: Int,
        activeFailures: Int,
        activeAttempts: Int
    ) {
        self.goalCriteriaTotal = goalCriteriaTotal
        self.goalCriteriaCovered = goalCriteriaCovered
        self.verificationCoverage = verificationCoverage
        self.blockers = blockers
        self.unresolvedDecisions = unresolvedDecisions
        self.suspectedGaps = suspectedGaps
        self.staleEvidence = staleEvidence
        self.activeFailures = activeFailures
        self.activeAttempts = activeAttempts
    }

    public static func compute(from state: ProjectState) -> ProjectHealth {
        let activeGoal = state.activeGoalRevisionID.flatMap { state.goals[$0] }
        let criteria = activeGoal?.acceptanceCriteria ?? []

        // Criteria coverage: a criterion counts as covered when at least one
        // valid verification-passed task exists whose evidence mentions it.
        // v1 heuristic: completed tasks with valid evidence cover criteria
        // positionally until richer linking exists — reported honestly as
        // coverage, not proof.
        let completedWithEvidence = state.tasks.values
            .filter { $0.state == .complete }
            .filter { task in
                state.attempts.values.contains { attempt in
                    attempt.taskID == task.taskID && attempt.outcome == .completed
                }
            }
            .count
        let covered = min(completedWithEvidence, criteria.count)

        let verificationRequirements = state.tasks.count
        let verifiedTasks = state.tasks.values.filter { $0.state == .complete }.count
        let verificationCoverage = verificationRequirements == 0
            ? 0.0
            : Double(verifiedTasks) / Double(verificationRequirements)

        let blockers = state.tasks.values.filter { $0.state == .blocked }.count
            + state.goals.values.filter { $0.blockedReason != nil }.count
        let staleEvidence = state.evidence.values
            .filter { $0.status == .stale || $0.status == .invalidated }
            .count
        let activeFailures = state.actions.values
            .filter { entry in
                guard let result = entry.result else { return false }
                return result.outcome == .failed
            }
            .count
        let activeAttempts = state.attempts.values.filter { $0.phase == .running }.count

        return ProjectHealth(
            goalCriteriaTotal: criteria.count,
            goalCriteriaCovered: covered,
            verificationCoverage: verificationCoverage,
            blockers: blockers,
            unresolvedDecisions: state.needsUser.count,
            suspectedGaps: state.warnings.count,
            staleEvidence: staleEvidence,
            activeFailures: activeFailures,
            activeAttempts: activeAttempts
        )
    }
}
