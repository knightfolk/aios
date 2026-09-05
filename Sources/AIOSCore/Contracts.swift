import Foundation

// Canonical contracts (docs 04). These are the model-neutral center of the
// Work Runtime: every field name here is wire-stable and covered by golden
// JSON decode tests. Typed Swift everywhere internally; the versioned JSON
// form exists only across process/network boundaries.

/// One bounded unit of intelligent work.
public struct WorkPackage: Codable, Sendable, Hashable {
    public static let currentSchemaVersion: UInt = 1

    public var schemaVersion: UInt
    public var packageID: WorkPackageID
    public var projectID: ProjectID
    public var goalRevisionID: GoalRevisionID
    public var planRevisionID: PlanRevisionID
    public var taskID: TaskID
    public var attemptID: AttemptID
    public var role: ExpertRole
    public var taskContract: TaskContract
    public var contextBundle: ContextBundle
    public var capabilities: [CapabilityClass]
    public var executionTargets: [ExecutionTopology]
    public var resourceBudget: ResourceBudget
    public var timeBudget: TimeBudget
    public var privacyPolicy: PrivacyPolicy
    public var spendPolicy: SpendPolicy
    public var expectedOutputs: [ExpectedOutput]
    public var verificationRequirements: [VerificationRequirement]
    public var handoffPolicy: HandoffPolicy
    public var failurePolicy: FailurePolicy
    public var harnessProfile: HarnessProfileID

    public init(
        packageID: WorkPackageID,
        projectID: ProjectID,
        goalRevisionID: GoalRevisionID,
        planRevisionID: PlanRevisionID,
        taskID: TaskID,
        attemptID: AttemptID,
        role: ExpertRole,
        taskContract: TaskContract,
        contextBundle: ContextBundle,
        capabilities: [CapabilityClass],
        executionTargets: [ExecutionTopology],
        resourceBudget: ResourceBudget,
        timeBudget: TimeBudget,
        privacyPolicy: PrivacyPolicy,
        spendPolicy: SpendPolicy,
        expectedOutputs: [ExpectedOutput],
        verificationRequirements: [VerificationRequirement],
        handoffPolicy: HandoffPolicy,
        failurePolicy: FailurePolicy,
        harnessProfile: HarnessProfileID,
        schemaVersion: UInt = WorkPackage.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.packageID = packageID
        self.projectID = projectID
        self.goalRevisionID = goalRevisionID
        self.planRevisionID = planRevisionID
        self.taskID = taskID
        self.attemptID = attemptID
        self.role = role
        self.taskContract = taskContract
        self.contextBundle = contextBundle
        self.capabilities = capabilities
        self.executionTargets = executionTargets
        self.resourceBudget = resourceBudget
        self.timeBudget = timeBudget
        self.privacyPolicy = privacyPolicy
        self.spendPolicy = spendPolicy
        self.expectedOutputs = expectedOutputs
        self.verificationRequirements = verificationRequirements
        self.handoffPolicy = handoffPolicy
        self.failurePolicy = failurePolicy
        self.harnessProfile = harnessProfile
    }
}

/// The frozen-for-an-attempt work agreement. Scope expansion requires a new
/// contract/attempt or an explicitly approved revision.
public struct TaskContract: Codable, Sendable, Hashable {
    public static let currentSchemaVersion: UInt = 1

    public var schemaVersion: UInt
    public var objective: String
    public var inputs: [String]
    public var allowedScope: [String]
    public var mustPreserve: [String]
    public var forbiddenScope: [String]
    public var expectedOutputs: [ExpectedOutput]
    public var verificationRequirements: [VerificationRequirement]
    public var dependencyAssumptions: [String]
    /// docs 04 calls this "expiry/staleness conditions".
    public var stalenessConditions: [String]

    public init(
        objective: String,
        inputs: [String],
        allowedScope: [String],
        mustPreserve: [String],
        forbiddenScope: [String],
        expectedOutputs: [ExpectedOutput],
        verificationRequirements: [VerificationRequirement],
        dependencyAssumptions: [String],
        stalenessConditions: [String],
        schemaVersion: UInt = TaskContract.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.objective = objective
        self.inputs = inputs
        self.allowedScope = allowedScope
        self.mustPreserve = mustPreserve
        self.forbiddenScope = forbiddenScope
        self.expectedOutputs = expectedOutputs
        self.verificationRequirements = verificationRequirements
        self.dependencyAssumptions = dependencyAssumptions
        self.stalenessConditions = stalenessConditions
    }
}

