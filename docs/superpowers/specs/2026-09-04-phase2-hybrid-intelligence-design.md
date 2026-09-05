# Phase 2 — Hybrid Intelligence Design

Date: 2026-09-04
Status: Approved (design); pre-implementation
Parent docs: `PROJECT_GOAL.md` (Phase 2), `docs/09_MODEL_AND_COMPUTE_RUNTIME.md`, `docs/13_DECISIONS_AND_OPEN_QUESTIONS.md`

## Goal

Give the Work Runtime its first two real Brain runtimes — a local MLX runtime
(~8B 4-bit class model) and one validated cloud connector (Z.ai,
OpenAI-compatible) — plus the policy layer that chooses between them:
provider capability profiles, quota/budget enforcement, data-driven harness
profiles, and graceful local↔cloud fallback at checkpoints. The Phase 0/1
architecture (journal, contracts, worker boundary, broker, evidence) is
unchanged; Phase 2 fills the `ModelRuntime` slot it reserved.

## Decisions already made

- Cloud provider: **Z.ai** (user holds an API key). Wire format is the
  OpenAI-compatible chat-completions API.
- Local model scale: **~8B 4-bit** (≈5 GB) from Hugging Face `mlx-community`;
  model identity is manifest-driven, chosen at implementation time from the
  best available GLM/Qwen build.
- Build order: two milestones — **2A local intelligence**, then **2B hybrid
  policy**. Each lands working, tested software.

## Non-goals (this phase)

- Tool-calling / agentic loops driven by local or cloud models (harness
  profiles define the shape; execution arrives in later phases).
- Multiple cloud providers (the abstraction exists; one connector ships).
- Model residency/eviction management beyond a load-and-hold worker
  lifecycle (Scheduler memory accounting stays coarse).
- Voice/media runtimes.

## Architecture

Three runtimes sit behind one typed interface, selected by the Router:

```
RuntimeRegistry
  ├─ scripted   (always available; honest fallback; declared in journal)
  ├─ mlx        (when a manifest + verified weights are resident locally)
  └─ cloudAPI   (Z.ai; when a provider profile + key + policy allow)
```

New SwiftPM libraries keep boundaries clean:

| Library | Depends on | Responsibility |
|---|---|---|
| `ModelRuntime` | AIOSCore | Pure types: `ModelManifest`, `ProviderProfile`, `HarnessProfile`, `GenerationRequest/Chunk/Result`, `RuntimeRegistry`. No I/O. |
| `MLXRuntime` | AIOSCore, ModelRuntime, mlx-swift(-examples) | `MLXEngine` (load + stream generation), `ModelStore` + `ModelFetch` (download, resume, SHA-256 verify). The **only** target that links mlx. |
| `CloudRuntime` | AIOSCore, ModelRuntime | `ZaiClient`: streaming chat completions, usage extraction, model listing; refuses network under Local Only before any connection opens. |

`InferenceWorker` gains a `--model <dir>` mode; `WorkRuntimeApp` and tests
gain nothing new structurally. `SecurityKernel` gains a `CredentialBroker`
(Keychain-backed) used by `CloudRuntime` and, later, every connector.

No new journal event kinds. Runtime selection journals through the existing
`ModelSelected`; provenance rides on `WorkResult.worker` (model name,
revision, runtime, quantization). Routing telemetry is appended as JSONL
under project storage (see Evaluation) rather than new journal events.

## Milestone 2A — Local intelligence

### ModelManifest (ModelRuntime)

Fields per docs 11: `modelID` (slug), `family`, `revision`, `quantization`,
`sourceURL`, `sourceSHA256`, `license`, `modalities`, `contextWindowTokens`,
`estimatedMemoryGB` (measured on test hardware), `supportedRuntimes`,
`recommendedRoles`, `knownLimitations`, `requiresRemoteCode`,
`evaluationRef`. Codable, schema-versioned, golden-JSON tested.

A curated `default-models.json` registry ships in-repo listing the chosen
~8B 4-bit manifest.

### ModelStore / ModelFetch (MLXRuntime)

- Storage root: `~/Library/Application Support/AIOS/models/<modelID>/`
  containing `manifest.json` + weights.
- `fetch(manifest)`: downloads with progress callback, verifies SHA-256 of
  every weight file against the manifest, refuses to mark a model resident
  on mismatch or partial download (resumable).
- CLI: `swift run ModelFetch <modelID-or-hf-id>` — manual, one-time,
  journaled nowhere (setup tooling, not engine state).

### MLXEngine (MLXRuntime)

Wraps mlx-swift-examples' LLM stack (model load, tokenizer, sampling).
`generate(request, onChunk)` streams tokens; reports prompt/completion token
counts and latency in the result. Load failures throw typed errors that map
to the existing worker-crash path.

### HarnessProfile (ModelRuntime)

Versioned JSON, data-driven, updateable independently of the engine
(built-in defaults in the library; overrides from
`~/Library/Application Support/AIOS/harness/` win). Fields per docs 09:
prompt/system strategy, output format contract (v1: a JSON `WorkResult`
template the model must fill), reasoning mode, context maintenance strategy,
preferred topologies, retry rules, known failure signatures, evaluator
compatibility.

### InferenceWorker `--model` mode

- Loads the manifest + weights via `MLXEngine`; heartbeats and the framed
  stdio protocol are unchanged.
- On `workPackage`: builds the prompt from `contextBundle` +
  `taskContract` per the harness profile, streams
  `generationChunk`s, then emits a `workResult` whose claims are typed
  `generatedContent` — never auto-promoted to fact, never tool-calling.
- The scripted runtime remains available as fallback (`--scenario`).

### Wire protocol additions (ExecutionFabric)

