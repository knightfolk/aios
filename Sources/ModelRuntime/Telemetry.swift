import Foundation
import AIOSCore

/// One measured routing outcome (docs 09 routing evidence): the actual
/// configuration `model + revision + quantization + runtime + harness +
/// task class`, never a leaderboard opinion.
public struct RoutingTelemetry: Codable, Sendable, Equatable {
    public var modelID: String
    public var revision: String
    public var quantization: String
    public var runtime: RuntimeKind
    public var harnessProfileID: String
    public var taskClass: String
    public var latencyMs: Double
    public var promptTokens: Int
    public var completionTokens: Int
    public var outcome: String
    public var recordedAt: Date

    public init(
        modelID: String,
        revision: String,
        quantization: String,
        runtime: RuntimeKind,
        harnessProfileID: String,
        taskClass: String,
        latencyMs: Double,
        promptTokens: Int,
        completionTokens: Int,
        outcome: String,
        recordedAt: Date = Date()
    ) {
        self.modelID = modelID
        self.revision = revision
        self.quantization = quantization
        self.runtime = runtime
        self.harnessProfileID = harnessProfileID
        self.taskClass = taskClass
        self.latencyMs = latencyMs
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.outcome = outcome
        self.recordedAt = recordedAt
    }
}

/// Append-only JSONL writer. One line per attempt, fsync-free (telemetry is
/// best-effort; the journal remains authoritative).
public struct TelemetryWriter: Sendable {
    public let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    public func append(_ row: RoutingTelemetry) throws {
        let line = try JSONEncoder().encode(row) + Data("\n".utf8)
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingAtPath: url.path)
        defer { try? handle?.close() }
        try handle?.seekToEnd()
        try handle?.write(contentsOf: line)
    }
}
