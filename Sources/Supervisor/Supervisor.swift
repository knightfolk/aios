import Foundation
import AIOSCore
import EventJournal

/// Mostly deterministic, event-driven execution monitor (docs 07). It never
/// polls an expensive orchestrator; it consumes action results and emits
/// directives: halt loops, block contract drift, refuse over-budget spend.
public actor Supervisor {
    public enum Directive: Equatable, Sendable {
        case proceed
        case haltAndEscalate(reason: String)
        case blockAttempt(reason: String)
        case refuseSpend(reason: String)
    }

    public struct Configuration: Sendable {
        /// How many equivalent failures (same capability+operation+outcome)
        /// are tolerated before the attempt is halted and escalated.
        public var equivalentFailureStrikeLimit: Int
        public var maxSpendUSD: Double

        public init(equivalentFailureStrikeLimit: Int = 3, maxSpendUSD: Double = 0) {
            self.equivalentFailureStrikeLimit = equivalentFailureStrikeLimit
            self.maxSpendUSD = maxSpendUSD
        }
    }

    private let configuration: Configuration
    private let journal: JournalStore
    private var failureStrikes: [String: Int] = [:]

    public init(configuration: Configuration = Configuration(), journal: JournalStore) {
        self.configuration = configuration
        self.journal = journal
    }

    /// Inspects one action result against the frozen task contract. Purely
    /// deterministic: same inputs, same directive.
    public func inspect(_ result: ActionResult, for request: ActionRequest, contract: TaskContract?) async -> Directive {
        // Contract drift: the target must fall inside the frozen scope.
        if let contract {
            let target = request.target.split(separator: " ").first.map(String.init) ?? request.target
            let inScope = contract.allowedScope.contains { scope in
                target == scope || target.hasPrefix(scope.hasSuffix("/") ? scope : scope + "/")
            }
            if !inScope {
                let directive = Directive.blockAttempt(reason: "action target \(target) drifts outside the task contract scope")
                await escalate(subject: "contract drift", question: "Attempt touched \(target) outside its TaskContract. Block or revise the contract?", blocking: true)
                return directive
            }
        }

        switch result.outcome {
        case .failed, .timedOut, .stalePrecondition:
            let signature = "\(request.capability.rawValue)|\(request.operation)|\(result.outcome.rawValue)"
            failureStrikes[signature, default: 0] += 1
            let strikes = failureStrikes[signature] ?? 0
            if strikes >= configuration.equivalentFailureStrikeLimit {
                await escalate(
                    subject: "repeated equivalent failure",
                    question: "Action \(request.operation) failed identically \(strikes) times. Halt and change strategy or replan?",
                    blocking: true
                )
                return .haltAndEscalate(reason: "repeated equivalent failure of \(request.operation) (\(strikes) strikes)")
            }
        case .succeeded:
            // A success clears the strike count for this operation's failure
            // signatures.
            for outcome in [ActionOutcome.failed, .timedOut, .stalePrecondition] {
                failureStrikes["\(request.capability.rawValue)|\(request.operation)|\(outcome.rawValue)"] = 0
            }
        default:
            break
        }
        return .proceed
    }

    /// Spending never silently escalates beyond policy (Constitution #24/#26).
    public func checkSpend(projectedAdditionUSD: Double) async -> Directive {
        guard projectedAdditionUSD <= configuration.maxSpendUSD else {
            await escalate(
                subject: "spend over budget",
                question: "Projected spend $\(projectedAdditionUSD) exceeds the $\(configuration.maxSpendUSD) budget. Raise the budget or reroute?",
                blocking: false
            )
            return .refuseSpend(reason: "projected spend $\(projectedAdditionUSD) exceeds budget $\(configuration.maxSpendUSD)")
        }
        return .proceed
    }

    private func escalate(subject: String, question: String, blocking: Bool) async {
        try? await journal.append(.decisionRequested(.init(
            subject: subject, question: question, blocking: blocking
        )))
    }
}
