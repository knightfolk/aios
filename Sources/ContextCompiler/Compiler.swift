import Foundation
import AIOSCore

/// Compiles a bounded task context: contract inputs first, then candidates,
/// dropped in reverse priority order until the estimated token budget fits.
/// Context is compiled, not accumulated (Constitution #7) — no transcript
/// shoveling.
public struct ContextCompiler: Sendable {
    public init() {}

    public static func estimatedTokens(in bundle: ContextBundle) -> Int {
        bundle.selections
            .map { ($0.path.utf8.count + $0.reason.utf8.count) / 4 }
            .reduce(0, +)
    }

    public func compile(
        contract: TaskContract,
        candidates: [ContextSelection],
        priorHandoff: Handoff?,
        tokenBudget: Int
    ) -> ContextBundle {
        // Contract inputs are always prioritized; other candidates follow in
        // given order.
        let contractInputs = Set(contract.inputs)
        let prioritized = candidates.sorted { lhs, rhs in
            let lhsPriority = contractInputs.contains(lhs.path)
            let rhsPriority = contractInputs.contains(rhs.path)
            if lhsPriority != rhsPriority { return lhsPriority }
            return false // stable sort keeps given order otherwise
        }

        var selected: [ContextSelection] = []
        var used = 0
        for selection in prioritized {
            let cost = (selection.path.utf8.count + selection.reason.utf8.count) / 4
            if used + cost <= tokenBudget {
                selected.append(selection)
                used += cost
            }
        }

        return ContextBundle(selections: selected, tokenBudget: tokenBudget)
    }
}
