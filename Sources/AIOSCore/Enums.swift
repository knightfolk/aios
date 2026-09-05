import Foundation

// MARK: - Semantic statement types (docs 05 — never collapse into generic "memory")

public enum SemanticStatementType: String, Codable, Sendable, CaseIterable, Hashable {
    case userRequirement = "USER_REQUIREMENT"
    case observedFact = "OBSERVED_FACT"
    case verifiedFact = "VERIFIED_FACT"
    case expertJudgment = "EXPERT_JUDGMENT"
    case hypothesis = "HYPOTHESIS"
    case plan = "PLAN"
    case prediction = "PREDICTION"
    case generatedContent = "GENERATED_CONTENT"
}

// MARK: - Evidence

public enum EvidenceStrength: String, Codable, Sendable, CaseIterable, Hashable {
    case observation = "OBSERVATION"
    case primarySource = "PRIMARY_SOURCE"
    case mechanicalCheck = "MECHANICAL_CHECK"
    case reproducedResult = "REPRODUCED_RESULT"
    case independentReview = "INDEPENDENT_REVIEW"
    case expertJudgment = "EXPERT_JUDGMENT"
    case userAcceptance = "USER_ACCEPTANCE"
}

public enum EvidenceStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case valid = "VALID"
    case stale = "STALE"
    case invalidated = "INVALIDATED"
    case inconclusive = "INCONCLUSIVE"
    case superseded = "SUPERSEDED"
}

// MARK: - Actions

public enum ActionOutcome: String, Codable, Sendable, CaseIterable, Hashable {
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    case partiallySucceeded = "PARTIALLY_SUCCEEDED"
    case cancelled = "CANCELLED"
    case timedOut = "TIMED_OUT"
    /// Not retryable until reconciled (Engine Constitution #13).
    case unknown = "UNKNOWN"
    case rejected = "REJECTED"
    case stalePrecondition = "STALE_PRECONDITION"
}

public enum CapabilityClass: String, Codable, Sendable, CaseIterable, Hashable {
    case observe = "OBSERVE"
    case modifyWorkspace = "MODIFY_WORKSPACE"
    case operateComputer = "OPERATE_COMPUTER"
    case externalConsequence = "EXTERNAL_CONSEQUENCE"
}

public enum SideEffectClass: String, Codable, Sendable, Hashable {
    case none = "NONE"
    case local = "LOCAL"
    case external = "EXTERNAL"
}

public enum Reversibility: String, Codable, Sendable, Hashable {
    case reversible = "REVERSIBLE"
    case irreversible = "IRREVERSIBLE"
    case unknown = "UNKNOWN"
}

public enum Idempotency: String, Codable, Sendable, Hashable {
    case idempotent = "IDEMPOTENT"
    case nonIdempotent = "NON_IDEMPOTENT"
    case unknown = "UNKNOWN"
}

// MARK: - Execution

public enum ExecutionTopology: String, Codable, Sendable, CaseIterable, Hashable {
    case direct = "DIRECT"
    case deterministic = "DETERMINISTIC"
    case singleAgent = "SINGLE_AGENT"
    case agentPlusReview = "AGENT_PLUS_REVIEW"
    case plannerExecutor = "PLANNER_EXECUTOR"
    case generatorEvaluator = "GENERATOR_EVALUATOR"
    case parallelResearch = "PARALLEL_RESEARCH"
    case orchestrated = "ORCHESTRATED"
    case computerUse = "COMPUTER_USE"
    case mediaPipeline = "MEDIA_PIPELINE"
}

/// The runtime that actually produced a worker's output. `scripted` is the
/// honest label for scenario-driven workers used until real model runtimes
/// land in Phase 2 — it is journaled, never hidden.
public enum RuntimeKind: String, Codable, Sendable, Hashable {
    case scripted = "SCRIPTED"
    case deterministic = "DETERMINISTIC"
    case mlx = "MLX"
    case coreML = "CORE_ML"
    case cloudAPI = "CLOUD_API"
}

// MARK: - Policies

