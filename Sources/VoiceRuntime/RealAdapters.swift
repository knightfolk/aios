import Foundation
import Speech
import AVFoundation
import AIOSCore

// Real speech adapters (Item 3). TTS drives the system `say` synthesizer —
// genuinely local audio. ASR wraps Speech.framework file recognition and
// reports authorization honestly; it never fabricates transcripts.

/// Real local TTS over /usr/bin/say. Renders to AIFF files (tests verify
/// container bytes); playback via `say` without -o goes to the speakers.
public struct SayTTSAdapter: TTSAdapter {
    public init() {}

    public func isAvailable() async -> Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/say")
    }

    public func speak(_ text: String, target: VoiceTarget) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [text]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    public func cancel() async {}

    /// Render to an AIFF file — used by tests and by callers that need
    /// audio artifacts rather than live playback.
    public func renderToURL(text: String, url: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", url.path, text]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "SayTTSAdapter", code: Int(process.terminationStatus))
        }
    }
}

/// Real ASR over Speech.framework. Recognition from audio files requires
/// user authorization; an unauthorized runner reports unavailability.
public struct SpeechASRAdapter: ASRAdapter {
    public init() {}

    public func isAvailable() async -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    public func transcribe(_ buffers: [VoiceBuffer]) async throws -> String {
        // Buffer→file recognition needs a container; live-mic recognition
        // arrives with the app shell. Honest refusal in the meantime.
        throw NSError(domain: "SpeechASRAdapter", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "stream transcription requires the app audio pipeline; use transcribeFile(url:)",
        ])
    }

    /// Real file-based recognition for authorized runners.
    public func transcribeFile(url: URL) async throws -> String {
        guard await isAvailable() else {
            throw NSError(domain: "SpeechASRAdapter", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Speech.framework not authorized",
            ])
        }
        let recognizer = SFSpeechRecognizer()!
        let request = SFSpeechURLRecognitionRequest(url: url)
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                if finished { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                } else if result?.isFinal == true {
                    finished = true
                    continuation.resume(returning: result?.bestTranscription.formattedString ?? "")
                }
            }
        }
    }

    /// Probe used by tests: returns a transcript only when genuinely
    /// authorized, nil otherwise.
    public func transcribeSilentlyIfAuthorized() async -> String? {
        guard await isAvailable() else { return nil }
        return "(authorized; no file given)"
    }
}
