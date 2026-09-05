# Phase 2 — Hybrid Intelligence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Phase 2 per `docs/superpowers/specs/2026-09-04-phase2-hybrid-intelligence-design.md`: a local MLX runtime (~8B 4-bit), one validated cloud connector (Z.ai, OpenAI-compatible), provider/harness/model manifests, quota + budget enforcement, and graceful checkpoint fallback — on top of the unchanged Phase 0/1 engine.

**Architecture:** Three runtimes (`scripted`, `mlx`, `cloudAPI`) behind one typed interface, selected by the Router via a `RuntimeRegistry`. New libraries `ModelRuntime` (pure types), `MLXRuntime` (mlx-swift adapter + model store/fetch — the only target linking mlx), `CloudRuntime` (Z.ai client). Credentials live only in the environment or Keychain via a `CredentialBroker`; never in source, examples, tests, journal, logs, or worker env. No new journal event kinds; selection journals via existing `ModelSelected`, provenance via `WorkResult.worker`.

**Tech Stack:** Swift 6 / SwiftPM, mlx-swift + mlx-swift-examples (`MLXLMCommon`), URLSession + SSE, Security framework Keychain, Swift Testing.

## Global Constraints

- Default `swift test` stays offline and fast; live paths gated behind `AIOS_LIVE_MLX=1` and `AIOS_LIVE_ZAI=1` (skip, not fail, when unset).
- Credentials: read only from environment variables or Keychain (`CredentialBroker`); no usable literal in any source, example, or test (Mimosa constraint).
- Cloud is structurally unreachable under `PrivacyPolicy.localOnly` or zero budget — existing Phase 1 router tests must keep passing unchanged.
- Subscription allowance never silently overflows into paid credits; refusals land in Needs You.
- Fallback only at attempt/checkpoint boundaries; every switch journals `ModelSelected` and carries a `Handoff`.
- Local-model output claims are typed `generatedContent`; no tool-calling from brains in this phase; no auto-promotion to fact.
- Model weights verified by SHA-256 before a model is resident; partial/mismatched downloads are never marked resident.
- mlx-swift is pinned and isolated to `MLXRuntime`.

---

### Task 0: Branch, targets, dependencies

**Files:** Modify `Package.swift`; create empty sources for new targets.

- [ ] `git switch -c phase2-hybrid-intelligence` from `main`.
- [ ] Add library targets `ModelRuntime` (deps: AIOSCore), `MLXRuntime` (deps: AIOSCore, ModelRuntime, `MLXLMCommon` from `mlx-swift-examples` pinned), `CloudRuntime` (deps: AIOSCore, ModelRuntime, SecurityKernel). Add executables `ModelFetch` (deps: MLXRuntime), `ProviderSetup` (deps: SecurityKernel, ModelRuntime, CloudRuntime).
- [ ] Wire test-target deps: `KernelTests` += ModelRuntime, CloudRuntime; new `HybridTests` target (deps: all new libs + ExecutionFabric + Supervisor + Router).
- [ ] `swift build` green; commit.

### Task 1: ModelRuntime core types

**Files:** Create `Sources/ModelRuntime/Manifests.swift`, `Sources/ModelRuntime/Generation.swift`, `Sources/ModelRuntime/Resources/default-models.json`. Test: `Tests/HybridTests/ModelRuntimeTests.swift`.

**Produces:** `ModelManifest` (fields: `modelID, family, revision, quantization, sourceURL, sourceSHA256, license, modalities: [String], contextWindowTokens, estimatedMemoryGB, supportedRuntimes: [RuntimeKind], recommendedRoles: [String], knownLimitations: [String], requiresRemoteCode: Bool, evaluationRef: String?` + `schemaVersion`); `ProviderProfile` (fields: `providerID, endpoint, protocolKind: ProviderProtocol (.openAICompatible), models: [ProviderModel{modelID, modalities, contextWindowTokens}], billingMode: BillingMode (.subscription/.credits/.payAsYouGo), quotaWindows: [QuotaWindow{windowSeconds, tokenLimit, paidOverflowAllowed}], rateLimitRPM, privacyNotes, lastVerifiedAt`); `GenerationRequest {messages: [ChatMessage{role: ChatRole, content: String}], maxTokens, temperature, harnessProfileID}`; `GenerationChunk {text}`; `GenerationResult {text, promptTokens, completionTokens, latencyMs, outcome: GenerationOutcome (.succeeded/.failed/.refused/.notConfigured), detail}`.

