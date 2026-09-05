# AIOS — Phase 0 + First Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Phase 0 engine kernel (canonical contracts, append-only EventJournal, ProjectKernel projections) and the Phase 1 native vertical slice (goal → task contract → isolated worker execution → build/test evidence → independent verification → SwiftUI inspection → crash recovery), per `PROJECT_GOAL.md` and `START_HERE.md`.

**Architecture:** One SwiftPM package with strict target boundaries (never collapse authoritative state, security enforcement, model execution, and UI into one module — START_HERE rule). The event journal is the only authoritative history; Timeline/UI are projections. Brains (worker processes) never touch reality directly — they emit `ActionRequest`s through the CapabilityBroker/SecurityKernel. Workers are separate executables (subprocess, length-framed stdio protocol); XPC adoption is a timeboxed spike, not a Phase 0 assumption.

**Tech Stack:** Swift 6 (strict concurrency; actors for journal/supervisor), SwiftPM, SwiftUI + AppKit shell, CRC-framed JSONL journal (no DB dependency in Phase 0), Swift Testing framework. macOS 15 floor (lowerable later).

## Global Constraints

- Native Swift/Apple frameworks only; typed Swift interfaces internally, versioned wire schemas only across process boundaries.
- Every state transition journaled; UI never source of truth; no completion from model self-report.
- Unknown outcomes are never auto-retried; completion requires declared evidence.
- Untrusted inputs (files, worker output) cannot alter policy or user intent.
- No decorative UI, fake progress, or mock state. The Phase 1 worker is an honestly-declared scripted runtime (`runtime: .scripted`, journaled truthfully); real build/test actions and evidence are real.
- TDD: failing test → implement → pass → commit, for all kernel/recovery behavior.
- Local Only is enforced at broker/network boundaries, not by a badge.
- Emergency Stop is local, deterministic, and independent of any model.

---

### Task 0: Repo bootstrap

**Files:** Create `.gitignore`, `LICENSE` (Apache-2.0), `Package.swift`.

- [ ] `git init` in `/Users/kevink/Projects/aios` (the parent `~/Projects` repo ignores all non-MyTV paths, so this stays clean).
- [ ] Root `Package.swift`: macOS 15, Swift 6 tools, library targets `AIOSCore`, `EventJournal`, `ProjectKernel`, `Scheduler`, `Router`, `Supervisor`, `CapabilityBroker`, `SecurityKernel`, `ExecutionFabric`, `ExpertRuntime`, `EvidenceEngine`, `ContextCompiler`, `EvaluationEngine`; executable targets `WorkRuntimeApp`, `InferenceWorker`, `ToolWorker`; test targets `KernelTests`, `RecoveryTests`, `SecurityTests`, `IntegrationTests`.
- [ ] `swift build` succeeds on an empty skeleton; commit.

### Task 1: AIOSCore — IDs, enums, canonical contracts

**Files:** Create `Sources/AIOSCore/Identifiers.swift`, `Sources/AIOSCore/Enums.swift`, `Sources/AIOSCore/Contracts.swift`. Test: `Tests/KernelTests/ContractCodableTests.swift` + golden JSON fixtures.

**Produces:** typed UUID-backed IDs (`ProjectID`, `GoalRevisionID`, `PlanRevisionID`, `TaskID`, `AttemptID`, `ActionID`, `ArtifactID`, `EvidenceID`, `WorkPackageID`, `ExpertID`); enums `SemanticStatementType` (7 values per docs 05), `EvidenceStrength` (7), `EvidenceStatus` (5), `ActionOutcome` (SUCCEEDED, FAILED, PARTIALLY_SUCCEEDED, CANCELLED, TIMED_OUT, UNKNOWN, REJECTED, STALE_PRECONDITION), `ExecutionTopology` (10 values), `CapabilityClass` (observe / modifyWorkspace / operateComputer / externalConsequence); Codable structs `WorkPackage`, `TaskContract`, `WorkResult`, `ActionRequest`, `ActionResult`, `Evidence`, `Handoff` with all fields exactly as listed in docs 04, each carrying `schemaVersion: UInt = 1`.

- [ ] Failing tests: Codable round-trip per contract; golden-JSON decode (old payload still decodes).
- [ ] Implement minimal types; tests pass; commit.

### Task 2: EventJournal — append-only, crash-safe

**Files:** Create `Sources/EventJournal/EventRecord.swift`, `EventKind.swift`, `JournalStore.swift`, `JournalReader.swift`. Test: `Tests/KernelTests/JournalTests.swift`.

