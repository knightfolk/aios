import Foundation
import AIOSCore

/// Typed engine events (docs 05 event list). Every meaningful engine
/// transition is journaled as one of these; the enum case is the event kind
/// and its associated value is the typed payload.
public enum EngineEvent: Codable, Sendable, Hashable {
    case projectOpened
    case goalCreated(GoalCreatedPayload)
    case goalRevised(GoalRevisedPayload)
    case planProposed(PlanProposedPayload)
    case planRevised(PlanRevisedPayload)
    case taskCreated(TaskCreatedPayload)
    case taskStateChanged(TaskStateChangedPayload)
    case attemptStarted(AttemptStartedPayload)
    case attemptEnded(AttemptEndedPayload)
    case modelSelected(ModelSelectedPayload)
    case contextCompiled(ContextCompiledPayload)
    case actionRequested(ActionRequestedPayload)
    case actionAuthorized(ActionAuthorizedPayload)
    case actionExecuted(ActionExecutedPayload)
    case actionReconciled(ActionReconciledPayload)
    case artifactCreated(ArtifactCreatedPayload)
    case artifactChanged(ArtifactChangedPayload)
    case evidenceCreated(EvidenceCreatedPayload)
    case evidenceInvalidated(EvidenceInvalidatedPayload)
    case verificationStarted(VerificationStartedPayload)
    case verificationPassed(VerificationPassedPayload)
    case verificationFailed(VerificationFailedPayload)
    case verificationInconclusive(VerificationInconclusivePayload)
    case decisionRequested(DecisionRequestedPayload)
    case userIntervened(UserIntervenedPayload)
    case checkpointCreated(CheckpointCreatedPayload)
    case workerCrashed(WorkerCrashedPayload)
    case workerRecovered(WorkerRecoveredPayload)
    case goalCompleted(GoalCompletedPayload)
    case goalBlocked(GoalBlockedPayload)
    case needsYouResolved(NeedsYouResolvedPayload)
    case notePromoted(NotePromotedPayload)
    case inboxItemPromoted(InboxItemPromotedPayload)
    case branchCreated(BranchCreatedPayload)
    case restoredFromCheckpoint(RestoredFromCheckpointPayload)
}

public struct NeedsYouResolvedPayload: Codable, Sendable, Hashable {
    public var subject: String
    public var question: String
    public var answer: String
    public var resolvedAt: Date

    public init(subject: String, question: String, answer: String, resolvedAt: Date = Date()) {
        self.subject = subject
        self.question = question
        self.answer = answer
        self.resolvedAt = resolvedAt
    }
}

public struct NotePromotedPayload: Codable, Sendable, Hashable {
    public var noteID: String
    /// GOAL | TASK | TIMELINE_PIN
    public var target: String
    public var summary: String

    public init(noteID: String, target: String, summary: String) {
        self.noteID = noteID
        self.target = target
        self.summary = summary
    }
}

public struct InboxItemPromotedPayload: Codable, Sendable, Hashable {
    public var itemID: String
    /// GOAL | TASK | TIMELINE_PIN | DISCARDED
    public var target: String
    public var summary: String

    public init(itemID: String, target: String, summary: String) {
        self.itemID = itemID
        self.target = target
        self.summary = summary
    }
}

public struct BranchCreatedPayload: Codable, Sendable, Hashable {
    public var fromCheckpointID: String
    public var newPlanRevisionID: PlanRevisionID
    public var previousPlanRevisionID: PlanRevisionID
    public var reason: String

    public init(fromCheckpointID: String, newPlanRevisionID: PlanRevisionID, previousPlanRevisionID: PlanRevisionID, reason: String) {
        self.fromCheckpointID = fromCheckpointID
        self.newPlanRevisionID = newPlanRevisionID
        self.previousPlanRevisionID = previousPlanRevisionID
        self.reason = reason
    }
}

public struct RestoredFromCheckpointPayload: Codable, Sendable, Hashable {
    public var checkpointID: String
    public var note: String

    public init(checkpointID: String, note: String) {
        self.checkpointID = checkpointID
        self.note = note
    }
}

public struct GoalCreatedPayload: Codable, Sendable, Hashable {
    public var goalRevisionID: GoalRevisionID
    /// Immutable original request — preserved verbatim, never rewritten.
    public var originalRequest: String
    public var objective: String
    public var acceptanceCriteria: [String]

    public init(goalRevisionID: GoalRevisionID, originalRequest: String, objective: String, acceptanceCriteria: [String]) {
        self.goalRevisionID = goalRevisionID
        self.originalRequest = originalRequest
        self.objective = objective
        self.acceptanceCriteria = acceptanceCriteria
    }
}

