# /goal — Build the AI Work Runtime

Build a production-quality, open-source, native macOS AI work environment from the architecture in this packet.

## Product outcome

Create a full-screen, Apple-native Swift application that feels like a grounded "AI computer": users work inside persistent Project desktops populated by useful cards, a living scrub-able Timeline, Activity Center, Needs You queue, Project Health, Desk Notes, and expert identities. The runtime underneath must support durable goals, long-running agent execution, local and cloud models, computer use, high-quality voice, media generation, tools/skills, evidence-backed completion, crash recovery, and strict capability enforcement.

## Hard constraints

- Native Swift/SwiftUI/AppKit. No Electron, React, embedded web UI, or web-first shell.
- macOS is the operating system; this application is a Work Runtime, not a Finder/desktop replacement.
- Apple-silicon-first compute architecture using MLX/MLX Swift, Core ML where it is a better fit, Metal, Accelerate, AVFoundation, ScreenCaptureKit, Accessibility APIs, and isolated XPC workers where appropriate.
- Must scale down to a 32 GB Apple-silicon Mac through hybrid cloud execution.
- Must scale up to a 256 GB Mac Ultra-class machine with several local expert brains resident concurrently.
- Concierge may be bundled as a lightweight optional local model, but every essential operation must have a non-AI path.
- Models must never own authoritative project state, permissions, or completion state.
- No model may grant itself capabilities or credentials.
- Local Only must be technically enforced across models, tools, plugins, networking, and telemetry.
- Important completion claims require declared evidence.
- Historical Timeline scrubbing is inspect-only unless the user explicitly branches/restores.
- Computer control must use a single-owner lease and an emergency stop path independent of language models.
- Do not invent progress percentages when progress is not objectively measurable.

## Permanent expert identities

- Linus — engineering/coding.
- Jobs — product/UX/taste.
- Einstein — science/math/modeling.
- Sherlock — research/investigation/verification/gap finding.
- Henson — creative media/art/music.
- Chloe — computer use/application operation/automation.
- Concierge — lightweight system guide/front desk, not a specialist expert.

Expert identity must be independent of the underlying model. Router may change a role's brain without changing the expert identity or project memory.

## Runtime roles

- Concierge: immediate user-facing assistance and navigation.
- Router: mostly deterministic capability + evidence + resource selection.
- Orchestrator: heavyweight planning/replanning for complex goals; invoked selectively.
- Supervisor: deterministic/event-driven execution monitoring, watchdogs, drift detection, retries, leases, and lifecycle state.
- Experts: specialized execution owners.
- Independent Evaluator: separate verification role; not a personality expert.

## Build order

### Phase 0 — contracts and kernel
Implement the canonical state types and durable event journal before building autonomous agent behavior.

Required first-class contracts:
- WorkPackage
- WorkResult
- ActionRequest
- ActionResult
- Evidence

Required state hierarchy:
Project → GoalRevision → PlanRevision → Task → Attempt → Action → Artifact → Evidence

### Phase 1 — native vertical slice
Prove one real workflow end to end:
1. Open a Swift repository.
2. Create a Goal with immutable original intent and revisionable acceptance criteria.
3. Generate a Plan and Task Contract.
4. Route to Linus.
5. Create isolated execution workspace/worktree.
6. Assemble context through ContextCompiler.
7. Execute edits through CapabilityBroker/ExecutionFabric.
8. Run build/tests.
9. Produce Evidence tied to exact artifact revisions.
10. Run independent review.
11. Mark task complete only if the contract verifies.
12. Show state through cards, Activity Center, and Timeline.
13. Kill an inference worker mid-run and prove recovery.

### Phase 2 — hybrid intelligence
Add local MLX runtime + one validated cloud connector. Add provider capability profiles, quota/budget policy, harness profiles, topology selection, and graceful fallback at checkpoints.

### Phase 3 — project desktop depth
Add Needs You, Project Health, Desk Notes, Project Inbox, Projected Future inspection, branching/checkpoints, and structured historical scrub.

### Phase 4 — Chloe
Add ScreenCaptureKit observation, Accessibility-first operation, browser/native API preference, bounded computer-control lease, Shadow Mode, reconciliation for uncertain external actions, and hard emergency stop.

### Phase 5 — full-duplex voice
Add native audio pipeline, local/remote ASR and TTS adapters, barge-in, explicit target selection, pause vs stop semantics, and performance tests under heavy inference load.

### Phase 6 — media and ecosystem
Add Henson media runtime, artifact versioning, MCP, Agent Skills, signed extension policy, remote worker nodes, and optional iPad companion/remote monitoring.

## Definition of done for the first release candidate

- Core runtime remains responsive if any model worker crashes.
- Project state can be reconstructed from the event journal.
- No unsafe auto-retry after an action outcome is unknown.
- Local Only is enforceable and test-covered.
- 32 GB hybrid profile completes the same representative workflow as the high-memory profile, with reduced concurrency/locality rather than a different UI.
- At least one heavyweight local model path works on Apple silicon through the Apple-first runtime.
- At least one cloud provider path is documented and legitimately supported.
- Provider quota/spending behavior is visible and never silently escalates beyond policy.
- User edits during agent execution are detected as stale preconditions.
- Independent verification can reject an expert's completion claim.
- Timeline distinguishes recorded past, live now, projected future, and gaps.
- Accessibility/keyboard navigation has a structured non-spatial alternative to freeform card manipulation.
- Emergency Stop works without invoking an LLM.

## Engineering behavior

Follow `AGENTS.md` and every design document in `docs/` as architecture requirements. When requirements conflict, prefer the Engine Constitution. Do not paper over a missing capability with mock data or decorative UI. Record limitations explicitly and leave the engine in a truthful state.
