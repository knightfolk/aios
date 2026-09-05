import Foundation
import AIOSCore

/// A stable expert identity (docs 07). Names are product shorthand for a
/// behavior/domain, not impersonation; `displayName` can be rebranded
/// without touching role IDs or stored project state.
public struct Expert: Codable, Sendable, Hashable {
    public var identity: ExpertID
    public var role: ExpertRole
    public var displayName: String
    public var domain: String
    public var responsibilities: [String]

    public init(identity: ExpertID, role: ExpertRole, displayName: String, domain: String, responsibilities: [String]) {
        self.identity = identity
        self.role = role
        self.displayName = displayName
        self.domain = domain
        self.responsibilities = responsibilities
    }
}

/// The permanent team plus temporary-specialist construction. Expert
/// identity is independent of model, provider, or runtime: routing changes
/// the brain, never the identity (Constitution #8).
public enum ExpertTeam {
    public static func permanentTeam() -> [Expert] {
        [
            Expert(identity: ExpertID(), role: .concierge, displayName: "Concierge", domain: "system guide / front desk",
                   responsibilities: ["onboarding", "navigation", "explain what is happening", "route simple requests"]),
            Expert(identity: ExpertID(), role: .linus, displayName: "Linus", domain: "engineering / coding",
                   responsibilities: ["implementation", "debugging", "architecture", "systems"]),
            Expert(identity: ExpertID(), role: .jobs, displayName: "Jobs", domain: "product / UX / taste",
                   responsibilities: ["product definition", "simplification", "coherence", "user-facing decisions"]),
            Expert(identity: ExpertID(), role: .einstein, displayName: "Einstein", domain: "science / math / modeling",
                   responsibilities: ["formal reasoning", "simulations", "quantitative verification"]),
            Expert(identity: ExpertID(), role: .sherlock, displayName: "Sherlock", domain: "research / investigation",
                   responsibilities: ["source verification", "contradiction detection", "missing-work discovery"]),
            Expert(identity: ExpertID(), role: .henson, displayName: "Henson", domain: "creative media",
                   responsibilities: ["visual art", "music", "media production"]),
            Expert(identity: ExpertID(), role: .chloe, displayName: "Chloe", domain: "computer operation",
                   responsibilities: ["application control", "GUI automation", "cross-app workflows"]),
        ]
    }

    /// Temporary specialists are role packages with functional names and
    /// finite lifetimes (docs 07) — never celebrity personas.
    public static func specialist(name: String, domain: String) -> Expert {
        Expert(
            identity: ExpertID(),
            role: .specialist(name: name),
            displayName: name,
            domain: domain,
            responsibilities: ["bounded consultation scoped by the requesting task"]
        )
    }
}
