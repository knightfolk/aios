import Foundation
import AIOSCore
import ExecutionFabric

// ToolWorker — the Hand-side executor. It only runs shell commands the host
// broker has already authorized; it never decides policy and never receives
// credentials.

let pipe = WorkerPipe()
let workerID = "tool-\(ProcessInfo.processInfo.processIdentifier)"

// Heartbeats keep the host's hung-worker watchdog honest.
let heartbeatThread = Thread {
    while true {
        Thread.sleep(forTimeInterval: 5)
        try? pipe.write(.heartbeat(Heartbeat(workerID: workerID)))
    }
}
heartbeatThread.start()

outer: while let inbound = (try? pipe.readMessage()).flatMap({ $0 }) {
    switch inbound {
    case .helloRequest(let hello):
        try? pipe.write(.helloResponse(HelloResponse(
            protocolVersion: hello.protocolVersion,
            workerID: workerID,
            runtime: .deterministic
        )))

    case .execute(let request):
        let result = execute(request)
        _ = try? pipe.write(.executionFinished(result))

    case .shutdown:
        break outer

    default:
        break
    }
}

exit(0)

func execute(_ request: ShellExecutionRequest) -> ShellExecutionResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: request.command)
    process.arguments = request.arguments
    process.currentDirectoryURL = URL(fileURLWithPath: request.cwd)
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
        try process.run()
    } catch {
        return ShellExecutionResult(
            executionID: request.executionID,
            exitCode: 127,
            stdout: "",
            stderr: "failed to launch \(request.command): \(error)",
            timedOut: false
        )
    }

    let timeoutDeadline = Date().addingTimeInterval(request.timeoutSeconds)
    var timedOut = false
    while process.isRunning && Date() < timeoutDeadline {
        Thread.sleep(forTimeInterval: 0.01)
    }
    if process.isRunning {
        timedOut = true
        process.terminate()
        Thread.sleep(forTimeInterval: 0.1)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return ShellExecutionResult(
        executionID: request.executionID,
        exitCode: process.terminationStatus,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? "",
        timedOut: timedOut
    )
}
