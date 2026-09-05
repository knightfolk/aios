import Foundation
import Testing
@testable import AIOSCore
@testable import VoiceRuntime
@testable import MediaRuntime

@Test(.enabled(if: ProcessInfo.processInfo.environment["AIOS_LIVE_TTS"] == "1"))
func sayAdapterSynthesizesRealAudio() async throws {
    let adapter = SayTTSAdapter()
    guard await adapter.isAvailable() else {
        Issue.record("/usr/bin/say unavailable on this machine")
        return
    }
    let out = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-say-\(UUID().uuidString).aiff")
    defer { try? FileManager.default.removeItem(at: out) }

    try await adapter.renderToURL(text: "testing one two three", url: out)
    let data = try Data(contentsOf: out)
    #expect(data.prefix(4) == Data("FORM".utf8)) // AIFF container magic
    #expect(data.count > 1000) // real audio, not an empty container
}

@Test func speechASRAdapterReportsAuthorizationRequirement() async {
    let adapter = SpeechASRAdapter()
    // Availability reflects real Speech.framework state; on an
    // unauthorized headless runner it must say so, never fake a transcript.
    let available = await adapter.isAvailable()
    _ = available
    let result = await adapter.transcribeSilentlyIfAuthorized()
    if !available {
        #expect(result == nil)
    }
}

@Test func cogviewAdapterIsRealOrHonestlyUnavailable() async throws {
    let adapter = try await CogImageViewAdapter()
    if await adapter.isAvailable() {
        let job = MediaJob(jobID: "cog-1", kind: .image, prompt: "a red circle on white", seed: 3)
        let media = try await adapter.render(job)
        #expect(media.data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        #expect(media.provenance.contains("cogview"))
    } else {
        #expect(adapter.unavailabilityReason?.contains("cogview") == true)
    }
}
