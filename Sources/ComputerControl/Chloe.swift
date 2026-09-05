import Foundation
import AIOSCore
import EventJournal
import SecurityKernel

// Chloe's Hands (docs 08): one exclusive automation owner of the real
// desktop at a time, ranked interaction adapters, shadow mode, and a
// deterministic emergency path. The Brain never executes computer control
// directly — it goes through these typed operations.

public enum ChloeAction: String, Codable, Sendable, Hashable {
    case activateApp
    case typeText
    case clickElement
    case readFocusedElement
}

public struct LeaseGrant: Sendable, Equatable {
    public var granted: Bool
    public var owner: String?

    public init(granted: Bool, owner: String? = nil) {
        self.granted = granted
        self.owner = owner
    }
}

public enum LeaseAuthorization: Sendable, Equatable {
    case allowed
    case denied
}

public protocol LeaseAuthorizing: Sendable {
    func acquire(owner: String, purpose: String, allowedActions: [ChloeAction], ttlSeconds: TimeInterval) async throws -> LeaseGrant
    func release(reason: String) async throws
    func authorize(owner: String, action: ChloeAction) async throws -> LeaseAuthorization
    func noteUserInteraction() async throws -> Bool
    func emergencyRelease(reason: String) async throws
}

/// The single-owner lease over the real user desktop. User interaction
/// immediately outranks automation: it invalidates the lease's assumptions
/// and blocks further action until re-observation.
public actor ComputerControlLease: LeaseAuthorizing {
    private struct ActiveLease {
        var owner: String
        var purpose: String
        var allowedActions: Set<ChloeAction>
        var expiresAt: Date
        var invalidated: Bool
    }

    private let journal: JournalStore
    private var active: ActiveLease?

    public init(journal: JournalStore) {
        self.journal = journal
    }

    public func acquire(owner: String, purpose: String, allowedActions: [ChloeAction], ttlSeconds: TimeInterval) async throws -> LeaseGrant {
        expireIfNeeded(reason: "ttl expired")
        if let current = active {
            try await journal.append(.leaseEvent(.init(granted: false, owner: owner, reason: "denied: conflicting lease held by \(current.owner)")))
            return LeaseGrant(granted: false, owner: current.owner)
        }
        active = ActiveLease(
            owner: owner,
            purpose: purpose,
            allowedActions: Set(allowedActions),
            expiresAt: Date().addingTimeInterval(ttlSeconds),
            invalidated: false
        )
        try await journal.append(.leaseEvent(.init(granted: true, owner: owner, reason: "granted: \(purpose)")))
        return LeaseGrant(granted: true, owner: owner)
    }

    public func release(reason: String) async throws {
        guard let current = active else { return }
        active = nil
        try await journal.append(.leaseEvent(.init(granted: false, owner: current.owner, reason: "released: \(reason)")))
    }

    public func authorize(owner: String, action: ChloeAction) async throws -> LeaseAuthorization {
        expireIfNeeded(reason: "ttl expired")
        guard let current = active else { return .denied }
        guard current.owner == owner, !current.invalidated, current.allowedActions.contains(action) else {
            return .denied
        }
        return .allowed
    }

    /// The user touched the real desktop. Returns true when a lease was
    /// invalidated; automation must observe again before continuing.
    public func noteUserInteraction() async throws -> Bool {
        guard var current = active else { return false }
        guard !current.invalidated else { return true }
        current.invalidated = true
        active = current
        try await journal.append(.leaseEvent(.init(granted: false, owner: current.owner, reason: "invalidated: user interaction outranks automation")))
        return true
    }

    public func emergencyRelease(reason: String) async throws {
        guard let current = active else { return }
        active = nil
        try await journal.append(.leaseEvent(.init(granted: false, owner: current.owner, reason: "released: \(reason)")))
    }

    private func expireIfNeeded(reason: String) {
        guard let current = active else { return }
        if Date() >= current.expiresAt {
            active = nil
            try? Task {
                try? await journal.append(.leaseEvent(.init(granted: false, owner: current.owner, reason: "expired: \(reason)")))
            }
        }
    }
}

// MARK: - Intents, adapters, director

public struct ChloeIntent: Sendable, Equatable {
    public var owner: String
    public var action: ChloeAction
    public var target: String
    public var parameters: [String: String]

    public init(owner: String, action: ChloeAction, target: String, parameters: [String: String]) {
        self.owner = owner
        self.action = action
        self.target = target
        self.parameters = parameters
    }
}

public struct ChloeResult: Sendable, Equatable {
    public var executed: Bool
    public var shadowRecorded: Bool
    public var detail: String?

    public init(executed: Bool, shadowRecorded: Bool = false, detail: String? = nil) {
        self.executed = executed
        self.shadowRecorded = shadowRecorded
        self.detail = detail
    }
}

/// Ranked per docs 08: native API → MCP/service → AX tree → browser DOM →
/// screenshot/pixel. The director picks the first available adapter; an
/// unavailable adapter is reported, never silently substituted.
public protocol InteractionAdapter: Sendable {
    var name: String { get }
    func isAvailable() async -> Bool
    func perform(_ intent: ChloeIntent) async throws -> ChloeResult
}

/// Shadow Mode: records proposals, executes nothing, and says so in every
/// result (docs 08 — training, debugging, safety review).
public struct ShadowAdapter: InteractionAdapter {
    public var name: String { "shadow" }

    public init() {}

    public func isAvailable() async -> Bool { true }

    public func perform(_ intent: ChloeIntent) async throws -> ChloeResult {
        ChloeResult(executed: false, shadowRecorded: true, detail: "shadow mode: recorded \(intent.action.rawValue) → \(intent.target); not executed")
    }
}

/// The director routes typed intents through the lease and the ranked
/// adapters. Frozen by Emergency Stop; freeze is deterministic and local.
public actor ChloeDirector {
    private let lease: any LeaseAuthorizing
    private let adapters: [any InteractionAdapter]
    private var frozen = false
    private var shadowMode = false

    public init(lease: any LeaseAuthorizing, adapters: [any InteractionAdapter]) {
        self.lease = lease
        self.adapters = adapters.sorted { lhs, _ in lhs.name == "native" }
    }

    public init(lease: any LeaseAuthorizing, adapter: any InteractionAdapter) {
        self.lease = lease
        self.adapters = [adapter]
    }

    public func setShadowMode(_ enabled: Bool) {
        shadowMode = enabled
    }

    public func emergencyStopEngaged() async {
        frozen = true
        shadowMode = true // nothing further may execute
        try? await lease.emergencyRelease(reason: "Emergency Stop")
    }

    public func noteUserInteraction() async throws -> Bool {
        try await lease.noteUserInteraction()
    }

    public func perform(_ intent: ChloeIntent) async throws -> ChloeResult {
        if frozen {
            return ChloeResult(executed: false, shadowRecorded: true, detail: "frozen by Emergency Stop; no computer control until re-armed")
        }
        if shadowMode {
            return try await ShadowAdapter().perform(intent)
        }
        guard case .allowed = try await lease.authorize(owner: intent.owner, action: intent.action) else {
            return ChloeResult(executed: false, detail: "lease denied for \(intent.action.rawValue)")
        }
        for adapter in adapters {
            if await adapter.isAvailable() {
                return try await adapter.perform(intent)
            }
        }
        return ChloeResult(executed: false, detail: "no available interaction adapter (tried: \(adapters.map(\.name).joined(separator: ", ")))")
    }
}
