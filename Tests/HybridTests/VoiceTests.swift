import Foundation
import Testing
@testable import AIOSCore
@testable import VoiceRuntime

@Test func voiceSessionPauseStopSpeakingAreDistinct() async throws {
    let session = VoiceSession(asr: EchoASRAdapter(), tts: EchoTTSAdapter())

    #expect(await session.state == .idle)

    // Start speaking a phrase.
    try await session.speak(text: "working on it", target: .concierge)
    #expect(await session.state == .speaking)

    // "Stop speaking" halts output but keeps the session alive.
    await session.stopSpeaking()
    #expect(await session.state == .idle)
    #expect(await session.lastSpokenText == "working on it")

    // Pause: mid-conversation hold; resume continues.
    try await session.beginListening(target: .project("p1"))
    await session.pause()
    #expect(await session.state == .paused)
    try await session.resume()
    #expect(await session.state == .listening)

    // Stop: full teardown of the turn.
    await session.stop()
    #expect(await session.state == .idle)
}

@Test func explicitTargetSelectionRoutesTranscript() async throws {
    let session = VoiceSession(asr: EchoASRAdapter(), tts: EchoTTSAdapter())
    let routed = try await session.utterance(fromBuffers: [VoiceBuffer(samples: [0.1, 0.2], at: 0)], target: .project("p1"))
    #expect(routed.target == .project("p1"))
    #expect(!routed.transcript.isEmpty)
}

@Test func bargeInCancelsPlaybackWhenEnergySpikes() async throws {
    let tts = RecordingTTS()
    let session = VoiceSession(asr: EchoASRAdapter(), tts: tts)

    try await session.speak(text: "long phrase", target: .concierge)
    #expect(await session.state == .speaking)
    #expect(tts.started)

    // Loud mic energy while speaking → barge-in: playback cancels.
    await session.processBargeInBuffer(VoiceBuffer(samples: [0.9, 0.95, 0.9], at: 1))
    #expect(tts.cancelled)
    #expect(await session.state == .listening) // user took the floor

    // Quiet noise must NOT barge in.
    try await session.speak(text: "again", target: .concierge)
    await session.processBargeInBuffer(VoiceBuffer(samples: [0.01, 0.02], at: 2))
    #expect(await session.state == .speaking)
}

@Test func pipelineLatencyStaysBoundedUnderSyntheticLoad() async throws {
    // SLO probe with synthetic buffers (docs 10: establish targets by
    // measurement, not invention): end-to-end utterance latency while a
    // CPU-burn task saturates cores.
    let session = VoiceSession(asr: EchoASRAdapter(), tts: EchoTTSAdapter())
    let burn = Task<Void, Never> { while !Task.isCancelled {} }
    defer { burn.cancel() }

    let started = Date()
    _ = try await session.utterance(fromBuffers: (0..<32).map { VoiceBuffer(samples: [0.05], at: Double($0)) }, target: .concierge)
    let latency = Date().timeIntervalSince(started)
    #expect(latency < 2.0, "utterance latency \(latency)s exceeds the 2s probe bound")
}

// MARK: - Test doubles

final class RecordingTTS: TTSAdapter, @unchecked Sendable {
    var started = false
    var cancelled = false
    func speak(_ text: String, target: VoiceTarget) async throws {
        started = true
        cancelled = false
    }
    func cancel() async { cancelled = true }
}
