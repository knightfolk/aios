import Foundation
import AIOSCore
import EventJournal

/// Independent verification role (docs 07): a system function, not a
/// personality. Deterministic in v0 — it checks the TaskContract's
/// verification requirements against the evidence set and journals the
/// verdict. A worker's completion claim never satisfies a requirement by
/// itself.
public actor IndependentEvaluator {
    public enum Decision: String, Sendable, Equatable {
        case passed
        case failed
        case inconclusive
    }

    public struct Verdict: Sendable, Equatable {
        public var decision: Decision
        public var unmetRequirements: [String]
        public var notes: [String]
    }

    private let journal: JournalStore

    public init(journal: JournalStore) {
        self.journal = journal
    }

    public func evaluate(
        taskID: TaskID,
        requirements: [VerificationRequirement],
        evidence: [Evidence],
        result: WorkResult
    ) async throws -> Verdict {
        try await journal.append(.verificationStarted(.init(taskID: taskID, requirement: requirements.map(\.description).joined(separator: "; "))))

        var unmet: [String] = []
        var notes: [String] = []

        for requirement in requirements {
            let satisfied = evidence.contains { item in
                item.status == .valid && satisfies(item.verificationMethod, requirement.method)
            }
            if !satisfied {
                unmet.append(requirement.description)
            }
        }

        if result.status == .completed && !unmet.isEmpty {
            notes.append("completion claim rejected: evidence does not cover all verification requirements")
        }

        let decision: Decision
        switch (unmet.isEmpty, result.status) {
        case (true, .completed):
            decision = .passed
        case (false, _):
            decision = .failed
        case (true, _):
            // Requirements covered but the worker did not claim completion.
            decision = .inconclusive
            notes.append("requirements covered but worker status is \(result.status.rawValue)")
        }

        switch decision {
        case .passed:
            try await journal.append(.verificationPassed(.init(taskID: taskID, requirement: requirements.map(\.description).joined(separator: "; "))))
        case .failed:
            try await journal.append(.verificationFailed(.init(
                taskID: taskID,
                requirement: requirements.map(\.description).joined(separator: "; "),
                detail: "unmet: \(unmet.joined(separator: ", "))"
            )))
        case .inconclusive:
            try await journal.append(.verificationInconclusive(.init(
                taskID: taskID,
                requirement: requirements.map(\.description).joined(separator: "; "),
                detail: notes.joined(separator: "; ")
            )))
        }

        return Verdict(decision: decision, unmetRequirements: unmet, notes: notes)
    }

    private func satisfies(_ evidenceMethod: VerificationMethod, _ required: VerificationMethod) -> Bool {
        switch (evidenceMethod, required) {
        case (.deterministicCheck(let found), .deterministicCheck(let needed)):
            return found == needed
        default:
            return evidenceMethod == required
        }
    }
}