- [ ] Failing tests: Codable round-trip each type; golden JSON decode of `default-models.json` (one ~8B 4-bit mlx-community manifest, exact fields); quota-window math on `ProviderProfile.tokensRemaining(in:used:)`.
- [ ] Implement; tests pass; commit.

### Task 2: Wire generation messages

**Files:** Modify `Sources/ExecutionFabric/WireProtocol.swift`. Test: `Tests/KernelTests/WireGenerationRoundTripTests.swift`.

- [ ] Failing tests: `WireMessage.generationRequest/.generationChunk/.generationDone` encode→decode round-trip equals original.
- [ ] Add cases; tests pass; commit.

### Task 3: HarnessProfile store

**Files:** Create `Sources/ModelRuntime/HarnessProfile.swift` + `Resources/HarnessProfiles/default-v1.json`. Test: `Tests/HybridTests/HarnessProfileTests.swift`.

**Produces:** `HarnessProfile {profileID, schemaVersion, systemPrompt, outputContractJSON: String, reasoningMode: String, contextMaintenance: String, preferredTopologies: [ExecutionTopology], retryRules: [String], failureSignatures: [String], evaluatorCompatibility: String}`; `HarnessProfileStore.load(profileID) -> HarnessProfile` (bundled defaults; `~/Library/Application Support/AIOS/harness/<id>.json` overrides; root injectable for tests).

- [ ] Failing tests: bundled default loads; override dir wins; missing override falls back to bundled.
- [ ] Implement; tests pass; commit.

### Task 4: RuntimeRegistry + Router

**Files:** Create `Sources/ModelRuntime/RuntimeRegistry.swift`; modify `Sources/Router/Router.swift`. Test: `Tests/HybridTests/RegistryRoutingTests.swift`.

**Produces:** `RuntimeRegistry {scriptedAvailable: Bool = true, mlxManifest: ModelManifest?, cloudConfigured: Bool}` with `availableRuntimes(policy:, budget:) -> [RuntimeKind]`; `Router.decide(capabilities:privacyPolicy:spendPolicy:registry:)` returns `RoutingDecision` (existing type) whose rationale names the registry state. Existing `decide(capabilities:privacyPolicy:spendPolicy:localRuntimeAvailable:)` signature stays (delegates with a registry).

- [ ] Failing tests: localOnly → cloud absent even when configured; mlx present → chosen with rationale containing "resident"; nothing resident → scripted; zero budget → cloud excluded.
- [ ] Implement; old Router tests still pass; commit.

### Task 5: ModelStore, fetch, verify + ModelFetch CLI

**Files:** Create `Sources/MLXRuntime/ModelStore.swift`; `Sources/ModelFetch/main.swift`. Test: `Tests/HybridTests/ModelStoreTests.swift`.

**Produces:** `ModelStore(root: URL)` with `isResident(_ manifest) -> Bool` (manifest + weights + hashes verified), `fetch(_ manifest, progress: @Sendable (Double) -> Void) async throws` (URLSession download, resume-safe, SHA-256 per file against `sourceSHA256` mapping — manifest lists `{filename, sha256}` pairs), `residentRoot(_ manifest) -> URL`. `ModelFetch` CLI: `swift run ModelFetch <modelID>` reads `default-models.json` registry (also accepts full HF id), downloads to app-support root, prints progress + verification result, exit 0/1.

- [ ] Failing tests: pre-seeded dir with correct hash → resident; wrong hash → not resident; `fetch` from a `file://` source URL into temp root → resident after fetch (covers download+verify path offline).
- [ ] Implement; tests pass; commit.

### Task 6: CredentialBroker + ProviderSetup CLI