`WireMessage` gains: `generationRequest(GenerationRequest)`,
`generationChunk(GenerationChunk)`, `generationDone(GenerationResult)`.
Frame format and versioning unchanged; both sides check `schemaVersion`.

### Router upgrade

`RuntimeRegistry` enumerates available runtimes (scripted always; mlx iff
the manifest is resident and weights verified; cloud iff profile + key +
policy allow). `Router.decide` consumes the registry and returns runtime +
topology + rationale; under Local Only or zero budget, cloud remains
structurally unreachable (existing tests keep passing).

### 2A acceptance criteria

- `swift test` green, offline, fast; MLX paths behind `AIOS_LIVE_MLX=1`.
- With `AIOS_LIVE_MLX=1` and the model fetched: InferenceWorker completes a
  real generation for a work package; output is a typed, journaled
  WorkResult; killing the worker mid-generation follows the existing crash
  path (journal + recovery).
- Router picks mlx with recorded rationale when resident; scripted
  otherwise.

## Milestone 2B — Hybrid policy

### ProviderProfile (ModelRuntime)

Fields per docs 09: `providerID`, `endpoint`, `protocol`
(`.openAICompatible`), models available (ids, modalities, context),
`billingMode` (`.subscription` / `.credits` / `.payAsYouGo`), quota windows
and their visibility, rate limits, privacy/data-handling metadata,
`lastVerifiedAt`. Ships as `zai-profile.json` in-repo.

### CredentialBroker (SecurityKernel)

Keychain-backed (service `aios.provider.<providerID>`). `set`, `get`,
`delete`. Secrets never enter model context, journal, logs, or worker env by
default. CLI helper `swift run ProviderSetup zai` prompts and stores.

### ZaiClient (CloudRuntime)

- Streaming chat completions (SSE), OpenAI-compatible request/response.
- Usage extraction (prompt/completion tokens) per chunk-final message.
- Model listing for capability discovery.
- Before any network: consults policy (`localOnly` → refuse locally, no
  connection), budget (SpendPolicy), and quota window state.

### Quota & budget enforcement

- `Supervisor.checkSpend` extended: `checkUsage(provider:, projectedTokens:)`
  consults the profile's quota window + a per-session usage tracker fed by
  client-reported usage; subscription allowance never silently overflows
  into paid credits (refusal + Needs You instead).
- All cloud usage is attributable: journal already records `ModelSelected`;
  the WorkResult carries tokens/latency.

### Graceful fallback at checkpoints

Fallback happens at attempt/checkpoint boundaries only — never mid-action.
`Router.refallback(now:, after:)` re-decides when a runtime failed, is
quota-exhausted, or lost residency; journals the new `ModelSelected` and
transfers a `Handoff` packet (existing type). Direction obeys policy:
cloud→local is always permitted (it reduces exposure); local→cloud
additionally requires the privacy policy, budget, and quota window to
allow it — and never happens silently.

### HarnessProfile × cloud

The same profile drives the cloud prompt/JSON contract; provider-specific
quirks (reasoning fields, tool formats) live in the profile data, not code.

### 2B acceptance criteria

- Default suite green and offline: Z.ai client tested against recorded
  fixtures (URLProtocol stubs) including SSE parsing, usage extraction, and
  error surfaces.
- Hybrid integration test: local attempt fails at a checkpoint → fallback to
  a stubbed cloud runtime → completion with evidence; `ModelSelected`
  switch journaled; handoff packet present.
- Quota-refusal test: projected usage over window with
  `allowPaidCredits == false` → refusal + Needs You entry, zero network.
- With `AIOS_LIVE_ZAI=1` + stored key: one real end-to-end generation smoke
  against Z.ai (tiny prompt, bounded tokens).

## Error handling summary

| Failure | Behavior |
|---|---|
| Model load OOM/corrupt | Existing worker-crash path; Router fallback at checkpoint |
| Hash mismatch after download | Model not marked resident; fetch reported failed |
| Network/HTTP error | Typed `GenerationResult.outcome == .failed` with detail |
| Missing key | Connector reports not-configured; zero network |
| Local Only | Connector refuses before connecting; Router never selects cloud |
| Quota/budget ceiling | Supervisor refusal + Needs You; no silent PAYG overflow |

## Testing strategy

- **Unit (offline, default):** golden decodes for manifest/profile/harness;
  registry + routing decision tables with rationale; harness override
  loading; quota-window math; budget refusal; Z.ai client fixtures;
  SSE parser; SHA-256 verification logic.
- **Integration (offline, default):** hybrid fallback flow with stubbed
  cloud; scripted→mlx registry behavior with a fake manifest; wire-protocol
  round-trips for generation messages.
- **Live gates (opt-in):** `AIOS_LIVE_MLX=1` (real generation, real
  crash-recovery), `AIOS_LIVE_ZAI=1` (real cloud smoke). Live gates skip
  (not fail) when env unset.

## Dependencies & risks

- `mlx-swift` / `mlx-swift-examples` (GitHub, pinned): largest new risk;
  isolated to `MLXRuntime`; if the dependency breaks the build, 2A blocks
  but 2B's offline work remains independent.
- One-time ~5 GB download via `ModelFetch` (manual).
- Z.ai quota/usage API surface may be thinner than assumed; usage then
  relies on response-reported usage only, with quota windows marked
  "advisory" in the profile — recorded as a limitation, not papered over.

## Evaluation (minimal, this phase)

A JSONL telemetry file per project
(`storage/telemetry/routing.jsonl`: model, revision, quantization, runtime,
harness, taskClass, latencyMs, tokens, outcome) appended by the worker host
after each attempt; `EvaluationEngine` gains a reader + summary API. No
journal schema change.
