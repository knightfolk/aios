import Foundation
import AIOSCore

/// The docs-05 state hierarchy. These records are projections built from the
/// journal — they are rebuildable and never authoritative on their own.

public struct GoalRecord: Codable, Sendable, Hashable {
    public var goalRevisionID: GoalRevisionID
    /// Immutable original request — copied verbatim across revisions.
    public var originalRequest: String
    public var objective: String
    public var acceptanceCriteria: [String]
    public var previousRevisionID: GoalRevisionID?
    public var revisionReason: String?
    public var completed: Bool
    public var blockedReason: String?

    public init(
        goalRevisionID: GoalRevisionID,
        originalRequest: String,
        objective: String,
        acceptanceCriteria: [String],
        previousRevisionID: GoalRevisionID? = nil,
        revisionReason: String? = nil,
        completed: Bool = false,
        blockedReason: String? = nil
    ) {
        self.goalRevisionID = goalRevisionID
        self.originalRequest = originalRequest
        self.objective = objective
        self.acceptanceCriteria = acceptanceCriteria
        self.previousRevisionID = previousRevisionID
        self.revisionReason = revisionReason
        self.completed = completed
        self.blockedReason = blockedReason
    }
}

public struct PlanRecord: Codable, Sendable, Hashable {
    public var planRevisionID: PlanRevisionID
    public var goalRevisionID: GoalRevisionID
    public var summary: String
    public var taskIDs: [TaskID]
    public var previousRevisionID: PlanRevisionID?
    public var revisionRationale: String?

    public init(
        planRevisionID: PlanRevisionID,
        goalRevisionID: GoalRevisionID,
        summary: String,
        taskIDs: [TaskID] = [],
        previousRevisionID: PlanRevisionID? = nil,
        revisionRationale: String? = nil
    ) {
        self.planRevisionID = planRevisionID
        self.goalRevisionID = goalRevisionID
        self.summary = summary
        self.taskIDs = taskIDs
        self.previousRevisionID = previousRevisionID
        self.revisionRationale = revisionRationale
    }
}

public struct TaskRecord: Codable, Sendable, Hashable {
    public var taskID: TaskID
    public var planRevisionID: PlanRevisionID
    public var objective: String
    public var owner: ExpertRole
    public var state: TaskLogicalState
    public var dependencies: [TaskID]

    public init(
        taskID: TaskID,
        planRevisionID: PlanRevisionID,
        objective: String,
        owner: ExpertRole,
        state: TaskLogicalState = .pending,
        dependencies: [TaskID] = []
    ) {
        self.taskID = taskID
        self.planRevisionID = planRevisionID
        self.objective = objective
        self.owner = owner
        self.state = state
        self.dependencies = dependencies
    }
}

public enum AttemptPhase: String, Codable, Sendable, Hashable {
    case pending = "PENDING"
    case running = "RUNNING"
    case ended = "ENDED"
}

public struct RuntimeSelection: Codable, Sendable, Hashable {
    public var runtime: RuntimeKind
    public var rationale: String

    public init(runtime: RuntimeKind, rationale: String) {
        self.runtime = runtime
        self.rationale = rationale
    }
}

public struct AttemptRecord: Codable, Sendable, Hashable {
    public var attemptID: AttemptID
    public var taskID: TaskID
    public var workPackageID: WorkPackageID
    public var worker: WorkerIdentity?
    public var phase: AttemptPhase
    public var outcome: WorkStatus?
    public var crashed: Bool
    public var recovered: Bool
    public var modelSelection: RuntimeSelection?
    public var contextBundle: ContextBundle?
    public var unreconciledUnknownActionIDs: Set<ActionID>

    public init(
        attemptID: AttemptID,
        taskID: TaskID,
        workPackageID: WorkPackageID,
        worker: WorkerIdentity? = nil,
        phase: AttemptPhase = .pending,
        outcome: WorkStatus? = nil,
        crashed: Bool = false,
        recovered: Bool = false,
        modelSelection: RuntimeSelection? = nil,
        contextBundle: ContextBundle? = nil,
        unreconciledUnknownActionIDs: Set<ActionID> = []
    ) {
        self.attemptID = attemptID
        self.taskID = taskID
        self.workPackageID = workPackageID
        self.worker = worker
        self.phase = phase
        self.outcome = outcome
        self.crashed = crashed
        self.recovered = recovered
        self.modelSelection = modelSelection
        self.contextBundle = contextBundle
        self.unreconciledUnknownActionIDs = unreconciledUnknownActionIDs
    }