**Produces:** `EventKind` covering the full docs-05 event list (ProjectOpened … GoalCompleted/GoalBlocked); frame layout `magic ‖ version ‖ length ‖ CRC32 ‖ JSON`; one journal per project under `~/Library/Application Support/AIOS/projects/<id>/journal/`; `JournalStore` actor with monotonic sequence; optional fsync-per-append; replay stops at first torn/corrupt frame and reports `tornTail`.

- [ ] Failing tests: append→replay equality; truncate last frame → clean prefix + torn-tail flag; CRC bit-flip → corruption detected; interleaved appends stay ordered; 100k-event replay smoke < 5s.
- [ ] Implement; tests pass; commit.

### Task 3: ProjectKernel — state model + pure projections

**Files:** Create `Sources/ProjectKernel/Project.swift`, `GoalRevision.swift`, `PlanRevision.swift`, `Task.swift`, `Attempt.swift`, `Action.swift`, `Artifact.swift`, `ProjectState.swift`, `Projection.swift`. Test: `Tests/KernelTests/ProjectionTests.swift`.

**Produces:** the docs-05 hierarchy (`Project → GoalRevision → PlanRevision → Task → Attempt → Action → Artifact`, plus `Evidence` links); `static func apply(_ state: ProjectState, _ event: EventRecord) -> ProjectState` as a pure fold; `Projection.replay(_ reader:)`; snapshots as cache + journal offset (accelerator only, never authoritative).

- [ ] Failing invariant tests: original goal intent immutable; `Task` reaches `Complete` only via a verification-passed event, never from `WorkResult`; `UNKNOWN` attempt outcome blocks retry until a reconcile event; wipe-snapshots-then-replay == snapshot state.
- [ ] Implement; tests pass; commit.

### Task 4: Worker boundary — InferenceWorker / ToolWorker executables

**Files:** Create `Sources/InferenceWorker/main.swift`, `Sources/ToolWorker/main.swift`, `Sources/ExecutionFabric/FrameCodec.swift`, `WorkerProcess.swift`, `WorkerSession.swift`. Test: `Tests/RecoveryTests/WorkerBoundaryTests.swift`.

**Produces:** length-prefixed Codable frames over stdio with `schemaVersion` checked on both sides; 5s heartbeat; `WorkPackage` in → `WorkResult` out; `ActionRequest`s streamed as proposed. InferenceWorker v1 = scenario-file-driven scripted runtime, journaled as `runtime: .scripted`. ToolWorker executes broker-authorized build/test/shell actions.

- [ ] Failing tests: kill -9 mid-run → session detects, journal records `WorkerCrashed`, attempt durably recoverable, host process unaffected; missed heartbeats → hung-worker detection.
- [ ] Implement; tests pass; commit.

### Task 5: SecurityKernel + CapabilityBroker — typed Hands, transaction lifecycle

**Files:** Create `Sources/SecurityKernel/Policy.swift`, `LocalOnlyEnforcer.swift`, `ApprovalGate.swift`; `Sources/CapabilityBroker/Broker.swift`, `Capabilities.swift`. Test: `Tests/SecurityTests/BrokerPolicyTests.swift`.

**Produces:** v0 capabilities `fs.read`, `fs.write`, `git.worktree`, `git.diff`, `shell.run` (allowlisted build/test commands), `artifact.record`; journaled phases Prepare→Validate→Authorize→Execute→Observe→Reconcile; preconditions = content hash at validation, re-checked at execute (else `STALE_PRECONDITION`); Local Only blocks all docs-08 classes (cloud inference, remote tools, browser/network, shell networking, telemetry, remote workers, derived uploads); goal-level envelope (filesystem roots + command allowlist) enforced outside the worker.

- [ ] Failing tests: mid-run user edit → `STALE_PRECONDITION`, no overwrite; out-of-scope write → `REJECTED`; non-idempotent op with lost confirmation → `UNKNOWN`, retry refused until reconcile; injection-style text in file content does not change policy; Local Only blocks every class.
- [ ] Implement; tests pass; commit.

### Task 6: Supervisor — deterministic monitor

**Files:** Create `Sources/Supervisor/Supervisor.swift`. Test: `Tests/RecoveryTests/SupervisorTests.swift`.

**Produces:** event-driven actor detecting hung workers (heartbeat timeout), repeated equivalent failures (signature = capability + operation + failure class; 3 strikes → halt + `DecisionRequested`), plan/contract drift (action outside frozen TaskContract), budget/quota ceiling refusal. No Orchestrator polling in Phase 1.