/// A worker's structured report. Not itself proof of completion.
public struct WorkResult: Codable, Sendable, Hashable {
    public static let currentSchemaVersion: UInt = 1

    public var schemaVersion: UInt
    public var packageID: WorkPackageID
    public var attemptID: AttemptID
    public var worker: WorkerIdentity
    public var status: WorkStatus
    public var artifacts: [ArtifactID]
    public var claims: [Claim]
    public var evidenceRefs: [EvidenceID]
    public var actionRequests: [ActionID]
    public var completedActionRefs: [ActionID]
    public var discoveredIssues: [String]
    public var unresolvedAssumptions: [String]
    public var blockers: [String]
    public var recommendedNextSteps: [String]
    public var handoff: Handoff?

    public init(
        packageID: WorkPackageID,
        attemptID: AttemptID,
        worker: WorkerIdentity,
        status: WorkStatus,
        artifacts: [ArtifactID] = [],
        claims: [Claim] = [],
        evidenceRefs: [EvidenceID] = [],
        actionRequests: [ActionID] = [],
        completedActionRefs: [ActionID] = [],
        discoveredIssues: [String] = [],
        unresolvedAssumptions: [String] = [],
        blockers: [String] = [],
        recommendedNextSteps: [String] = [],
        handoff: Handoff? = nil,
        schemaVersion: UInt = WorkResult.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.packageID = packageID
        self.attemptID = attemptID
        self.worker = worker
        self.status = status
        self.artifacts = artifacts
        self.claims = claims
        self.evidenceRefs = evidenceRefs
        self.actionRequests = actionRequests
        self.completedActionRefs = completedActionRefs
        self.discoveredIssues = discoveredIssues
        self.unresolvedAssumptions = unresolvedAssumptions
        self.blockers = blockers
        self.recommendedNextSteps = recommendedNextSteps
        self.handoff = handoff
    }
}

/// A typed proposal to use a capability. No Brain executes reality directly;
/// it requests an Action through the broker.
public struct ActionRequest: Codable, Sendable, Hashable {
    public static let currentSchemaVersion: UInt = 1

    public var schemaVersion: UInt
    public var actionID: ActionID
    public var workPackageID: WorkPackageID
    public var requestedBy: ExpertRole
    public var capability: CapabilityClass
    public var operation: String
    public var target: String
    public var parameters: [String: ActionParameterValue]
    public var expectedEffect: String
    public var sideEffectClass: SideEffectClass
    public var reversibility: Reversibility
    public var idempotency: Idempotency
    public var requiredPermission: CapabilityClass
    public var preconditions: [Precondition]
    public var verificationPlan: String
    public var timeout: TimeInterval?

    public init(
        actionID: ActionID,
        workPackageID: WorkPackageID,
        requestedBy: ExpertRole,
        capability: CapabilityClass,
        operation: String,
        target: String,
        parameters: [String: ActionParameterValue] = [:],
        expectedEffect: String,
        sideEffectClass: SideEffectClass,
        reversibility: Reversibility,
        idempotency: Idempotency,
        requiredPermission: CapabilityClass,
        preconditions: [Precondition] = [],
        verificationPlan: String,
        timeout: TimeInterval? = nil,
        schemaVersion: UInt = ActionRequest.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.actionID = actionID
        self.workPackageID = workPackageID
        self.requestedBy = requestedBy
        self.capability = capability
        self.operation = operation
        self.target = target
        self.parameters = parameters
        self.expectedEffect = expectedEffect
        self.sideEffectClass = sideEffectClass
        self.reversibility = reversibility
        self.idempotency = idempotency
        self.requiredPermission = requiredPermission
        self.preconditions = preconditions
        self.verificationPlan = verificationPlan
        self.timeout = timeout
    }
}

/// What the Hand actually observed.
public struct ActionResult: Codable, Sendable, Hashable {
    public static let currentSchemaVersion: UInt = 1

    public var schemaVersion: UInt
    public var actionID: ActionID
    public var outcome: ActionOutcome
    public var startedAt: Date
    public var endedAt: Date
    public var observedEffects: [String]
    public var artifacts: [ArtifactID]
    public var stdoutReference: String?
    public var stderrReference: String?
    public var verificationResults: [VerificationResult]
    public var stateBeforeReference: String?
    public var stateAfterReference: String?
    public var reconciliationRequired: Bool
    public var failureDetails: String?

