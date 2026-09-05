import Foundation
import AIOSCore
import ModelRuntime

extension Router {
    public enum FallbackTrigger: Sendable, Equatable {
        case runtimeFailed
        case quotaExhausted
        case lostResidency
    }

    /// Checkpoint-boundary fallback (never mid-action). cloud→local is
    /// always permitted (it reduces exposure); local→cloud requires the
    /// privacy policy, a cloud-configured registry, and a real budget —
    /// never silent paid escalation. Returns nil when no legal fallback
    /// exists; the caller must escalate to the user.
    public static func planFallback(
        current: RuntimeKind,
        after trigger: FallbackTrigger,
        registry: RuntimeRegistry,
        policy: PrivacyPolicy,
        budget: SpendPolicy
    ) -> RoutingDecision? {
        let available = registry.availableRuntimes(policy: policy, budget: budget)
        let rationale = "fallback after \(trigger) on \(current.rawValue)"

        switch current {
        case .cloudAPI:
            if available.contains(.mlx) {
                return RoutingDecision(runtime: .mlx, topology: .singleAgent, rationale: [rationale, "local MLX resident"])
            }
            if available.contains(.scripted) {
                return RoutingDecision(runtime: .scripted, topology: .singleAgent, rationale: [rationale, "no local model; scripted fallback"])
            }
            return nil

        case .mlx, .scripted, .deterministic, .coreML:
            if available.contains(.cloudAPI) {
                return RoutingDecision(runtime: .cloudAPI, topology: .singleAgent, rationale: [rationale, "hybrid policy with budget permits cloud"])
            }
            if current != .scripted && available.contains(.scripted) {
                return RoutingDecision(runtime: .scripted, topology: .singleAgent, rationale: [rationale, "no cloud permitted; scripted fallback"])
            }
            return nil
        }
    }
}