public struct GoalRevisedPayload: Codable, Sendable, Hashable {
    public var goalRevisionID: GoalRevisionID
    public var previousRevisionID: GoalRevisionID
    public var reason: String

    public init(goalRevisionID: GoalRevisionID, previousRevisionID: GoalRevisionID, reason: String) {
        self.goalRevisionID = goalRevisionID
        self.previousRevisionID = previousRevisionID
        self.reason = reason
    }
}

public struct PlanProposedPayload: Codable, Sendable, Hashable {
    public var planRevisionID: PlanRevisionID
    public var goalRevisionID: GoalRevisionID
    public var summary: String

    public init(planRevisionID: PlanRevisionID, goalRevisionID: GoalRevisionID, summary: String) {
        self.planRevisionID = planRevisionID
        self.goalRevisionID = goalRevisionID
        self.summary = summary
    }
}

public struct PlanRevisedPayload: Codable, Sendable, Hashable {
    public var planRevisionID: PlanRevisionID
    public var previousRevisionID: PlanRevisionID
    public var rationale: String

    public init(planRevisionID: PlanRevisionID, previousRevisionID: PlanRevisionID, rationale: String) {
        self.planRevisionID = planRevisionID
        self.previousRevisionID = previousRevisionID
        self.rationale = rationale
    }
}

public struct TaskCreatedPayload: Codable, Sendable, Hashable {
    public var taskID: TaskID
    public var planRevisionID: PlanRevisionID
    public var objective: String
    public var owner: ExpertRole

    public init(taskID: TaskID, planRevisionID: PlanRevisionID, objective: String, owner: ExpertRole) {
        self.taskID = taskID
        self.planRevisionID = planRevisionID
        self.objective = objective
        self.owner = owner
    }
}

public struct TaskStateChangedPayload: Codable, Sendable, Hashable {
    public var taskID: TaskID
    public var oldState: TaskLogicalState
    public var newState: TaskLogicalState

    public init(taskID: TaskID, oldState: TaskLogicalState, newState: TaskLogicalState) {
        self.taskID = taskID
        self.oldState = oldState
        self.newState = newState
    }
}

public struct AttemptStartedPayload: Codable, Sendable, Hashable {
    public var attemptID: AttemptID
    public var taskID: TaskID
    public var workPackageID: WorkPackageID
    public var worker: WorkerIdentity

    public init(attemptID: AttemptID, taskID: TaskID, workPackageID: WorkPackageID, worker: WorkerIdentity) {
        self.attemptID = attemptID
        self.taskID = taskID
        self.workPackageID = workPackageID
        self.worker = worker
    }
}

public struct AttemptEndedPayload: Codable, Sendable, Hashable {
    public var attemptID: AttemptID
    public var taskID: TaskID
    public var outcome: WorkStatus
    public var recovered: Bool

    public init(attemptID: AttemptID, taskID: TaskID, outcome: WorkStatus, recovered: Bool = false) {
        self.attemptID = attemptID
        self.taskID = taskID
        self.outcome = outcome
        self.recovered = recovered
    }
}

public struct ModelSelectedPayload: Codable, Sendable, Hashable {
    public var attemptID: AttemptID
    public var runtime: RuntimeKind
    public var rationale: String

    public init(attemptID: AttemptID, runtime: RuntimeKind, rationale: String) {
        self.attemptID = attemptID
        self.runtime = runtime
        self.rationale = rationale
    }
}

public struct ContextCompiledPayload: Codable, Sendable, Hashable {
    public var attemptID: AttemptID
    public var bundle: ContextBundle

    public init(attemptID: AttemptID, bundle: ContextBundle) {
        self.attemptID = attemptID
        self.bundle = bundle
    }
}

public struct ActionRequestedPayload: Codable, Sendable, Hashable {
    public var request: ActionRequest
    public init(request: ActionRequest) { self.request = request }
}

public struct ActionAuthorizedPayload: Codable, Sendable, Hashable {
    public var actionID: ActionID
    public var authorizedScope: String
    public init(actionID: ActionID, authorizedScope: String) {
        self.actionID = actionID
        self.authorizedScope = authorizedScope
    }
}

public struct ActionExecutedPayload: Codable, Sendable, Hashable {
    public var result: ActionResult
    public init(result: ActionResult) { self.result = result }
}

public struct ActionReconciledPayload: Codable, Sendable, Hashable {
    public var actionID: ActionID
    public var resolvedOutcome: ActionOutcome
    public var note: String

    public init(actionID: ActionID, resolvedOutcome: ActionOutcome, note: String) {
        self.actionID = actionID
        self.resolvedOutcome = resolvedOutcome
        self.note = note
    }
}

