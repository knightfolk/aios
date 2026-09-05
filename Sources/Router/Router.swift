import Foundation
import AIOSCore
import ModelRuntime

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

    /// Legacy entry point from Phase 1: maps onto an implicit registry with
    /// no local model manifest and no cloud configuration.
    public func decide(
        capabilities: [CapabilityClass],
        privacyPolicy: PrivacyPolicy,
        spendPolicy: SpendPolicy,
        localRuntimeAvailable: Bool
    ) -> RoutingDecision {
        decide(
            capabilities: capabilities,
            privacyPolicy: privacyPolicy,
            spendPolicy: spendPolicy,
            registry: RuntimeRegistry(mlxManifest: nil, cloudConfigured: false),
            localRuntimeAvailable: localRuntimeAvailable
        )
    }

    public func decide(
        capabilities: [CapabilityClass],
        privacyPolicy: PrivacyPolicy,
        spendPolicy: SpendPolicy,
        registry: RuntimeRegistry,
        localRuntimeAvailable: Bool = true
    ) -> RoutingDecision {
        var rationale: [String] = []
        let available = registry.availableRuntimes(policy: privacyPolicy, budget: spendPolicy)

        if privacyPolicy == .localOnly {
            rationale.append("privacy policy is Local Only: cloud runtimes are excluded")
        } else if (spendPolicy.maxSpendUSD ?? 0) <= 0 && !spendPolicy.allowPaidCredits {
            rationale.append("budget is zero: cloud runtimes are excluded until the budget allows spend")
        }

        let runtime: RuntimeKind
        if available.contains(.mlx) {
            runtime = .mlx
            if let manifest = registry.mlxManifest {
                rationale.append("local MLX model \(manifest.modelID) (\(manifest.quantization)) is resident")
            }
        } else if available.contains(.cloudAPI) {
            runtime = .cloudAPI
            rationale.append("hybrid policy with $\(spendPolicy.maxSpendUSD ?? 0) budget permits cloud execution")
        } else if available.contains(.scripted) && localRuntimeAvailable {
            runtime = .scripted
            rationale.append("no capable model runtime resident; scripted fallback selected")
        } else {
            runtime = .deterministic
            rationale.append("no local runtime available; deterministic execution selected")
        }
        rationale.append("requested capabilities: \(capabilities.map(\.rawValue).sorted().joined(separator: ", "))")

        let topology: ExecutionTopology = capabilities == [.observe] ? .direct : .singleAgent
        rationale.append("simplest topology expected to satisfy the task class: \(topology.rawValue)")

        return RoutingDecision(runtime: runtime, topology: topology, rationale: rationale)
    }
}
