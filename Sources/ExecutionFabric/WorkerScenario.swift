import Foundation
import AIOSCore

/// Scenario script driving the v1 scripted InferenceWorker. This runtime is
/// declared honestly (`RuntimeKind.scripted`) — it exists to exercise the real
/// worker boundary, protocol, and recovery machinery until MLX lands in
/// Phase 2. It never fabricates evidence: any completion claims it emits are
/// typed claims that still require verification.
public struct WorkerScenario: Codable, Sendable {
    public struct ActionStep: Codable, Sendable {
        public var operation: String
        public var target: String
        public var contents: String?
        public var expectedEffect: String
        public var verificationPlan: String

        public init(operation: String, target: String, contents: String? = nil, expectedEffect: String, verificationPlan: String) {
            self.operation = operation
            self.target = target
            self.contents = contents
            self.expectedEffect = expectedEffect
            self.verificationPlan = verificationPlan
        }
    }

    public struct FinishStep: Codable, Sendable {
        /// One of WorkStatus raw values, e.g. "COMPLETED".
        public var status: String
        /// Claims as [statement, SemanticStatementType raw value] pairs.
        public var claims: [[String]]
        public var summary: String

        public init(status: String, claims: [[String]], summary: String) {
            self.status = status
            self.claims = claims
            self.summary = summary
        }
    }

    public enum Step: Codable, Sendable {
        case action(ActionStep)
        case sleepMs(Int)
        case finish(FinishStep)
        /// Simulates a mid-run crash: the worker exits uncleanly with code 9.
        case crash
    }

    public var steps: [Step]
    public var heartbeatIntervalSeconds: Double

    public init(steps: [Step], heartbeatIntervalSeconds: Double = 5) {
        self.steps = steps
        self.heartbeatIntervalSeconds = heartbeatIntervalSeconds
    }
}

extension WorkerScenario {
    /// Builds the typed ActionRequest for a step within a work package.
    public func actionRequest(for step: ActionStep, in package: WorkPackage) -> ActionRequest {
        var parameters: [String: ActionParameterValue] = [:]
        if let contents = step.contents {
            parameters["contents"] = .text(contents)
        }
        return ActionRequest(
            actionID: ActionID(),
            workPackageID: package.packageID,
            requestedBy: package.role,
            capability: Self.capabilityClass(forOperation: step.operation),
            operation: step.operation,
            target: step.target,
            parameters: parameters,
            expectedEffect: step.expectedEffect,
            sideEffectClass: Self.sideEffectClass(forOperation: step.operation),
            reversibility: .reversible,
            idempotency: .idempotent,
            requiredPermission: Self.capabilityClass(forOperation: step.operation),
            preconditions: [],
            verificationPlan: step.verificationPlan
        )
    }

    static func capabilityClass(forOperation operation: String) -> CapabilityClass {
        switch operation {
        case let op where op.hasPrefix("fs.read"), let op where op.hasPrefix("git.diff"), let op where op.hasPrefix("git.status"):
            _ = op
            return .observe
        case let op where op.hasPrefix("shell.run"):
            _ = op
            return .modifyWorkspace
        default:
            return .modifyWorkspace
        }
    }

    static func sideEffectClass(forOperation operation: String) -> SideEffectClass {
        switch operation {
        case let op where op.hasPrefix("fs.read"), let op where op.hasPrefix("git.diff"):
            _ = op
            return .none
        default:
            return .local
        }
    }
}
