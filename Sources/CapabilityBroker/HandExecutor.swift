import Foundation
import AIOSCore
import ExecutionFabric

public enum HandError: Error, Sendable {
    /// The Hand could not confirm whether the effect happened (process died
    /// mid-operation, connection lost, ...). The outcome must stay UNKNOWN
    /// until reconciled.
    case uncertainOutcome(String)
}

/// The actual Hands: everything that changes or observes reality. The broker
/// is the only caller; Brains never touch these directly.
public protocol HandExecutor: Sendable {
    func readFile(at path: String) throws -> Data
    func writeFile(at path: String, contents: Data) throws
    func runCommand(cwd: String, command: String, arguments: [String], timeout: Double) async -> ShellExecutionResult
}

/// Local, in-process implementation over FileManager and Process. Open for
/// subclassing so tests can inject uncertainty.
open class LocalHandExecutor: HandExecutor, @unchecked Sendable {
    public init() {}

    open func readFile(at path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    open func writeFile(at path: String, contents: Data) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, options: .atomic)
    }

    open func runCommand(cwd: String, command: String, arguments: [String], timeout: Double) async -> ShellExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ShellExecutionResult(executionID: UUID().uuidString, exitCode: 127, stdout: "", stderr: "\(error)", timedOut: false)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        var timedOut = false
        if process.isRunning {
            timedOut = true
            process.terminate()
            try? await Task.sleep(for: .milliseconds(100))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        return ShellExecutionResult(
            executionID: UUID().uuidString,
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            timedOut: timedOut
        )
    }
}
