import Foundation
import AIOSCore

/// Goal-level working envelope (docs 08). Enforced deterministically outside
/// any model — never negotiable by untrusted input.
public struct SecurityPolicy: Codable, Sendable, Hashable {
    public var workspaceRoots: [String]
    /// Absolute executable paths the `shell.run` operation may launch.
    public var allowedCommands: [String]
    /// Local Only boundary: blocks cloud inference, remote tools, browser and
    /// shell networking, telemetry, remote workers, and uploads.
    public var localOnly: Bool
    /// External-consequence actions need explicit user approval; v0 denies.
    public var allowExternalConsequences: Bool
    /// Computer control is lease-gated; the broker refuses it unless the
    /// policy explicitly opted in (docs 08 capability class).
    public var allowComputerControl: Bool

    public init(
        workspaceRoots: [String] = [],
        allowedCommands: [String] = [],
        localOnly: Bool = true,
        allowExternalConsequences: Bool = false,
        allowComputerControl: Bool = false
    ) {
        self.workspaceRoots = workspaceRoots
        self.allowedCommands = allowedCommands
        self.localOnly = localOnly
        self.allowExternalConsequences = allowExternalConsequences
        self.allowComputerControl = allowComputerControl
    }
}

public enum PolicyDecision: Equatable, Sendable {
    case authorized(scope: String)
    case rejected(reason: String)
}

/// Deterministic Local Only enforcement (docs 08: a badge is not sufficient).
public enum LocalOnlyEnforcer {
    public static let blockedOperationPrefixes: Set<String> = [
        "cloud.", "mcp.", "net.", "http.", "browser.", "telemetry.", "remote.",
    ]
    public static let blockedShellCommands: Set<String> = [
        "/usr/bin/curl", "/usr/bin/wget", "/usr/bin/nc", "/usr/bin/ssh",
        "/usr/bin/scp", "/usr/bin/ftp", "/usr/bin/telnet", "/usr/bin/ping",
        "/usr/sbin/ping", "/usr/bin/rsync",
    ]

    public static func decide(_ request: ActionRequest) -> PolicyDecision {
        let executable = request.target.split(separator: " ").first.map(String.init) ?? request.target
        if blockedShellCommands.contains(executable) {
            return .rejected(reason: "Local Only blocks network-capable command \(executable)")
        }
        if blockedOperationPrefixes.contains(where: { request.operation.hasPrefix($0) }) {
            return .rejected(reason: "Local Only blocks operation \(request.operation)")
        }
        if request.target.hasPrefix("http://") || request.target.hasPrefix("https://") || request.target.hasPrefix("s3://") {
            return .rejected(reason: "Local Only blocks network target \(request.target)")
        }
        if request.sideEffectClass == .external {
            return .rejected(reason: "Local Only blocks external side effects without explicit approval")
        }
        return .authorized(scope: "local")
    }
}

/// Workspace scope containment: every touched path must live under one of the
/// policy's roots, with no `..` escape.
public enum ScopeEnforcer {
    public static func decide(_ request: ActionRequest, policy: SecurityPolicy) -> PolicyDecision {
        let path = normalized(request.target.split(separator: " ").first.map(String.init) ?? request.target)
        guard !path.contains("/../") else {
            return .rejected(reason: "path traversal rejected: \(path)")
        }
        for root in policy.workspaceRoots.map(normalized) where path == root || path.hasPrefix(root + "/") {
            return .authorized(scope: path)
        }
        return .rejected(reason: "target \(path) is outside the approved workspace roots")
    }

    public static func normalized(_ path: String) -> String {
        (path as NSString).resolvingSymlinksInPath
    }
}
