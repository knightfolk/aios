import Foundation
import AIOSCore
import EventJournal

/// Host-side session with one worker process. Owns process lifecycle, the
/// framed stdio protocol, heartbeat monitoring, and crash detection. Crashes
/// are journaled; the host (this session's owner) always survives them.
public actor WorkerSession {
    public enum Event: Sendable, Equatable {
        case started(workerID: String, runtime: RuntimeKind)
        case actionRequest(ActionRequest)
        case workResult(WorkResult)
        case executionFinished(ShellExecutionResult)
        case log(String)
        case heartbeatReceived(workerID: String)
        case hungDetected(workerID: String)
        case crashed(workerID: String)
        case shutDown
    }

    public enum SessionError: Error, Equatable {
        case protocolVersionMismatch(host: UInt, worker: UInt)
        case handshakeTimedOut
        case notRunning
    }

    public struct Configuration: Sendable {
        public var executableURL: URL
        public var arguments: [String]
        public var heartbeatTimeoutSeconds: TimeInterval
        public var handshakeTimeoutSeconds: TimeInterval
        public var protocolVersion: UInt

        public init(
            executableURL: URL,
            arguments: [String] = [],
            heartbeatTimeoutSeconds: TimeInterval = 30,
            handshakeTimeoutSeconds: TimeInterval = 10,
            protocolVersion: UInt = 1
        ) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.heartbeatTimeoutSeconds = heartbeatTimeoutSeconds
            self.handshakeTimeoutSeconds = handshakeTimeoutSeconds
            self.protocolVersion = protocolVersion
        }
    }

    private let configuration: Configuration
    private let journal: JournalStore?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// A crashed worker leaves a broken pipe behind; writes must surface as
    /// errors, not kill the host via SIGPIPE.
    private static let ignoreSIGPIPE: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    private var process: Process?
    private var writer: FileHandle?
    private var framer = StreamFramer()
    private var readerTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?

    private var history: [Event] = []
    private var started = false
    private var intentionalShutdown = false
    private var hangReported = false
    private var lastHeartbeatAt: Date?
    private var workerID: String = "unknown"
    private(set) public var lastWorkPackage: WorkPackage?

    public init(configuration: Configuration, journal: JournalStore? = nil) {
        Self.ignoreSIGPIPE
        self.configuration = configuration
        self.journal = journal
    }

    public func start() async throws {
        guard process == nil else { return }

        let process = Process()
        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        self.process = process
        self.writer = stdinPipe.fileHandleForWriting

        process.terminationHandler = { [weak self] terminated in
            let exitCode = terminated.terminationStatus
            Task { await self?.noteTermination(exitCode: exitCode) }
        }

        try process.run()

        let stdoutHandle = stdoutPipe.fileHandleForReading
        readerTask = Task {
            do {
                for try await byte in stdoutHandle.bytes {
                    await self.consume(Data([byte]))
                }
            } catch {
                await self.emit(.log("stdout reader error: \(error)"))
            }
            await self.noteStreamEnd()
        }

        monitorTask = Task {
            await self.monitorHeartbeats()
        }

        try send(.helloRequest(HelloRequest(protocolVersion: configuration.protocolVersion)))

        let first = try await waitFor(
            { if case .started = $0 { true } else { false } },
            timeout: configuration.handshakeTimeoutSeconds
        )
        guard case .started = first else { throw SessionError.handshakeTimedOut }
    }

    // MARK: - Outbound

    public func send(_ message: WireMessage) throws {
        guard let writer else { throw SessionError.notRunning }
        let payload = try encoder.encode(message)
        var frame = Data(capacity: 4 + payload.count)
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(payload)
        try writer.write(contentsOf: frame)
    }

    public func sendWorkPackage(_ package: WorkPackage) async throws {
        lastWorkPackage = package
        try send(.workPackage(package))
    }

    public func sendActionResult(_ result: ActionResult) async throws {
        try send(.actionResult(result))
    }

    public func terminate() async {
        intentionalShutdown = true
        readerTask?.cancel()
        monitorTask?.cancel()
        try? send(.shutdown)
        _ = process?.waitUntilExit()
        emit(.shutDown)
    }

    /// Hard-kills the worker (test harness / emergency path).
    public func killForTesting() {
        guard let process, process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
    }

    // MARK: - Event access for hosts and tests

    public func eventHistory() -> [Event] { history }

    /// Waits (polling) for the first event matching the predicate. Events are
    /// never consumed — history is append-only, so multiple waiters can scan.
    public func waitFor(
        _ match: @Sendable (Event) -> Bool,
        timeout: TimeInterval
    ) async throws -> Event {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let event = history.last(where: match) {
                return event
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw TimeoutError()
    }

    public struct TimeoutError: Error, CustomStringConvertible {
        public var description: String { "timed out waiting for worker event" }
    }

    // MARK: - Internals

    private func consume(_ data: Data) {
        for payload in framer.append(data) {
            guard let message = try? decoder.decode(WireMessage.self, from: payload) else {
                emit(.log("undecodable frame (\(payload.count) bytes)"))
                continue
            }
            handle(message)
        }
    }

    private func handle(_ message: WireMessage) {
        switch message {
        case .helloRequest:
            break // host never receives this
        case .helloResponse(let response):
            guard response.protocolVersion == configuration.protocolVersion else {
                emit(.log("protocol mismatch host=\(configuration.protocolVersion) worker=\(response.protocolVersion)"))
                Task { await self.shutdownAfterError() }
                return
            }
            workerID = response.workerID
            started = true
            lastHeartbeatAt = Date()
            emit(.started(workerID: response.workerID, runtime: response.runtime))
        case .workPackage:
            break
        case .actionRequest(let request):
            emit(.actionRequest(request))
        case .actionResult:
            break
        case .workResult(let result):
            emit(.workResult(result))
        case .heartbeat(let beat):
            lastHeartbeatAt = beat.at
            emit(.heartbeatReceived(workerID: beat.workerID))
        case .log(let text):
            emit(.log(text))
        case .cancel, .shutdown, .execute:
            break
        case .executionFinished(let result):
            emit(.executionFinished(result))
        }
    }

    private func monitorHeartbeats() async {
        while !Task.isCancelled {
            if started, !hangReported, !intentionalShutdown,
               let last = lastHeartbeatAt,
               Date().timeIntervalSince(last) > configuration.heartbeatTimeoutSeconds {
                hangReported = true
                emit(.hungDetected(workerID: workerID))
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func noteTermination(exitCode: Int32) {
        guard !intentionalShutdown, started || exitCode != 0 else { return }
        emit(.crashed(workerID: workerID))
        if let journal, let attemptID = lastWorkPackage?.attemptID {
            Task {
                try? await journal.append(.workerCrashed(.init(workerID: workerID, attemptID: attemptID)))
            }
        }
    }

    private func noteStreamEnd() {
        guard !intentionalShutdown, started else { return }
        // Stream ended without an intentional shutdown: treat like a crash;
        // termination handler usually also fires, history dedupes logically.
        if !history.contains(where: { if case .crashed = $0 { true } else { false } }) {
            emit(.crashed(workerID: workerID))
        }
    }

    private func shutdownAfterError() async {
        intentionalShutdown = true
        readerTask?.cancel()
        monitorTask?.cancel()
        killForTesting()
    }

    private func emit(_ event: Event) {
        history.append(event)
    }
}
