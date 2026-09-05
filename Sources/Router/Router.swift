import Foundation
import AIOSCore

/// Mostly deterministic capability/policy/budget selection. Every decision
/// carries its rationale so expensive or surprising choices are inspectable
/// (Constitution #28).
public struct RoutingDecision: Equatable, Sendable {
    public var runtime: RuntimeKind
    public var topology: ExecutionTopology
    public var rationale: [String]

    public init(runtime: RuntimeKind, topology: ExecutionTopology, rationale: [String]) {
        self.runtime = runtime
        self.topology = topology
        self.rationale = rationale
    }
}

public struct Router: Sendable {
    public init() {}

    public func decide(
        capabilities: [CapabilityClass],
        privacyPolicy: PrivacyPolicy,
        spendPolicy: SpendPolicy,
        localRuntimeAvailable: Bool
    ) -> RoutingDecision {
        var rationale: [String] = []

        let runtime: RuntimeKind
        if privacyPolicy == .localOnly {
            runtime = localRuntimeAvailable ? .scripted : .deterministic
            rationale.append("privacy policy is Local Only: cloud runtimes are excluded")
        } else if (spendPolicy.maxSpendUSD ?? 0) <= 0 && !spendPolicy.allowPaidCredits {
            runtime = localRuntimeAvailable ? .scripted : .deterministic
            rationale.append("budget is zero: cloud runtimes are excluded until the budget allows spend")
        } else {
            runtime = .cloudAPI
            rationale.append("hybrid policy with $\(spendPolicy.maxSpendUSD ?? 0) budget permits cloud execution")
        }
        rationale.append("requested capabilities: \(capabilities.map(\.rawValue).sorted().joined(separator: ", "))")

        let topology: ExecutionTopology = capabilities == [.observe] ? .direct : .singleAgent
        rationale.append("simplest topology expected to satisfy the task class: \(topology.rawValue)")

        return RoutingDecision(runtime: runtime, topology: topology, rationale: rationale)
    }
}