public struct ArtifactCreatedPayload: Codable, Sendable, Hashable {
    public var artifactID: ArtifactID
    public var kind: ArtifactKind
    public var path: String
    public var revision: String
    public var contentHash: String

    public init(artifactID: ArtifactID, kind: ArtifactKind, path: String, revision: String, contentHash: String) {
        self.artifactID = artifactID
        self.kind = kind
        self.path = path
        self.revision = revision
        self.contentHash = contentHash
    }
}

public struct ArtifactChangedPayload: Codable, Sendable, Hashable {
    public var artifactID: ArtifactID
    public var newRevision: String
    public var contentHash: String

    public init(artifactID: ArtifactID, newRevision: String, contentHash: String) {
        self.artifactID = artifactID
        self.newRevision = newRevision
        self.contentHash = contentHash
    }
}

public struct EvidenceCreatedPayload: Codable, Sendable, Hashable {
    public var evidence: Evidence
    public init(evidence: Evidence) { self.evidence = evidence }
}

public struct EvidenceInvalidatedPayload: Codable, Sendable, Hashable {
    public var evidenceID: EvidenceID
    public var reason: String
    /// The resulting evidence status: `.stale` for artifact-change cascades,
    /// `.invalidated` for direct retraction.
    public var mark: EvidenceStatus

    public init(evidenceID: EvidenceID, reason: String, mark: EvidenceStatus = .invalidated) {
        self.evidenceID = evidenceID
        self.reason = reason
        self.mark = mark
    }
}

public struct VerificationStartedPayload: Codable, Sendable, Hashable {
    public var taskID: TaskID
    public var requirement: String

    public init(taskID: TaskID, requirement: String) {
        self.taskID = taskID
        self.requirement = requirement
    }
}

public struct VerificationPassedPayload: Codable, Sendable, Hashable {
    public var taskID: TaskID
    public var requirement: String
    public var evidenceID: EvidenceID?

    public init(taskID: TaskID, requirement: String, evidenceID: EvidenceID? = nil) {
        self.taskID = taskID
        self.requirement = requirement
        self.evidenceID = evidenceID
    }
}

public struct VerificationFailedPayload: Codable, Sendable, Hashable {
    public var taskID: TaskID
    public var requirement: String
    public var detail: String

    public init(taskID: TaskID, requirement: String, detail: String) {
        self.taskID = taskID
        self.requirement = requirement
        self.detail = detail
    }
}

public struct VerificationInconclusivePayload: Codable, Sendable, Hashable {
    public var taskID: TaskID
    public var requirement: String
    public var detail: String

    public init(taskID: TaskID, requirement: String, detail: String) {
        self.taskID = taskID
        self.requirement = requirement
        self.detail = detail
    }
}

public struct DecisionRequestedPayload: Codable, Sendable, Hashable {
    public var subject: String
    public var question: String
    public var blocking: Bool

    public init(subject: String, question: String, blocking: Bool) {
        self.subject = subject
        self.question = question
        self.blocking = blocking
    }
}

public struct UserIntervenedPayload: Codable, Sendable, Hashable {
    /// Free-form description of the intervention (includes Emergency Stop).
    public var intervention: String

    public init(intervention: String) {
        self.intervention = intervention
    }
}

public struct CheckpointCreatedPayload: Codable, Sendable, Hashable {
    public var checkpointID: String
    public var note: String

    public init(checkpointID: String, note: String) {
        self.checkpointID = checkpointID
        self.note = note
    }
}

public struct WorkerCrashedPayload: Codable, Sendable, Hashable {
    public var workerID: String
    public var attemptID: AttemptID?

    public init(workerID: String, attemptID: AttemptID? = nil) {
        self.workerID = workerID
        self.attemptID = attemptID
    }
}

public struct WorkerRecoveredPayload: Codable, Sendable, Hashable {
    public var workerID: String
    public var attemptID: AttemptID
    public var strategy: String

    public init(workerID: String, attemptID: AttemptID, strategy: String) {
        self.workerID = workerID
        self.attemptID = attemptID
        self.strategy = strategy
    }
}

public struct GoalCompletedPayload: Codable, Sendable, Hashable {
    public var goalRevisionID: GoalRevisionID
    public init(goalRevisionID: GoalRevisionID) { self.goalRevisionID = goalRevisionID }
}

public struct GoalBlockedPayload: Codable, Sendable, Hashable {
    public var goalRevisionID: GoalRevisionID
    public var reason: String

    public init(goalRevisionID: GoalRevisionID, reason: String) {
        self.goalRevisionID = goalRevisionID
        self.reason = reason
    }
}