public enum PrivacyPolicy: String, Codable, Sendable, Hashable {
    case localOnly = "LOCAL_ONLY"
    case hybridAllowed = "HYBRID_ALLOWED"
}

public enum HandoffPolicy: String, Codable, Sendable, Hashable {
    case continuation = "CONTINUATION"
    case compaction = "COMPACTION"
    case freshShiftWithHandoffPacket = "FRESH_SHIFT_WITH_HANDOFF_PACKET"
}

public enum FailurePolicy: String, Codable, Sendable, Hashable {
    case failFast = "FAIL_FAST"
    case retryIdempotentOnly = "RETRY_IDEMPOTENT_ONLY"
    case requestReplan = "REQUEST_REPLAN"
    case escalateToUser = "ESCALATE_TO_USER"
}

public enum WorkStatus: String, Codable, Sendable, Hashable {
    case inProgress = "IN_PROGRESS"
    case completed = "COMPLETED"
    case blocked = "BLOCKED"
    case failed = "FAILED"
}

/// Logical task state (docs 05). A task reaches `complete` only through a
/// passed verification event — never from a worker's self-report.
public enum TaskLogicalState: String, Codable, Sendable, CaseIterable, Hashable {
    case pending = "PENDING"
    case ready = "READY"
    case inProgress = "IN_PROGRESS"
    case blocked = "BLOCKED"
    case awaitingVerification = "AWAITING_VERIFICATION"
    case complete = "COMPLETE"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
}

// MARK: - Artifacts and sources

public enum ArtifactKind: String, Codable, Sendable, CaseIterable, Hashable {
    case fileOrDiff = "FILE_OR_DIFF"
    case commit = "COMMIT"
    case report = "REPORT"
    case design = "DESIGN"
    case image = "IMAGE"
    case audio = "AUDIO"
    case video = "VIDEO"
    case dataset = "DATASET"
    case build = "BUILD"
    case simulationOutput = "SIMULATION_OUTPUT"
    case decisionRecord = "DECISION_RECORD"
}

public enum SourceType: String, Codable, Sendable, Hashable {
    case file = "FILE"
    case command = "COMMAND"
    case model = "MODEL"
    case user = "USER"
    case tool = "TOOL"
    case external = "EXTERNAL"
}

// MARK: - Experts

/// Stable expert role carried by contracts. The seven permanent team members
/// encode as plain strings on the wire; temporary specialists encode as
/// {"specialist": "<functional name>"} (docs 07: functional names, finite lifetimes).
public enum ExpertRole: Hashable, Sendable {
    case concierge
    case linus
    case jobs
    case einstein
    case sherlock
    case henson
    case chloe
    case specialist(name: String)
}

extension ExpertRole: Codable {
    private enum CodingKeys: String, CodingKey { case specialist }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .concierge, .linus, .jobs, .einstein, .sherlock, .henson, .chloe:
            var container = encoder.singleValueContainer()
            try container.encode(wireName)
        case .specialist(let name):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .specialist)
        }
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let name = try? single.decode(String.self),
           let role = ExpertRole(named: name) {
            self = role
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self = .specialist(name: try container.decode(String.self, forKey: .specialist))
        }
    }

    private var wireName: String {
        switch self {
        case .concierge: "concierge"
        case .linus: "linus"
        case .jobs: "jobs"
        case .einstein: "einstein"
        case .sherlock: "sherlock"
        case .henson: "henson"
        case .chloe: "chloe"
        case .specialist: "" // encoded via keyed form above
        }
    }

    private init?(named name: String) {
        switch name {
        case "concierge": self = .concierge
        case "linus": self = .linus
        case "jobs": self = .jobs
        case "einstein": self = .einstein
        case "sherlock": self = .sherlock
        case "henson": self = .henson
        case "chloe": self = .chloe
        default: return nil
        }
    }
}

// MARK: - Small shared value types

/// A typed JSON-ish parameter value: no untyped `Any` crosses the broker boundary.
public enum ActionParameterValue: Codable, Sendable, Hashable {
    case text(String)
    case number(Double)
    case flag(Bool)
}

