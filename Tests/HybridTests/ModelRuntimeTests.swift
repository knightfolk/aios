import Foundation
import Testing
@testable import AIOSCore
@testable import ModelRuntime

// MARK: - Manifest round-trip + golden registry

@Test func modelManifestRoundTrips() throws {
    let manifest = ModelManifest(
        modelID: "qwen25-7b-instruct-4bit",
        family: "qwen2.5",
        revision: "1",
        quantization: "4bit",
        sourceURL: "https://huggingface.co/mlx-community/Qwen2.5-7B-Instruct-4bit",
        files: [ModelFile(filename: "model.safetensors", sha256: String(repeating: "a", count: 64))],
        license: "apache-2.0",
        modalities: ["text"],
        contextWindowTokens: 32_768,
        estimatedMemoryGB: 5.2,
        supportedRuntimes: [.mlx],
        recommendedRoles: ["linus", "sherlock"],
        knownLimitations: ["no vision"],
        requiresRemoteCode: false,
        evaluationRef: nil
    )
    let decoded = try roundTrip(manifest)
    #expect(decoded == manifest)
}

@Test func defaultModelsRegistryDecodes() throws {
    let url = Bundle.module.url(forResource: "default-models", withExtension: "json")
    let loaded = try #require(url)
    let registry = try JSONDecoder().decode(ModelRegistry.self, from: Data(contentsOf: loaded))
    #expect(!registry.models.isEmpty)
    let first = registry.models[0]
    #expect(!first.files.isEmpty)
    #expect(first.files.allSatisfy { $0.isVerifiable })
    #expect(first.files.contains { ($0.sha256?.count ?? 0) == 64 }) // weights pinned by SHA-256
    #expect(first.estimatedMemoryGB < 8)
    #expect(first.supportedRuntimes == [.mlx])
}

// MARK: - Provider profile + quota math

@Test func providerProfileQuotaMath() throws {
    let profile = ProviderProfile(
        providerID: "zai",
        endpoint: "https://api.example/v4/",
        protocolKind: .openAICompatible,
        models: [ProviderModel(modelID: "glm-4.7-flash", modalities: ["text"], contextWindowTokens: 128_000)],
        billingMode: .payAsYouGo,
        quotaWindows: [QuotaWindow(windowSeconds: 3600, tokenLimit: 100_000, paidOverflowAllowed: false)],
        rateLimitRPM: 60,
        privacyNotes: "test",
        lastVerifiedAt: Date(timeIntervalSinceReferenceDate: 0)
    )
    let decoded = try roundTrip(profile)
    #expect(decoded == profile)

    #expect(profile.tokensRemaining(usedTokensInWindow: 90_000) == 10_000)
    #expect(profile.tokensRemaining(usedTokensInWindow: 150_000) == 0)
    #expect(!profile.allowsOverflow)
}

// MARK: - Generation contracts

@Test func generationContractsRoundTrip() throws {
    let request = GenerationRequest(
        messages: [ChatMessage(role: .system, content: "be terse"), ChatMessage(role: .user, content: "hello")],
        maxTokens: 64,
        temperature: 0,
        harnessProfileID: "default-v1"
    )
    #expect(try roundTrip(request) == request)

    let chunk = GenerationChunk(text: "hi")
    #expect(try roundTrip(chunk) == chunk)

    let result = GenerationResult(
        text: "hi there",
        promptTokens: 10,
        completionTokens: 3,
        latencyMs: 120,
        outcome: .succeeded,
        detail: nil
    )
    #expect(try roundTrip(result) == result)
    #expect(GenerationResult(text: "", promptTokens: 0, completionTokens: 0, latencyMs: 0, outcome: .notConfigured, detail: "no key").outcome == .notConfigured)
}

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}