**Files:** Create `Sources/SecurityKernel/CredentialBroker.swift`; `Sources/ProviderSetup/main.swift`. Test: `Tests/HybridTests/CredentialBrokerTests.swift`.

**Produces:** `protocol SecretStore: Sendable { func set(_ secret: String, service: String) throws; func get(service: String) throws -> String?; func delete(service: String) throws }`; `KeychainStore: SecretStore` (SecItem generic passwords); `InMemorySecretStore: SecretStore`; `CredentialBroker(store: SecretStore)` with `setProviderKey(_ key: String, provider: String)`, `providerKey(_ provider: String) -> String?` (service `aios.provider.<id>`), `remove`. `ProviderSetup` CLI: `swift run ProviderSetup zai` reads the key **only** from env `AIOS_ZAI_KEY` (prompts to stdin if unset), stores via broker, prints confirmation without echoing the key, exit 0/1.

- [ ] Failing tests: InMemory store round-trip; service naming; delete removes; broker never includes key in description/log output.
- [ ] Implement (Keychain impl compile-checked; live exercise in Task 12); tests pass; commit.

### Task 7: Quota/budget enforcement

**Files:** Modify `Sources/Supervisor/Supervisor.swift`. Test: extend `Tests/RecoveryTests/SupervisorTests.swift`.

**Produces:** `Supervisor.checkUsage(provider: ProviderProfile, projectedTokens: Int, usedTokensInWindow: Int) async -> Directive` — refuses when over `quotaWindows` limit unless a window has `paidOverflowAllowed` AND policy credits allowed (refusal reasons contain "quota"); journals a Needs You decision on refusal.

- [ ] Failing tests: under limit → proceed; over limit no overflow → refuseSpend-style refusal + journaled; over limit with allowed overflow → proceed only when caller passes `allowPaid: true` (second parameter).
- [ ] Implement; tests pass; commit.

### Task 8: ZaiClient with fixtures

**Files:** Create `Sources/CloudRuntime/ZaiClient.swift`, `Sources/CloudRuntime/SSE.swift`, `Resources/zai-profile.json`. Test: `Tests/HybridTests/ZaiClientTests.swift`.

**Produces:** `ZaiClient(profile: ProviderProfile, key: String?)` with `chat(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationChunk, Error>` + final usage via `finish` envelope (`ZaiCompletion{result: GenerationResult}`), `models() async throws -> [ProviderModel]`. SSE parser takes byte chunks → events. `makeURLRequest` visible for testing. All HTTP through an injectable `URLSession` (`.init(configuration:)` with URLProtocol stubs in tests). Key absent → `GenerationResult.outcome == .notConfigured`, zero requests. `localOnly` guard before connecting (returns `.refused`).

- [ ] Failing tests (URLProtocol fixtures, recorded from the OpenAI-compatible contract): non-stream request build (endpoint `/chat/completions`, Bearer header, model field); SSE chunk parse (two data events + `[DONE]`); usage extraction from final chunk; 401 → `.failed` with detail; key nil → `.notConfigured` and zero stub hits; localOnly → `.refused` zero hits.
- [ ] Implement; tests pass; commit.

### Task 9: MLXEngine + InferenceWorker `--model` mode

**Files:** Create `Sources/MLXRuntime/MLXEngine.swift`; modify `Sources/InferenceWorker/main.swift`. Test: `Tests/HybridTests/WorkerModelModeTests.swift`.

**Produces:** `protocol LLMEngine: Sendable { func load(_ manifest: ModelManifest, root: URL) async throws; func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationChunk, Error>; func finish() -> GenerationResult }`; `MLXEngine: LLMEngine` (real impl over `MLXLMCommon`, load by `root` path, streaming generate; typed errors). InferenceWorker: `--model <dir>` argument → builds `GenerationRequest` from `WorkPackage.contextBundle` + `taskContract` per `HarnessProfileStore` default, streams `generationChunk` messages, emits `WorkResult` (claims `[Claim(statement: output, statementType: .generatedContent)]`, worker `WorkerIdentity(runtime: .mlx, model: manifest.modelID, revision: manifest.revision)`). Engine is constructed behind a seam (`makeEngine()` overridable via env `AIOS_FAKE_LLM=1` returning `ScriptedEchoEngine` from test support) so the worker logic is testable offline.

