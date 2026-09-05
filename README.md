# AIOS — AI Work Runtime

A native, open-source macOS work environment for durable intelligent work: a
grounded "AI computer" rather than a chat client. Users work inside persistent
Project desktops; underneath is a durable runtime for goals, agents, tools,
evidence, computer use, voice, media, and long-running execution.

Status: **Phase 0–4 complete** (engine kernel, first vertical slice, hybrid
intelligence). See `docs/superpowers/specs/` and `docs/superpowers/plans/` for
the design history; `docs/` holds the full architecture packet.

## What runs today

- Append-only, crash-safe **EventJournal** (CRC-framed, torn-tail tolerant).
  The journal is the only authoritative state; everything else is a projection.
- **ProjectKernel** projections with enforced invariants: no completion from
  model self-report, no retry after UNKNOWN outcomes, immutable goal intent.
- **Worker boundary**: real subprocess workers (framed stdio protocol,
  heartbeats, SIGKILL crash detection and recovery). The InferenceWorker has
  two honest modes: `--scenario` (declared scripted runtime) and `--model`
  (real local MLX inference).
- **SecurityKernel + CapabilityBroker**: Prepare→Validate→Authorize→Execute→
  Observe→Reconcile lifecycle, stale-precondition detection, workspace
  containment, command allowlist, Local Only enforcement of every escalation
  class. Credentials live in the Keychain (or env); never in source or logs.
- **Local MLX runtime**: ~8B 4-bit local models, hash-verified on download
  (LFS SHA-256 for weights, git blob SHA-1 for configs).
- **One validated cloud connector (Z.ai)**, OpenAI-compatible with SSE
  streaming and usage extraction. The bundled profile defaults to the
  free-tier `glm-4.5-flash`; paid models are opt-in.
- **Supervisor**: deterministic loop-halt, contract-drift block, budget and
  quota refusal (subscription allowance never silently overflows to paid).
- **Checkpoint fallback** across scripted / MLX / cloud with journaled
  `ModelSelected` switches and handoff packets.
- **Evidence engine**: revision-bound evidence with automatic staleness
  cascade; independent evaluator rejects unevidenced completion claims.
- **Minimal truthful SwiftUI shell**: cards from projections, Past/Now/Future/
  Gaps timeline, deterministic Emergency Stop.
- **Desktop depth**: resolvable Needs You queue, evidence-based Project
  Health (no composite score), Desk Notes + Project Inbox with explicit
  journaled promotion, projected-future panel, checkpoints with explicit
  branch/restore, and inspect-only timeline scrub (pure replay prefix — the
  journal is byte-identical before and after scrubbing).

## Build & test

```sh
swift build          # builds everything including mlx-linked targets
swift test           # offline, fast: full suite (unit + integration)
```

## Prepare MLX Metal kernels (one-time per clean build)

SwiftPM does not emit mlx-swift's Metal library; MLX loads it colocated with
the binaries. After `swift build` (and after any clean), run:

```sh
./tools/prepare-mlx-metallib.sh
```

## Fetch the local model (one-time, ~4.3 GB)

```sh
swift run ModelFetch qwen25-7b-instruct-4bit
```

Downloads from Hugging Face `mlx-community`, verifies every file hash, and
marks the model resident under `~/Library/Application Support/AIOS/models/`.

## Live gates (opt-in)

```sh
# Real local MLX generation through a real worker process:
AIOS_LIVE_MLX=1 swift test --filter liveMLXGenerationInWorker

# One bounded Z.ai completion (key from env or Keychain):
AIOS_LIVE_ZAI=1 AIOS_ZAI_KEY=... swift test --filter liveZaiCompletion
```

Store a provider key without putting it in any command line history you
share: `AIOS_ZAI_KEY=... swift run ProviderSetup zai`.

## Inspect a project journal

```sh
swift run WorkRuntimeApp --journal <directory-containing-<uuid>-journals>
```

## Honest limitations (as of Phase 4)

- No tool-calling from model brains yet: local/cloud generation produces
  typed `generatedContent` claims only; real effects still flow through the
  scripted scenario path and the broker.
- Z.ai quota windows are advisory — the provider lacks a public usage API;
  enforcement uses locally tracked response-reported usage.
- Keychain-stored keys are readable only by processes the user approves
  (unsigned CLI binaries prompt); the app target will carry proper
  keychain-access groups.
- **Chloe computer control (Phase 4)**: single-owner lease (journaled
  grant/release/deny/expiry), Accessibility-first adapter (activate app,
  read focused element, type text — requires the runner to hold the
  Accessibility trust), Shadow Mode that records without executing, and an
  Emergency Stop path that releases the lease and freezes the director
  deterministically. `clickElement` refuses rather than guessing until the
  AX selector engine lands; ScreenCaptureKit observation and browser-DOM /
  pixel adapters are typed seams, honestly reported unavailable.
- Voice and media runtimes are later phases; see
  `docs/10_VALIDATION_AND_ROADMAP.md`.

## License

Apache-2.0 for this repository. Model weights, runtimes, and connectors keep
their own licenses and terms.
