import Foundation
import AIOSCore

/// Which runtimes are actually usable right now. `scripted` is always
/// available (the honest fallback); `mlx` requires a resident verified
/// manifest; `cloudAPI` requires configuration plus policy and budget.
public struct RuntimeRegistry: Sendable, Hashable {
    public var mlxManifest: ModelManifest?
    public var cloudConfigured: Bool

    public init(mlxManifest: ModelManifest? = nil, cloudConfigured: Bool = false) {
        self.mlxManifest = mlxManifest
        self.cloudConfigured = cloudConfigured
    }

    public func availableRuntimes(policy: PrivacyPolicy, budget: SpendPolicy) -> [RuntimeKind] {
        var runtimes: [RuntimeKind] = [.scripted]
        if mlxManifest != nil {
            runtimes.append(.mlx)
        }
        let cloudAllowedByPolicy = policy == .hybridAllowed
        let cloudAllowedByBudget = (budget.maxSpendUSD ?? 0) > 0 || budget.allowPaidCredits
        if cloudConfigured && cloudAllowedByPolicy && cloudAllowedByBudget {
            runtimes.append(.cloudAPI)
        }
        return runtimes
    }
}