    public init(
        actionID: ActionID,
        outcome: ActionOutcome,
        startedAt: Date,
        endedAt: Date,
        observedEffects: [String] = [],
        artifacts: [ArtifactID] = [],
        stdoutReference: String? = nil,
        stderrReference: String? = nil,
        verificationResults: [VerificationResult] = [],
        stateBeforeReference: String? = nil,
        stateAfterReference: String? = nil,
        reconciliationRequired: Bool = false,
        failureDetails: String? = nil,
        schemaVersion: UInt = ActionResult.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.actionID = actionID
        self.outcome = outcome
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.observedEffects = observedEffects
        self.artifacts = artifacts
        self.stdoutReference = stdoutReference
        self.stderrReference = stderrReference
        self.verificationResults = verificationResults
        self.stateBeforeReference = stateBeforeReference
        self.stateAfterReference = stateAfterReference
        self.reconciliationRequired = reconciliationRequired
        self.failureDetails = failureDetails
    }
}

/// First-class, revision-bound evidence. Completion of important work
/// requires it; stale artifacts invalidate it.
public struct Evidence: Codable, Sendable, Hashable {
    public static let currentSchemaVersion: UInt = 1

    public var schemaVersion: UInt
    public var evidenceID: EvidenceID
    public var projectID: ProjectID
    public var subject: String
    public var proposition: String
    public var claimType: SemanticStatementType
    public var sourceType: SourceType
    public var sourceReference: String
    public var producedBy: WorkerIdentity?
    public var observedAt: Date
    public var verificationMethod: VerificationMethod
    public var strength: EvidenceStrength
    public var artifactRevisionRefs: [ArtifactRevisionRef]
    public var dependencies: [EvidenceID]
    public var invalidatedBy: [EvidenceID]
    public var status: EvidenceStatus

    public init(
        evidenceID: EvidenceID,
        projectID: ProjectID,
        subject: String,
        proposition: String,
        claimType: SemanticStatementType,
        sourceType: SourceType,
        sourceReference: String,
        producedBy: WorkerIdentity? = nil,
        observedAt: Date,
        verificationMethod: VerificationMethod,
        strength: EvidenceStrength,
        artifactRevisionRefs: [ArtifactRevisionRef] = [],
        dependencies: [EvidenceID] = [],
        invalidatedBy: [EvidenceID] = [],
        status: EvidenceStatus = .valid,
        schemaVersion: UInt = Evidence.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.evidenceID = evidenceID
        self.projectID = projectID
        self.subject = subject
        self.proposition = proposition
        self.claimType = claimType
        self.sourceType = sourceType
        self.sourceReference = sourceReference
        self.producedBy = producedBy
        self.observedAt = observedAt
        self.verificationMethod = verificationMethod
        self.strength = strength
        self.artifactRevisionRefs = artifactRevisionRefs
        self.dependencies = dependencies
        self.invalidatedBy = invalidatedBy
        self.status = status
    }
}

/// Structured transition between sessions/models/experts. Raw transcripts are
/// not the handoff format.
public struct Handoff: Codable, Sendable, Hashable {
    public static let currentSchemaVersion: UInt = 1

    public var schemaVersion: UInt
    public var task: String
    public var currentState: String
    public var artifactsChanged: [ArtifactID]
    public var verifiedFacts: [String]
    public var unverifiedAssumptions: [String]
    public var failedApproaches: [String]
    public var blockers: [String]
    public var recommendedNextAction: String
    public var evidenceRefs: [EvidenceID]

    public init(
        task: String,
        currentState: String,
        artifactsChanged: [ArtifactID] = [],
        verifiedFacts: [String] = [],
        unverifiedAssumptions: [String] = [],
        failedApproaches: [String] = [],
        blockers: [String] = [],
        recommendedNextAction: String,
        evidenceRefs: [EvidenceID] = [],
        schemaVersion: UInt = Handoff.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.task = task
        self.currentState = currentState
        self.artifactsChanged = artifactsChanged
        self.verifiedFacts = verifiedFacts
        self.unverifiedAssumptions = unverifiedAssumptions
        self.failedApproaches = failedApproaches
        self.blockers = blockers
        self.recommendedNextAction = recommendedNextAction
        self.evidenceRefs = evidenceRefs
    }
}