    /// True while an action of this attempt ended with outcome `UNKNOWN` and
    /// has not been reconciled. Retrying such an attempt is forbidden.
    public var hasUnreconciledUnknownOutcome: Bool { !unreconciledUnknownActionIDs.isEmpty }
}

public struct ArtifactRecord: Codable, Sendable, Hashable {
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

public struct ActionEntry: Codable, Sendable, Hashable {
    public var request: ActionRequest
    public var authorized: Bool
    public var result: ActionResult?
    public var reconciled: Bool

    public init(request: ActionRequest, authorized: Bool = false, result: ActionResult? = nil, reconciled: Bool = false) {
        self.request = request
        self.authorized = authorized
        self.result = result
        self.reconciled = reconciled
    }
}

public struct NeedsYouEntry: Codable, Sendable, Hashable {
    public var subject: String
    public var question: String
    public var blocking: Bool

    public init(subject: String, question: String, blocking: Bool) {
        self.subject = subject
        self.question = question
        self.blocking = blocking
    }
}

public struct ResolvedNeedsYouEntry: Codable, Sendable, Hashable {
    public var subject: String
    public var question: String
    public var answer: String
    public var resolvedAt: Date

    public init(subject: String, question: String, answer: String, resolvedAt: Date) {
        self.subject = subject
        self.question = question
        self.answer = answer
        self.resolvedAt = resolvedAt
    }
}

public struct PromotionRecord: Codable, Sendable, Hashable {
    public var noteID: String?
    public var itemID: String?
    /// GOAL | TASK | TIMELINE_PIN | DISCARDED
    public var target: String
    public var summary: String

    public init(noteID: String? = nil, itemID: String? = nil, target: String, summary: String) {
        self.noteID = noteID
        self.itemID = itemID
        self.target = target
        self.summary = summary
    }
}

public struct BranchRecord: Codable, Sendable, Hashable {
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

public struct RestorationRecord: Codable, Sendable, Hashable {
    public var checkpointID: String
    public var note: String

    public init(checkpointID: String, note: String) {
        self.checkpointID = checkpointID
        self.note = note
    }
}

public struct LeaseEventRecord: Codable, Sendable, Hashable {
    public var granted: Bool
    public var owner: String
    public var reason: String

    public init(granted: Bool, owner: String, reason: String) {
        self.granted = granted
        self.owner = owner
        self.reason = reason
    }
}

/// Full projected state of one project, derived only from journaled events.
public struct ProjectState: Codable, Sendable, Hashable {
    public var projectID: ProjectID
    public var goals: [GoalRevisionID: GoalRecord]
    public var activeGoalRevisionID: GoalRevisionID?
    public var plans: [PlanRevisionID: PlanRecord]
    public var activePlanRevisionID: PlanRevisionID?
    public var tasks: [TaskID: TaskRecord]
    public var attempts: [AttemptID: AttemptRecord]
    public var artifacts: [ArtifactID: ArtifactRecord]
    public var evidence: [EvidenceID: Evidence]
    public var actions: [ActionID: ActionEntry]
    /// Journal insertion order of actions (dictionaries are unordered).
    public var actionOrder: [ActionID]
    public var needsUser: [NeedsYouEntry]
    public var resolvedNeedsYou: [ResolvedNeedsYouEntry]
    public var promotions: [PromotionRecord]
    public var branches: [BranchRecord]
    public var restorations: [RestorationRecord]
    public var leaseEvents: [LeaseEventRecord]
    public var interventions: [String]
    public var checkpoints: [String]
    public var warnings: [String]
    public var lastSequence: UInt64

    public init(projectID: ProjectID) {
        self.projectID = projectID
        self.goals = [:]
        self.activeGoalRevisionID = nil
        self.plans = [:]
        self.activePlanRevisionID = nil
        self.tasks = [:]
        self.attempts = [:]
        self.artifacts = [:]
        self.evidence = [:]
        self.actions = [:]
        self.actionOrder = []
        self.needsUser = []
        self.resolvedNeedsYou = []
        self.promotions = []
        self.branches = []
        self.restorations = []
        self.leaseEvents = []
        self.interventions = []
        self.checkpoints = []
        self.warnings = []
        self.lastSequence = 0
    }
}