- [ ] Failing tests: loop-signature halt; out-of-scope action blocks attempt with contract violation journaled; lifecycle transitions all journaled.
- [ ] Implement; tests pass; commit.

### Task 7: EvidenceEngine + independent evaluator v0

**Files:** Create `Sources/EvidenceEngine/Evidence.swift`, `Invalidation.swift`; `Sources/EvaluationEngine/Evaluator.swift`. Test: `Tests/KernelTests/EvidenceTests.swift`.

**Produces:** evidence bound to exact artifact revisions (content hash / commit SHA); invalidation cascade when a referenced revision changes; deterministic evaluator checking TaskContract verification requirements against the evidence set and rejecting `WorkResult.status == completed` claims lacking required evidence.

- [ ] Failing tests: tests-passed evidence auto-STALE after post-verification edit; unevidenced completion claim → task stays `unverified`.
- [ ] Implement; tests pass; commit.

### Task 8: Scheduler + Router + ExpertRuntime + ContextCompiler (minimal)

**Files:** Create `Sources/Scheduler/Scheduler.swift`, `Sources/Router/Router.swift`, `Sources/ExpertRuntime/Expert.swift`, `Team.swift`, `Sources/ContextCompiler/Compiler.swift`. Test: `Tests/KernelTests/SchedulingAndRoutingTests.swift`.

**Produces:** dependency/concurrency admission with resource budget check; deterministic Router returning `RoutingDecision` with recorded reasons; the 7 stable expert identities per docs-07 role schema (display names swappable without touching role IDs); ContextCompiler v0 = contract + selected file set + prior handoff within a token budget (no transcript shoveling).

- [ ] Failing tests: routing rationale journaled; context respects budget; expert identity independent of runtime (swap worker runtime under same `ExpertID` → journal shows `ModelSelected` only).
- [ ] Implement; tests pass; commit.

### Task 9: Integration — the vertical slice

**Files:** Create `Tests/IntegrationTests/VerticalSliceTests.swift` + a generated Swift fixture repo in a temp directory.

**Produces:** all 13 PROJECT_GOAL Phase 1 steps end-to-end with real subprocess workers, including step 13 kill-and-recover; plus the Sherlock secondary scenario (bounded research artifact separating `OBSERVED_FACT` from `EXPERT_JUDGMENT`, independently checked for evidence coverage); plus the docs-10 adversarial rows applicable now: restart-mid-goal replay, stale precondition, quota pause, UNKNOWN reconciliation, evidence staleness, completion-without-evidence, equivalent-failure halt, contract-drift block, Concierge-absent operation.

- [ ] Write the scenario test against the current engine (it should fail where machinery is missing).
- [ ] Close gaps until the full slice passes; commit.

### Task 10: SwiftUI shell (minimal, truthful)

**Files:** Create `Sources/WorkRuntimeApp/` (SwiftPM executable hosting NSApplication + SwiftUI): Home (projects, global activity count, Needs You), one Project desktop rendering Task/Activity/Artifact/Finding/Decision cards from `ProjectState` projections, collapsed Timeline strip (Past/Now/Future/Gaps from journal + PlanRevision), Emergency Stop control (deterministic — cancels workers, freezes broker, journals `UserIntervened`).

- [ ] No Concierge, no fake motion; card state changes only from journaled events; view models unit-tested against projections; manual smoke run via `swift run WorkRuntimeApp`; commit.

## Verification gates (Definition of Done for this milestone)

- `swift test` green across Kernel/Recovery/Security/Integration suites.
- Project state fully reconstructible from journal alone (test wipes snapshots and replays).
- Kill a worker mid-run → shell process alive, attempt recoverable.
- No completion without evidence; no retry after UNKNOWN; Local Only test-covered.
- START_HERE first-deliverable checklist fully proven.

## Explicit spikes (docs 13 unknowns — timeboxed, findings recorded before code)

1. XPC service vs subprocess topology for workers under direct distribution.
2. MLX Swift integration shape + smallest viable local model (feeds Phase 2; off this milestone's critical path).

## Out of scope (later phases per roadmap)

MLX/cloud runtimes (P2), Needs You/Health/Inbox/branching UX depth (P3), Chloe computer control (P4), voice (P5), media/MCP/Skills/LAN/iPad (P6–7). Target graph already reserves places for these.
