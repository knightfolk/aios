import Foundation
import Testing
@testable import AIOSCore
@testable import ModelRuntime
@testable import EvaluationEngine

@Test func telemetryRoundTripsAndSummarizes() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-telemetry-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }

    let writer = TelemetryWriter(url: url)
    try writer.append(RoutingTelemetry(
        modelID: "qwen25-7b", revision: "1", quantization: "4bit", runtime: .mlx,
        harnessProfileID: "default-v1", taskClass: "coding",
        latencyMs: 1200, promptTokens: 300, completionTokens: 80, outcome: "SUCCEEDED"
    ))
    try writer.append(RoutingTelemetry(
        modelID: "glm-4.6", revision: "1", quantization: "none", runtime: .cloudAPI,
        harnessProfileID: "default-v1", taskClass: "coding",
        latencyMs: 900, promptTokens: 300, completionTokens: 80, outcome: "SUCCEEDED"
    ))
    try writer.append(RoutingTelemetry(
        modelID: "qwen25-7b", revision: "1", quantization: "4bit", runtime: .mlx,
        harnessProfileID: "default-v1", taskClass: "coding",
        latencyMs: 600, promptTokens: 100, completionTokens: 20, outcome: "FAILED"
    ))

    let rows = try readTelemetry(url: url)
    #expect(rows.count == 3)

    let summary = summarizeTelemetry(byRuntime: rows)
    #expect(summary[.mlx]?.attempts == 2)
    #expect(summary[.mlx]?.avgLatencyMs == 900) // (1200 + 600) / 2
    #expect(summary[.cloudAPI]?.attempts == 1)
    #expect(summary[.cloudAPI]?.avgLatencyMs == 900)
}

@Test func telemetryWriterAppendsAtomicallyPerLine() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-telemetry-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    let writer = TelemetryWriter(url: url)
    for index in 0..<50 {
        try writer.append(RoutingTelemetry(
            modelID: "m", revision: "1", quantization: "4bit", runtime: .scripted,
            harnessProfileID: "default-v1", taskClass: "test",
            latencyMs: Double(index), promptTokens: 0, completionTokens: 0, outcome: "SUCCEEDED"
        ))
    }
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 50)
}
