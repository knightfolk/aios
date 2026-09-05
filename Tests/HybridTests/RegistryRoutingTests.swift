import Foundation
import Testing
@testable import AIOSCore
@testable import ModelRuntime
@testable import Router

private func manifest() -> ModelManifest {
    ModelManifest(
        modelID: "qwen25-7b-instruct-4bit", family: "qwen2.5", revision: "1",
        quantization: "4bit",
        sourceURL: "https://huggingface.co/mlx-community/Qwen2.5-7B-Instruct-4bit",
        files: [ModelFile(filename: "model.safetensors", sha256: String(repeating: "a", count: 64))],
        license: "apache-2.0", modalities: ["text"], contextWindowTokens: 32_768,
        estimatedMemoryGB: 5.4, supportedRuntimes: [.mlx],
        recommendedRoles: ["linus"], knownLimitations: [], requiresRemoteCode: false
    )
}

@Test func localOnlyExcludesCloudEvenWhenConfigured() {
    let registry = RuntimeRegistry(mlxManifest: manifest(), cloudConfigured: true)
    let available = registry.availableRuntimes(
        policy: .localOnly,
        budget: SpendPolicy(maxSpendUSD: 100, allowPaidCredits: true)
    )
    #expect(!available.contains(.cloudAPI))
    #expect(available.contains(.mlx))
    #expect(available.contains(.scripted))
}

@Test func zeroBudgetExcludesCloud() {
    let registry = RuntimeRegistry(mlxManifest: nil, cloudConfigured: true)
    let available = registry.availableRuntimes(
        policy: .hybridAllowed,
        budget: SpendPolicy(maxSpendUSD: 0, allowPaidCredits: false)
    )
    #expect(!available.contains(.cloudAPI))
    #expect(available == [.scripted])
}

@Test func hybridPolicyWithBudgetAllowsCloud() {
    let registry = RuntimeRuntimeCaseHelper.cloudConfigured()
    let available = registry.availableRuntimes(
        policy: .hybridAllowed,
        budget: SpendPolicy(maxSpendUSD: 5, allowPaidCredits: false)
    )
    #expect(available.contains(.cloudAPI))
}

@Test func routerPicksMLXWhenResidentAndExplainsWhy() {
    let router = Router()
    let decision = router.decide(
        capabilities: [.modifyWorkspace],
        privacyPolicy: .localOnly,
        spendPolicy: SpendPolicy(),
        registry: RuntimeRegistry(mlxManifest: manifest(), cloudConfigured: false)
    )
    #expect(decision.runtime == .mlx)
    #expect(decision.rationale.contains { $0.contains("resident") })

    let without = router.decide(
        capabilities: [.modifyWorkspace],
        privacyPolicy: .localOnly,
        spendPolicy: SpendPolicy(),
        registry: RuntimeRegistry(mlxManifest: nil, cloudConfigured: false)
    )
    #expect(without.runtime == .scripted)
    #expect(without.rationale.contains { $0.contains("scripted") })
}

private enum RuntimeRuntimeCaseHelper {
    static func cloudConfigured() -> RuntimeRegistry {
        RuntimeRegistry(mlxManifest: nil, cloudConfigured: true)
    }
}
