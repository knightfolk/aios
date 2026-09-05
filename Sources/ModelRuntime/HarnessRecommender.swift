import Foundation
import AIOSCore

/// Empirical harness/model selection from measured trajectories (docs 09:
/// routing evidence with sample counts — never overfit from a few tasks).
public struct HarnessRecommendation: Sendable, Equatable {
    public struct ModelEvidence: Sendable, Equatable {
        public var modelID: String
        public var samples: Int
        public var successRate: Double
        public var avgLatencyMs: Double
    }

    public var preferredModelID: String?
    public var evidence: ModelEvidence?
    public var reason: String
}

public enum HarnessRecommender {
    /// Ranks candidates for a task class by measured success rate, then
    /// latency, among models with at least `minimumSamples` observations.
    /// Below the floor there is no preference — the caller keeps defaults.
    public static func recommend(
        candidates: [String],
        telemetry: [RoutingTelemetry],
        taskClass: String,
        minimumSamples: Int
    ) -> HarnessRecommendation {
        var evidence: [String: HarnessRecommendation.ModelEvidence] = [:]
        for modelID in candidates {
            let rows = telemetry.filter { $0.modelID == modelID && $0.taskClass == taskClass }
            guard rows.count >= minimumSamples else { continue }
            let successes = rows.filter { $0.outcome == "SUCCEEDED" }.count
            let avgLatency = rows.reduce(0.0) { $0 + $1.latencyMs } / Double(rows.count)
            evidence[modelID] = .init(
                modelID: modelID,
                samples: rows.count,
                successRate: Double(successes) / Double(rows.count),
                avgLatencyMs: avgLatency
            )
        }

        guard !evidence.isEmpty else {
            return HarnessRecommendation(
                preferredModelID: nil, evidence: nil,
                reason: "insufficient samples (floor \(minimumSamples)) for \(candidates.joined(separator: ", ")); keeping defaults"
            )
        }

        let ranked = evidence.values.sorted { lhs, rhs in
            if lhs.successRate != rhs.successRate {
                return lhs.successRate > rhs.successRate
            }
            return lhs.avgLatencyMs < rhs.avgLatencyMs
        }
        let winner = ranked[0]
        return HarnessRecommendation(
            preferredModelID: winner.modelID,
            evidence: winner,
            reason: "measured: \(Int(winner.successRate * 100))% success over \(winner.samples) samples, avg \(Int(winner.avgLatencyMs))ms"
        )
    }
}
