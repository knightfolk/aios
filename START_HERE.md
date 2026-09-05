# Start Here

Use this packet as the initial specification for a brand-new repository.

## Recommended repository bootstrap

1. Create a new private or public repository with no inherited codebase.
2. Copy this packet into the repository root.
3. Keep `AGENTS.md`, `PROJECT_GOAL.md`, and `README.md` at the root.
4. Keep all design documents under `docs/`.
5. Choose a temporary codename; do not let naming block architecture work.
6. Start the coding agent with the contents of `PROJECT_GOAL.md` as the primary goal.
7. Instruct it to read `AGENTS.md` and every `docs/*.md` file before proposing implementation.
8. Require it to begin with Phase 0 contracts/kernel and a written implementation plan. Do not permit a UI-first mock implementation.

## First implementation deliverable

The first PR/build should prove:

- append-only EventJournal,
- Project/Goal/Plan/Task/Attempt state projections,
- canonical contracts,
- worker-process boundary,
- deterministic Supervisor lifecycle,
- a minimal SwiftUI shell that can inspect those states,
- tests that replay journal state and survive a simulated worker crash.

It does **not** need a polished AI desktop yet.

## Suggested initial repository structure

```text
App/
  WorkRuntimeApp/
Packages/
  AIOSCore/
  ProjectKernel/
  EventJournal/
  Scheduler/
  Router/
  ContextCompiler/
  ExpertRuntime/
  CapabilityBroker/
  SecurityKernel/
  ExecutionFabric/
  Supervisor/
  EvidenceEngine/
  EvaluationEngine/
  ModelRuntime/
  VoiceRuntime/
  MediaRuntime/
Workers/
  InferenceWorker/
  ToolWorker/
  ComputerControlWorker/
Tests/
  KernelTests/
  RecoveryTests/
  SecurityTests/
  IntegrationTests/
docs/
```

Exact package boundaries may evolve, but do not collapse authoritative state, security enforcement, model execution, and UI into one module for convenience.

## Bootstrap agent prompt

```text
Read README.md, AGENTS.md, PROJECT_GOAL.md, and every file under docs/ before making any implementation proposal.

Treat docs/02_ENGINE_CONSTITUTION.md as the highest architecture authority.

Your first responsibility is not to build the full product. Produce a concrete implementation plan for Phase 0 and the first native vertical slice, identifying technical unknowns that require spikes. Preserve the canonical contracts unless you can demonstrate a contradiction; if you propose changing one, document the reason and the migration impact before implementation.

Use test-driven development for the kernel and recovery behavior. Do not create decorative UI or mock progress that is not backed by engine state. Do not claim completion without running the required verification.
```
