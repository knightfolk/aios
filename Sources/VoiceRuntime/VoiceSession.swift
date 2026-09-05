import Foundation
import AIOSCore

// Voice runtime (docs 08/Phase 5): native audio pipeline with injectable
// ASR/TTS adapters, energy-based barge-in, explicit target selection, and
// pause / stop-speaking / stop as distinct semantics. Adapters are honest:
// the echo pair is a declared test double; real model adapters land with
// their runtimes and are never silently substituted.

public struct VoiceBuffer: Sendable, Equatable {
    public var samples: [Float]
    public var at: TimeInterval

    public init(samples: [Float], at: TimeInterval) {
        self.samples = samples
        self.at = at
    }
}

/// Where a spoken/heard utterance is routed — explicit, never guessed.
public enum VoiceTarget: Sendable, Equatable, Hashable {
    case concierge
    case project(String)
}

public protocol ASRAdapter: Sendable {
    func transcribe(_ buffers: [VoiceBuffer]) async throws -> String
}

public protocol TTSAdapter: Sendable {
    func speak(_ text: String, target: VoiceTarget) async throws
    func cancel() async
}

/// Declared offline ASR double: returns a fixed marker so tests exercise
/// routing and state, never real transcription.
public struct EchoASRAdapter: ASRAdapter {
    public init() {}

    public func transcribe(_ buffers: [VoiceBuffer]) async throws -> String {
        "(echo transcript of \(buffers.count) buffers)"
    }
}

/// Declared offline TTS double.
public struct EchoTTSAdapter: TTSAdapter {
    public init() {}

    public func speak(_ text: String, target: VoiceTarget) async throws {}

    public func cancel() async {}
}

public struct RoutedUtterance: Sendable, Equatable {
    public var target: VoiceTarget
    public var transcript: String

    public init(target: VoiceTarget, transcript: String) {
        self.target = target
        self.transcript = transcript
    }
}

public enum VoiceSessionState: String, Sendable, Equatable {
    case idle
    case listening
    case speaking
    case paused
}

public actor VoiceSession {
    private let asr: any ASRAdapter
    private let tts: any TTSAdapter
    private var currentState: VoiceSessionState = .idle
    private var currentTarget: VoiceTarget = .concierge
    private var _lastSpokenText: String?

    /// Energy threshold (RMS) above which live mic input barges in on
    /// playback. Tunable; the default favors user voices over room noise.
    public var bargeInRMS: Float = 0.25

    public init(asr: any ASRAdapter, tts: any TTSAdapter) {
        self.asr = asr
        self.tts = tts
    }

    public var state: VoiceSessionState { currentState }
    public var lastSpokenText: String? { _lastSpokenText }

    public func speak(text: String, target: VoiceTarget) async throws {
        currentTarget = target
        currentState = .speaking
        _lastSpokenText = text
        try await tts.speak(text, target: target)
    }

    /// Distinct from pause and from Emergency Stop: halts output, session
    /// stays alive (docs 08).
    public func stopSpeaking() async {
        await tts.cancel()
        currentState = .idle
    }

    public func beginListening(target: VoiceTarget) async throws {
        currentTarget = target
        currentState = .listening
    }

    public func pause() {
        guard currentState == .listening else { return }
        currentState = .paused
    }

    public func resume() throws {
        guard currentState == .paused else { return }
        currentState = .listening
    }

    public func stop() async {
        await tts.cancel()
        currentState = .idle
    }

    /// End-to-end: buffers → transcript routed to the explicit target.
    public func utterance(fromBuffers buffers: [VoiceBuffer], target: VoiceTarget) async throws -> RoutedUtterance {
        currentTarget = target
        currentState = .listening
        let transcript = try await asr.transcribe(buffers)
        currentState = .idle
        return RoutedUtterance(target: target, transcript: transcript)
    }

    /// Barge-in: while speaking, loud input cancels playback and the user
    /// takes the floor. Quiet input changes nothing.
    public func processBargeInBuffer(_ buffer: VoiceBuffer) async {
        guard currentState == .speaking else { return }
        let rms = Self.rootMeanSquare(buffer.samples)
        guard rms >= bargeInRMS else { return }
        await tts.cancel()
        currentState = .listening
    }

    static func rootMeanSquare(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }
}
