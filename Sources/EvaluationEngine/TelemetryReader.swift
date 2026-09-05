import Foundation
import AIOSCore
import ModelRuntime

/// Reads routing telemetry recorded by `TelemetryWriter`.
public func readTelemetry(url: URL) throws -> [RoutingTelemetry] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return data.split(separator: 0x0A).compactMap { line in
        try? JSONDecoder().decode(RoutingTelemetry.self, from: line)
    }
}

public struct RuntimeSummary: Sendable, Equatable {
    public var attempts: Int
    public var avgLatencyMs: Double
}

/// Aggregate routing evidence per runtime (docs 09): measured, not assumed.
public func summarizeTelemetry(byRuntime rows: [RoutingTelemetry]) -> [RuntimeKind: RuntimeSummary] {
    var grouped: [RuntimeKind: [RoutingTelemetry]] = [:]
    for row in rows {
        grouped[row.runtime, default: []].append(row)
    }
    return grouped.mapValues { rowsForRuntime in
        let total = rowsForRuntime.reduce(0.0) { $0 + $1.latencyMs }
        return RuntimeSummary(
            attempts: rowsForRuntime.count,
            avgLatencyMs: rowsForRuntime.isEmpty ? 0 : total / Double(rowsForRuntime.count)
        )
    }
}
