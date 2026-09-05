import Foundation
import AIOSCore

/// Versioned wire messages exchanged between the host and worker processes
/// over framed stdio. This is the only place ad hoc JSON is tolerated — it is
/// the process boundary (AGENTS: versioned wire schemas across boundaries).
public enum WireMessage: Codable, Sendable, Hashable {
    case helloRequest(HelloRequest)
    case helloResponse(HelloResponse)
    case workPackage(WorkPackage)
    case actionRequest(ActionRequest)
    case actionResult(ActionResult)
    case workResult(WorkResult)
    case heartbeat(Heartbeat)
    case log(String)
    case cancel(String)
    case execute(ShellExecutionRequest)
    case executionFinished(ShellExecutionResult)
    case shutdown
}

public struct HelloRequest: Codable, Sendable, Hashable {
    public var protocolVersion: UInt
    public init(protocolVersion: UInt) { self.protocolVersion = protocolVersion }
}

public struct HelloResponse: Codable, Sendable, Hashable {
    public var protocolVersion: UInt
    public var workerID: String
    public var runtime: RuntimeKind
    public init(protocolVersion: UInt, workerID: String, runtime: RuntimeKind) {
        self.protocolVersion = protocolVersion
        self.workerID = workerID
        self.runtime = runtime
    }
}

public struct Heartbeat: Codable, Sendable, Hashable {
    public var workerID: String
    public var at: Date
    public init(workerID: String, at: Date = Date()) {
        self.workerID = workerID
        self.at = at
    }
}

/// A shell command the broker has already authorized; the ToolWorker only
/// executes it in isolation and reports what it observed.
public struct ShellExecutionRequest: Codable, Sendable, Hashable {
    public var executionID: String
    public var cwd: String
    public var command: String
    public var arguments: [String]
    public var timeoutSeconds: Double

    public init(executionID: String, cwd: String, command: String, arguments: [String], timeoutSeconds: Double) {
        self.executionID = executionID
        self.cwd = cwd
        self.command = command
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct ShellExecutionResult: Codable, Sendable, Hashable {
    public var executionID: String
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool

    public init(executionID: String, exitCode: Int32, stdout: String, stderr: String, timedOut: Bool) {
        self.executionID = executionID
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

/// Splits a byte stream into length-prefixed payloads (4-byte big-endian
/// length followed by that many bytes).
public struct StreamFramer {
    private var buffer = Data()
    public init() {}

    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var payloads: [Data] = []
        while buffer.count >= 4 {
            let length = Int(buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) })
            guard buffer.count - 4 >= length else { break }
            let payload = buffer.subdata(in: 4..<(4 + length))
            buffer.removeSubrange(0..<(4 + length))
            payloads.append(payload)
        }
        return payloads
    }
}

/// Blocking stdio helper for worker processes. Writes are serialized with a
/// lock because the heartbeat thread and the scenario loop write
/// concurrently.
public struct WorkerPipe {
    private let input: FileHandle
    private let output: FileHandle
    private let writeLock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        self.input = input
        self.output = output
    }

    /// Blocking read of one message; nil on EOF.
    public func readMessage() throws -> WireMessage? {
        let lengthData: Data? = try readExact(4)
        guard let lengthData else { return nil }
        let length = lengthData.reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0, length < 64 * 1024 * 1024 else {
            throw NSError(domain: "WorkerPipe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "invalid frame length \(length)"])
        }
        let payload = try readExact(length)
        return try payload.map { try decoder.decode(WireMessage.self, from: $0) }
    }

    public func write(_ message: WireMessage) throws {
        let payload = try encoder.encode(message)
        var frame = Data(capacity: 4 + payload.count)
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(payload)
        writeLock.lock()
        defer { writeLock.unlock() }
        try output.write(contentsOf: frame)
    }

    private func readExact(_ count: Int) throws -> Data? {
        var data = Data(capacity: count)
        while data.count < count {
            guard let chunk = try input.read(upToCount: count - data.count), !chunk.isEmpty else {
                return data.isEmpty ? nil : data
            }
            data.append(chunk)
        }
        return data
    }
}
