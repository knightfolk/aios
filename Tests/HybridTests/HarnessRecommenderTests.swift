import Foundation
import Testing
@testable import AIOSCore
@testable import ModelRuntime
@testable import EvaluationEngine

// Item: close the quality loop — measured telemetry feeds harness/model
// selection (docs 09: empirical, version-aware routing evidence).

@Test func recommenderPrefersMeasuredWinners() throws {
    let rows: [RoutingTelemetry] = [
        // qwen: 3 successes, 1 failure, avg 1000ms
        RoutingTelemetry(modelID: "qwen25-7b", revision: "1", quantization: "4bit", runtime: .mlx, harnessProfileID: "default-v1", taskClass: "coding", latencyMs: 1000, promptTokens: 10, completionTokens: 5, outcome: "SUCCEEDED"),
        RoutingTelemetry(modelID: "qwen25-7b", revision: "1", quantization: "4bit", runtime: .mlx, harnessProfileID: "default-v1", taskClass: "coding", latencyMs: 800, promptTokens: 10, completionTokens: 5, outcome: "SUCCEEDED"),
        RoutingTelemetry(modelID: "qwen25-7b", revision: "1", quantization: "4bit", runtime: .mlx, harnessProfileID: "default-v1", taskClass: "coding", latencyMs: 1200, promptTokens: 10, completionTokens: 5, outcome: "SUCCEEDED"),
        RoutingTelemetry(modelID: "qwen25-7b", revision: "1", quantization: "4bit", runtime: .mlx, harnessProfileID: "default-v1", taskClass: "coding", latencyMs: 1000, promptTokens: 10, completionTokens: 5, outcome: "FAILED"),
        // glm: 4 successes, avg 5000ms
        RoutingTelemetry(modelID: "glm-4.5-flash", revision: "1", quantization: "none", runtime: .cloudAPI, harnessProfileID: "default-v1", taskClass: "coding", latencyMs: 5000, promptTokens: 10, completionTokens: 5, outcome: "SUCCEEDED"),
        RoutingTelemetry(modelID: "glm-4.5-flash", revision: "1", quantization: "none", runtime: .cloudAPI, harnessProfileID: "default-v1", taskClass: "coding", latencyMs: 5000, promptTokens: 10, completionTokens: 5, outcome: "SUCCEEDED"),
        RoutingTelemetry(modelID: "glm-4.5-flash", revision: "1", quantization: "none", runtime: .cloudAPI, harnessProfileID: "default-v1", taskClass: "coding", latencyMs: 5000, promptTokens: 10, completionTokens: 5, outcome: "SUCCEEDED"),
        RoutingTelemetry(modelID: "glm-4.5-flash", revision: "1", quantization: "none", runtime: .cloudAPI, harnessProfileID: "default-v1", taskClass: "coding", latencyMs: 5000, promptTokens: 10, completionTokens: 5, outcome: "SUCCEEDED"),
    ]

    let recommendation = HarnessRecommender.recommend(
        candidates: ["qwen25-7b", "glm-4.5-flash"],
        telemetry: rows,
        taskClass: "coding",
        minimumSamples: 3
    )
    let winner = try #require(recommendation.preferredModelID as String?)
    #expect(winner == "glm-4.5-flash") // perfect success rate wins despite 5s latency
    #expect(recommendation.evidence?.samples == 4)
    #expect(recommendation.evidence?.successRate == 1.0)
}

@Test func recommenderKeepsDefaultBelowSampleFloor() {
    let rows = [
        RoutingTelemetry(modelID: "qwen25-7b", revision: "1", quantization: "4bit", runtime: .mlx, harnessProfileID: "default-v1", taskClass: "coding", latencyMs: 100, promptTokens: 0, completionTokens: 0, outcome: "SUCCEEDED"),
    ]
    let recommendation = HarnessRecommender.recommend(
        candidates: ["qwen25-7b"],
        telemetry: rows,
        taskClass: "coding",
        minimumSamples: 3
    )
    #expect(recommendation.preferredModelID == nil) // not enough evidence: no overfit
    #expect(recommendation.reason.contains("insufficient samples"))
}

@Test func recommenderTiesBreakOnLatency() {
    func row(_ model: String, latency: Double) -> RoutingTelemetry {
        RoutingTelemetry(modelID: model, revision: "1", quantization: "4bit", runtime: .mlx, harnessProfileID: "default-v1", taskClass: "coding", latencyMs: latency, promptTokens: 0, completionTokens: 0, outcome: "SUCCEEDED")
    }
    let rows = [
        row("a", latency: 300), row("a", latency: 500),
        row("b", latency: 100), row("b", latency: 200),
    ]
    let recommendation = HarnessRecommender.recommend(
        candidates: ["a", "b"], telemetry: rows, taskClass: "coding", minimumSamples: 2
    )
    #expect(recommendation.preferredModelID == "b") // same success rate, faster
}
