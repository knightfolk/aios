import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import ExecutionFabric
@testable import DesktopShell

// Step 4: Expert Cards converse over a REAL worker session. The transcript
// is view-model state fed by session events; the brain's output stays
// generatedContent; completion claims never auto-promote.

private func workerBinary() throws -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = packageRoot.appendingPathComponent(".build/debug/InferenceWorker")
    #expect(FileManager.default.fileExists(atPath: url.path), "missing worker binary: \(url.path)")
    return url
}

@MainActor @Test func expertChatTranscriptReflectsSessionEvents() async throws {
    await TestEnvGate.lock()
    defer { TestEnvGate.unlock() }
    TestEnvGate.set("AIOS_FAKE_LLM", "1")
    TestEnvGate.set("AIOS_FAKE_LLM_ACTIONS", nil)
    TestEnvGate.set("AIOS_ECHO_ACTION_TARGET", nil)

    let chat = ExpertChatModel(expertRole: .linus)
    try await chat.startConsultation(workerURL: try workerBinary())

    let result = try await chat.send(userText: "what should we do about the flaky timer test?")
    #expect(result.status == .completed)
    #expect(chat.transcript.count == 4) // system-start, user, assistant, turn-ended
    #expect(chat.transcript.first { $0.role == .assistant }?.text.isEmpty == false)
    // Honest identity: the echo brain reports scripted, never mlx.
    #expect(chat.lastWorkerRuntime == .scripted)
    #expect(chat.transcript.allSatisfy { !$0.text.isEmpty })

    await chat.end()
}

@MainActor @Test func expertChatRequiresStartBeforeSend() async throws {
    let chat = ExpertChatModel(expertRole: .sherlock)
    do {
        _ = try await chat.send(userText: "hello?")
        Issue.record("send before start must throw")
    } catch {
        // expected
    }
}