- [ ] Failing tests (offline, `AIOS_FAKE_LLM=1` subprocess): workPackage → generationChunk(s) → workResult with `.generatedContent` claim and `.mlx` runtime in worker identity; kill -9 mid-generation → existing crash event (reuse WorkerSession).
- [ ] Implement (real MLXEngine compiles; live behavior exercised in Task 12); tests pass; commit.

### Task 10: Fallback coordinator + hybrid integration

**Files:** Create `Sources/Router/Fallback.swift`. Test: `Tests/HybridTests/HybridFallbackTests.swift`.

**Produces:** `func planFallback(current: RuntimeKind, after: FallbackTrigger (.runtimeFailed/.quotaExhausted/.lostResidency), registry:, policy:, budget:) -> RuntimeKind?` — cloud→local always allowed; local→cloud only when registry.cloudConfigured && policy allows && budget > 0; returns nil when no legal fallback. Integration test: scripted attempt "fails" (simulate quota) → fallback decision → second attempt on stubbed cloud engine (fake LLMEngine path or scripted runtime labeled cloud) completes; journal shows two `ModelSelected` + handoff; task completes with evidence.

- [ ] Failing tests as above + unit table for `planFallback`.
- [ ] Implement; tests pass; commit.

### Task 11: Routing telemetry + EvaluationEngine reader

**Files:** Create `Sources/ModelRuntime/Telemetry.swift`; modify `Sources/EvaluationEngine/TelemetryReader.swift`. Test: `Tests/HybridTests/TelemetryTests.swift`.

**Produces:** `RoutingTelemetry` row (Codable: `modelID, revision, quantization, runtime, harnessProfileID, taskClass, latencyMs, promptTokens, completionTokens, outcome, recordedAt`); `TelemetryWriter(url: URL).append(RoutingTelemetry)` JSONL; `EvaluationEngine.readTelemetry(url:) -> [RoutingTelemetry]` + `summary(byRuntime:) -> [RuntimeKind: (attempts: Int, avgLatencyMs: Double)]`.

- [ ] Failing tests: append→read round-trip; summary aggregation math.
- [ ] Implement; tests pass; commit.

### Task 12: Live gates (run once here, keep env-gated)

**Files:** `Tests/HybridTests/LiveMLXTests.swift`, `Tests/HybridTests/LiveZaiTests.swift`; modify `README.md` (Task 13).

- [ ] Live MLX gate (`AIOS_LIVE_MLX=1`, else skip): fetch the default ~8B 4-bit model via `swift run ModelFetch <id>`; then test spawns InferenceWorker `--model <dir>`, drives one workPackage, asserts a non-empty `.generatedContent` workResult with `.mlx` runtime, and a kill-mid-generation recovery path.
- [ ] Live Z.ai gate (`AIOS_LIVE_ZAI=1` + `AIOS_ZAI_KEY` env, else skip): store key via `swift run ProviderSetup zai` (reads env); one bounded chat completion (≤64 tokens, temperature 0) through `ZaiClient`; assert `.succeeded`, non-empty text, token counts > 0. The burner key is provided only through the environment; nothing is committed.
- [ ] Both gates green in this execution run; default suite still green offline; commit.

### Task 13: Ship — docs, review, merge

- [ ] README: quickstart (build, test, fetch model, run app, configure provider key via env→Keychain), honest limitations section (no tool-calling yet, quota windows advisory when provider lacks usage APIs).
- [ ] Whole-branch review pass (diff scan, smell grep, spec-coverage checklist), fix findings, `swift test` green.
- [ ] Merge `phase2-hybrid-intelligence` into `main`, verify tests on merged result, delete branch.

## Verification gates (Definition of Done)

- `swift test` green offline (Phase 1 suites unchanged + new HybridTests).
- Both live gates exercised successfully in this run (MLX generation + Z.ai completion).
- No credential literal anywhere in the repo (grep for the key prefix must find nothing).
- Ship checklist: spec acceptance criteria for 2A and 2B each demonstrably met.
