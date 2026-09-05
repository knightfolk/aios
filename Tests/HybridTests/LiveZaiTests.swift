import Foundation
import Testing
@testable import AIOSCore
@testable import SecurityKernel
@testable import ModelRuntime
@testable import CloudRuntime

// Opt-in live gate: one real, bounded Z.ai completion. Skipped unless
// AIOS_LIVE_ZAI=1. The key comes ONLY from the environment or the local
// Keychain (CredentialBroker) — never from source.

private func liveKey() -> String? {
    if let fromEnv = ProcessInfo.processInfo.environment["AIOS_ZAI_KEY"], !fromEnv.isEmpty {
        return fromEnv
    }
    return CredentialBroker().providerKey("zai")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AIOS_LIVE_ZAI"] == "1"))
func liveZaiCompletion() async throws {
    let key = try #require(liveKey(), "set AIOS_ZAI_KEY or run: swift run ProviderSetup zai")
    let profile = try ProviderProfile.loadBundled(providerID: "zai")
    let client = ZaiClient(profile: profile, key: key)

    let result = await client.complete(GenerationRequest(
        messages: [
            ChatMessage(role: .system, content: "Answer with a single word."),
            ChatMessage(role: .user, content: "What is the capital of France?"),
        ],
        maxTokens: 16,
        temperature: 0,
        harnessProfileID: "default-v1"
    ))

    #expect(result.outcome == .succeeded, "detail: \(result.detail ?? "")")
    #expect(!result.text.isEmpty)
    // Token counts are reported honestly when the provider sends usage.
    print("live zai: tokens prompt=\(result.promptTokens) completion=\(result.completionTokens) latency=\(result.latencyMs)ms text=\(result.text.prefix(60))")
}
