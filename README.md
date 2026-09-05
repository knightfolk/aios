# AIOS — AI Work Runtime

A native, open-source macOS work environment for durable intelligent work: a
grounded "AI computer" rather than a chat client. Users work inside persistent
Project desktops; underneath is a durable runtime for goals, agents, tools,
evidence, computer use, voice, media, and long-running execution.

Status: **First full roadmap pass complete, live-proven** — the resident
local model proposes real actions, the broker executes them, and the
journal records everything.

## Architecture in one screen

```
User / Project Desktop (SwiftUI, projections only)
        │
Concierge routing (goal: / note: / inbox: / ask:)
        │
Project Kernel ← Event Journal (append-only, CRC-framed; the only truth)
        │
Scheduler / Router (registry + telemetry-driven recommendations)
        │
Expert Runtime → InferenceWorker (--model: real MLX brain, multi-turn
        │         tool-calling via harness contracts; --scenario: declared
        │         scripted double)      ToolWorker (authorized commands)
        │
CapabilityBroker → SecurityKernel → ExecutionFabric
   (Prepare→Validate→Authorize→Execute→Observe→Reconcile; Local Only;
    workspace scopes; command allowlists; one computer-control lease)
        │
EvidenceEngine / Independent Evaluation → completion only on evidence
```

Design authority: `docs/02_ENGINE_CONSTITUTION.md`. History:
`docs/superpowers/specs/` and `docs/superpowers/plans/`. Contributing:
`CONTRIBUTING.md`. (engine kernel, first vertical slice, hybrid
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
- **Interactive desktop**: Needs You entries resolve in place; notes and
  inbox items promote with one click; checkpoints branch and restore from
  the shell; live activities stop deterministically. A timeline event ruler
  shows branch lanes and snaps the playhead to meaningful history. Per-
  project layouts persist; a semantic design-token set keeps past visually
  unmistakable from now. Expert Cards hold real conversations over live
  worker sessions (resident model when available, echo double otherwise —
  always labeled).
- **OS layer**: native macOS menu bar (File/View/Desktop/Control — every
  command routes through the tested CommandRouter), a menu-bar status item
  with live needs-you/activity counts and a deterministic Emergency Stop
  entry, per-project desktops that restore their full session (card order,
  pins, scrub position, layout) on switch, drag-and-drop card arrangement,
  right-click context menus (copy/pin/card-size), and window autosave with
  proper resizability.
- **Chloe Deck** (animated, constitution-honest): a ghost hand whose
  gesture mirrors real lease/action state (hovering, reaching, shadow-mime
  that never lands, uncertain hold, user-outranked recoil, frozen on
  Emergency Stop), an authority metronome that swings only while a live
  lease breathes and stops dead when the user outranks automation, and an
  action constellation where UNKNOWN outcomes keep pulsing until
  reconciled. Reduce Motion swaps every animation for static glyphs.
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

## Honest limitations (as of the review round)

- No tool-calling from model brains yet: local/cloud generation produces
  typed `generatedContent` claims only; real effects still flow through the
  scripted scenario path and the broker.
- Z.ai quota windows are advisory — the provider lacks a public usage API;
  enforcement uses locally tracked response-reported usage.
- Keychain-stored keys are readable only by processes the user approves
  (unsigned CLI binaries prompt); the app target will carry proper
  keychain-access groups.
- **Review-round hardening**: journal appends in state-transition paths
  now propagate failures (an unwritable journal refuses new actions and
  lease grants instead of silently proceeding); AppModel refresh is
  snapshot-accelerated; the bootstrap stub is gone; AppModel lives in its
  own file; all seven permanent experts render as cards; the timeline
  scrub snaps at scale; historical surfaces are hue-distinct in dark and
  light mode; interactive controls carry accessibility labels; an
  onboarding empty state greets journal-less launches; an Activity Center
  panel shows live attempts with deterministic stop; the quality loop
  (telemetry writer + empirical recommender) and ContextCompiler are wired
  into the runtime; a voice surface panel routes through the VoiceSession.
- **Chloe computer control (Phase 4)**: single-owner lease (journaled
  grant/release/deny/expiry), Accessibility-first adapter (activate app,
  read focused element, type text — requires the runner to hold the
  Accessibility trust), Shadow Mode that records without executing, and an
  Emergency Stop path that releases the lease and freezes the director
  deterministically. `clickElement` refuses rather than guessing until the
  AX selector engine lands; ScreenCaptureKit observation and browser-DOM /
  pixel adapters are typed seams, honestly reported unavailable.
- **Voice runtime (Phase 5)**: session state machine with explicit target
  routing, distinct stop-speaking / pause / stop semantics, RMS-energy
  barge-in that cancels playback, and a load-probe latency test. ASR/TTS
  adapters are injectable; the bundled pair is a declared echo double —
  real local/cloud speech adapters are typed seams, honestly unavailable
  until their runtimes land.
- **Real speech + image adapters**: local TTS via the system `say`
  synthesizer (renders genuine AIFF audio, tested); Speech.framework ASR
  adapter that reports authorization honestly and never fabricates
  transcripts; a real Z.ai `cogview-4-250304` image adapter behind the
  media seam — verified against the live API (2026-09-05): the model
  exists but requires paid balance, so it reports unavailable on a
  zero-balance account rather than faking output.
- **Media runtime (Phase 6, Henson)**: render scheduling (one at a time,
  cancellable), artifact versioning with per-revision seeds and content
  hashes, and journaled provenance. The builtin renderer produces real
  local artifacts (gradient PNGs, tone WAVs) explicitly labeled synthetic —
  model-backed image/music/video adapters are typed seams, honestly
  unavailable until their runtimes land.
- **Ecosystem (Phase 7)**: a real MCP client (JSON-RPC 2.0 over stdio:
  initialize → tools/list → tools/call, integration-tested against a live
  fixture server) with tool→action mapping under broker policy; Agent
  Skills SKILL.md loading where declared capabilities are requests, never
  grants; extension trust with pinned SHA-256 hashes and mandatory
  reapproval on capability expansion; LAN worker transport as an honest
  declared seam.
- Remaining roadmap depth (remote iPad companion, ACP/A2A, signed
  distribution, model-backed media renderers, real speech adapters) is
  tracked in `docs/10_VALIDATION_AND_ROADMAP.md` and the README
  limitations above.

## Release engineering

- CI: `.github/workflows/ci.yml` builds, prepares the MLX metallib, runs the
  offline suite, and smoke-launches the shell on every push/PR.
- Notarization and signed distribution require an Apple Developer account
  and certificates that are not part of this repository; the direct-build
  channel remains the release path until those exist.
- Publishing: the repository is prepared for a public GitHub remote;
  credentials/secrets never live in the tree.

## License

Apache-2.0 for this repository. Model weights, runtimes, and connectors keep
their own licenses and terms.