public struct HarnessProfileID: Codable, Sendable, Hashable, CustomStringConvertible {
    public let value: String
    public init(value: String) { self.value = value }
    public var description: String { value }
}

/// Identity of the worker that produced a result. `runtime` records honestly
/// what executed the work (see `RuntimeKind.scripted`).
public struct WorkerIdentity: Codable, Sendable, Hashable {
    public var workerID: String
    public var model: String?
    public var runtime: RuntimeKind
    public var revision: String?

    public init(workerID: String, model: String? = nil, runtime: RuntimeKind, revision: String? = nil) {
        self.workerID = workerID
        self.model = model
        self.runtime = runtime
        self.revision = revision
    }
}

public struct ResourceBudget: Codable, Sendable, Hashable {
    public var maxMemoryGB: Double?
    public var maxComputeCores: Int?

    public init(maxMemoryGB: Double? = nil, maxComputeCores: Int? = nil) {
        self.maxMemoryGB = maxMemoryGB
        self.maxComputeCores = maxComputeCores
    }
}

public struct TimeBudget: Codable, Sendable, Hashable {
    public var timeoutSeconds: TimeInterval?
    public var deadline: Date?

    public init(timeoutSeconds: TimeInterval? = nil, deadline: Date? = nil) {
        self.timeoutSeconds = timeoutSeconds
        self.deadline = deadline
    }
}

public struct SpendPolicy: Codable, Sendable, Hashable {
    public var maxSpendUSD: Double?
    public var allowPaidCredits: Bool

    public init(maxSpendUSD: Double? = nil, allowPaidCredits: Bool = false) {
        self.maxSpendUSD = maxSpendUSD
        self.allowPaidCredits = allowPaidCredits
    }
}

public struct ExpectedOutput: Codable, Sendable, Hashable {
    public var artifactKind: ArtifactKind
    public var description: String

    public init(artifactKind: ArtifactKind, description: String) {
        self.artifactKind = artifactKind
        self.description = description
    }
}

public enum VerificationMethod: Codable, Sendable, Hashable {
    case buildSucceeds
    case testsPass
    case independentReview
    case userAcceptance
    case deterministicCheck(String)
}

public struct VerificationRequirement: Codable, Sendable, Hashable {
    public var description: String
    public var method: VerificationMethod

    public init(description: String, method: VerificationMethod) {
        self.description = description
        self.method = method
    }
}

public struct VerificationResult: Codable, Sendable, Hashable {
    public var requirement: String
    public var passed: Bool
    public var detail: String

    public init(requirement: String, passed: Bool, detail: String) {
        self.requirement = requirement
        self.passed = passed
        self.detail = detail
    }
}

public struct ArtifactRevisionRef: Codable, Sendable, Hashable {
    public var artifactID: ArtifactID
    public var revision: String

    public init(artifactID: ArtifactID, revision: String) {
        self.artifactID = artifactID
        self.revision = revision
    }
}

public struct Precondition: Codable, Sendable, Hashable {
    public var target: String
    public var contentHash: String?

    public init(target: String, contentHash: String? = nil) {
        self.target = target
        self.contentHash = contentHash
    }
}

public struct ContextSelection: Codable, Sendable, Hashable {
    public var path: String
    public var reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

/// Bounded compiled context for one work package (docs 03: compiled, not accumulated).
public struct ContextBundle: Codable, Sendable, Hashable {
    public var selections: [ContextSelection]
    public var tokenBudget: Int

    public init(selections: [ContextSelection], tokenBudget: Int) {
        self.selections = selections
        self.tokenBudget = tokenBudget
    }
}

/// A typed claim inside a `WorkResult` — every claim carries its semantic type;
/// generated output is never automatically promoted to fact.
public struct Claim: Codable, Sendable, Hashable {
    public var statement: String
    public var statementType: SemanticStatementType

    public init(statement: String, statementType: SemanticStatementType) {
        self.statement = statement
        self.statementType = statementType
    }
}
