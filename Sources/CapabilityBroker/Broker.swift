import Foundation
import CryptoKit
import AIOSCore
import EventJournal
import SecurityKernel

/// The single typed access layer between Brains and reality. Implements the
/// docs-08 action transaction lifecycle — Prepare → Validate → Authorize →
/// Execute → Observe → Reconcile — and journals every phase. It refuses to
/// retry actions whose outcome is UNKNOWN until they are reconciled.
public actor CapabilityBroker {
    /// Result of the Prepare/Validate phase. Carries the frozen precondition
    /// hashes so `perform` can detect stale state immediately before
    /// execution.
    public struct PreparedAction: Sendable {
        public let request: ActionRequest
        public let policy: SecurityPolicy
        public let preconditionHashes: [String: String]
        public let rejection: ActionResult?

        init(request: ActionRequest, policy: SecurityPolicy, preconditionHashes: [String: String] = [:], rejection: ActionResult? = nil) {
            self.request = request
            self.policy = policy
            self.preconditionHashes = preconditionHashes
            self.rejection = rejection
        }
    }

    private let journal: JournalStore
    private let executor: any HandExecutor
    private var awaitingReconciliation: Set<ActionID> = []

    public init(journal: JournalStore, executor: any HandExecutor = LocalHandExecutor()) {
        self.journal = journal
        self.executor = executor
    }

    // MARK: - Prepare / Validate / Authorize

    public func prepare(_ request: ActionRequest, policy: SecurityPolicy) async -> PreparedAction {
        try? await journal.append(.actionRequested(.init(request: request)))

        func reject(_ reason: String) -> PreparedAction {
            PreparedAction(request: request, policy: policy, rejection: ActionResult(
                actionID: request.actionID,
                outcome: .rejected,
                startedAt: Date(), endedAt: Date(),
                failureDetails: reason
            ))
        }

        if awaitingReconciliation.contains(request.actionID) {
            return reject("action outcome is UNKNOWN; reconciliation required before retry")
        }

        if policy.localOnly {
            if case .rejected(let reason) = LocalOnlyEnforcer.decide(request) {
                return reject(reason)
            }
        }

        if request.sideEffectClass == .external && !policy.allowExternalConsequences {
            return reject("external consequence requires explicit user approval")
        }

        if request.capability == .operateComputer && !policy.allowComputerControl {
            return reject("computer control requires an explicit lease-backed policy grant")
        }

        if request.capability == .operateComputer {
            // Targets are AX references / bundle ids, not filesystem paths:
            // gated by the explicit policy grant + the lease, not roots.
        } else if request.operation == "shell.run" {
            // The target is an executable (constrained by the allowlist and
            // Local Only); the workspace scope applies to the working
            // directory the command runs in.
            if case .text(let cwd)? = request.parameters["cwd"] {
                let normalizedCwd = ScopeEnforcer.normalized(cwd)
                let inside = policy.workspaceRoots
                    .map(ScopeEnforcer.normalized)
                    .contains { normalizedCwd == $0 || normalizedCwd.hasPrefix($0 + "/") }
                if !inside {
                    return reject("cwd \(cwd) is outside the approved workspace roots")
                }
            }
            let executable = request.target.split(separator: " ").first.map(String.init) ?? request.target
            if !policy.allowedCommands.contains(executable) {
                return reject("command \(executable) is not on the allowlist")
            }
        } else if case .rejected(let reason) = ScopeEnforcer.decide(request, policy: policy) {
            return reject(reason)
        }

        // Capture precondition hashes for existing files the action touches.
        var hashes: [String: String] = [:]
        for precondition in request.preconditions {
            hashes[precondition.target] = Self.contentHash(at: precondition.target)
        }
        let writeTarget = request.target.split(separator: " ").first.map(String.init) ?? request.target
        if request.operation == "fs.write" || request.operation == "fs.read" {
            hashes[writeTarget] = Self.contentHash(at: writeTarget)
        }

        return PreparedAction(request: request, policy: policy, preconditionHashes: hashes)
    }

    // MARK: - Execute / Observe

    public func perform(_ prepared: PreparedAction) async -> ActionResult {
        let startedAt = Date()
        let request = prepared.request

        if let rejection = prepared.rejection {
            try? await journal.append(.actionExecuted(.init(result: rejection)))
            return rejection
        }

        try? await journal.append(.actionAuthorized(.init(
            actionID: request.actionID,
            authorizedScope: prepared.preconditionHashes.keys.sorted().joined(separator: ",")
        )))

        // Stale precondition check: reality must match what was validated.
        for (path, captured) in prepared.preconditionHashes {
            if Self.contentHash(at: path) != captured {
                let stale = ActionResult(
                    actionID: request.actionID,
                    outcome: .stalePrecondition,
                    startedAt: startedAt, endedAt: Date(),
                    observedEffects: ["\(path) changed after validation"],
                    failureDetails: "precondition for \(path) is stale; refusing to execute"
                )
                try? await journal.append(.actionExecuted(.init(result: stale)))
                return stale
            }
        }

        let result = await executeEffect(of: request, startedAt: startedAt)
        try? await journal.append(.actionExecuted(.init(result: result)))
        if result.outcome == .unknown {
            awaitingReconciliation.insert(request.actionID)
        }
        return result
    }

    public func execute(_ request: ActionRequest, policy: SecurityPolicy) async -> ActionResult {
        await perform(await prepare(request, policy: policy))
    }

    // MARK: - Reconcile

    public func reconcile(_ actionID: ActionID, resolved: ActionOutcome, note: String) async throws {
        try await journal.append(.actionReconciled(.init(
            actionID: actionID, resolvedOutcome: resolved, note: note
        )))
        awaitingReconciliation.remove(actionID)
    }

    // MARK: - Effects

    private func executeEffect(of request: ActionRequest, startedAt: Date) async -> ActionResult {
        do {
            switch request.operation {
            case "fs.read":
                let data = try executor.readFile(at: request.target)
                return ActionResult(
                    actionID: request.actionID, outcome: .succeeded,
                    startedAt: startedAt, endedAt: Date(),
                    observedEffects: ["read \(data.count) bytes from \(request.target)"],
                    stateBeforeReference: Self.contentHash(at: request.target)
                )

            case "fs.write":
                guard case .text(let contents)? = request.parameters["contents"] else {
                    return ActionResult(
                        actionID: request.actionID, outcome: .rejected,
                        startedAt: startedAt, endedAt: Date(),
                        failureDetails: "fs.write requires a text contents parameter"
                    )
                }
                let before = Self.contentHash(at: request.target)
                try executor.writeFile(at: request.target, contents: Data(contents.utf8))
                return ActionResult(
                    actionID: request.actionID, outcome: .succeeded,
                    startedAt: startedAt, endedAt: Date(),
                    observedEffects: ["wrote \(contents.utf8.count) bytes to \(request.target)"],
                    stateBeforeReference: before,
                    stateAfterReference: Self.contentHash(at: request.target)
                )

            case "shell.run":
                let executable = request.target.split(separator: " ").first.map(String.init) ?? request.target
                let arguments: [String]
                if case .text(let joined)? = request.parameters["arguments"] {
                    arguments = joined.split(separator: " ").map(String.init)
                } else {
                    arguments = []
                }
                let cwd: String
                if case .text(let dir)? = request.parameters["cwd"] {
                    cwd = dir
                } else if let root = request.preconditions.first?.target {
                    cwd = (root as NSString).deletingLastPathComponent
                } else {
                    cwd = FileManager.default.currentDirectoryPath
                }
                let timeout = request.timeout ?? 120
                let shell = await executor.runCommand(cwd: cwd, command: executable, arguments: arguments, timeout: timeout)
                let outcome: ActionOutcome = shell.timedOut
                    ? .timedOut
                    : (shell.exitCode == 0 ? .succeeded : .failed)
                return ActionResult(
                    actionID: request.actionID, outcome: outcome,
                    startedAt: startedAt, endedAt: Date(),
                    observedEffects: ["exit \(shell.exitCode)"],
                    stdoutReference: "inline:\(shell.stdout.prefix(200))",
                    stderrReference: shell.stderr.isEmpty ? nil : "inline:\(shell.stderr.prefix(200))",
                    failureDetails: shell.timedOut ? "command timed out after \(timeout)s" : nil
                )

            case "git.worktree", "git.diff", "git.status":
                return ActionResult(
                    actionID: request.actionID, outcome: .rejected,
                    startedAt: startedAt, endedAt: Date(),
                    failureDetails: "\(request.operation) arrives with the Phase 1 slice executor; not yet wired"
                )

            default:
                return ActionResult(
                    actionID: request.actionID, outcome: .rejected,
                    startedAt: startedAt, endedAt: Date(),
                    failureDetails: "unsupported operation \(request.operation)"
                )
            }
        } catch let error as HandError {
            // Constitution #13: unknown stays unknown until reconciled.
            if case .uncertainOutcome(let detail) = error {
                return ActionResult(
                    actionID: request.actionID, outcome: .unknown,
                    startedAt: startedAt, endedAt: Date(),
                    observedEffects: ["executor could not confirm the effect"],
                    reconciliationRequired: true,
                    failureDetails: detail
                )
            }
            return ActionResult(
                actionID: request.actionID, outcome: .failed,
                startedAt: startedAt, endedAt: Date(),
                failureDetails: "\(error)"
            )
        } catch {
            return ActionResult(
                actionID: request.actionID, outcome: .failed,
                startedAt: startedAt, endedAt: Date(),
                failureDetails: "\(error)"
            )
        }
    }

    // MARK: - Hashing

    /// SHA-256 of a file's contents, or "<absent>" when the file does not
    /// exist (a file appearing also counts as a state change).
    static func contentHash(at path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path) else { return "<absent>" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
