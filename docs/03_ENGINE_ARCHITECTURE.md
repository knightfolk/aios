# Engine Architecture

## Architectural center

The engine is a durable runtime for intelligent work, not an agent loop.

```text
User / Project Desktop
        │
Concierge + native commands
        │
Project Kernel
        │
Scheduler / Router / Orchestrator
        │
Expert Runtime or Deterministic Flow
        │
Capability Broker → Security Kernel → Execution Fabric
        │
Action Results / Artifacts
        │
Evidence Engine / Independent Evaluation
        │
Event Journal
        │
Timeline / Activity / Memory / Recovery / Evals
```

## Major modules

### AIOSCore
Stable IDs, shared enums, canonical contracts, versioned schemas.

### ProjectKernel
Owns Project, GoalRevision, PlanRevision, Task, Attempt, Action, Artifact references, project policy, and state projections.

### EventJournal
Append-only authoritative event history. Supports snapshots, replay, migration, crash recovery, historical inspection, and downstream projections.

### Scheduler
Admits work based on dependencies, concurrency, memory, compute, provider quota, budgets, priorities, and leases. Selects execution topology.

### Router
Selects eligible model/runtime/harness profile from capabilities and empirical evidence. Must expose why a choice was made.

### Orchestrator
Strategic heavyweight intelligence for large goals. Creates/revises plans, task contracts, topology, milestone decisions, and major recovery plans. It sleeps between strategic events.

### Supervisor
Mostly deterministic runtime monitor. Watches lifecycle state, hung workers, loop signatures, stale context, contract drift, retries, resource boundaries, and computer-control leases. Wakes Orchestrator only when necessary.

### ContextCompiler
Compiles a bounded task context from goal, contract, project knowledge, decisions, files, artifacts, relevant evidence, skills, tool metadata, prior handoff, model profile, and token budget.

Supported continuity modes:
- Continuation
- Compaction
- Fresh Shift with Handoff Packet

### ExpertRuntime
Stable expert identities, per-project expert memory views, temporary specialists, consultations, and WorkPackage execution sessions.

### CapabilityBroker
Single typed access layer for native capabilities, MCP, filesystem, Git, build/test, browser, search, media, computer use, and credentials.

### SecurityKernel
Enforces scopes and approvals outside the model. Owns filesystem/network boundaries, privacy modes, spending policy, secrets mediation, external side effects, extension trust, and computer-control lease policy.

### ExecutionFabric
Isolated Hands:
- local XPC model workers,
- project workspaces/worktrees,
- build/test sandboxes,
- Chloe computer-control worker,
- media workers,
- cloud workers,
- LAN workers.

### EvidenceEngine
Creates and validates revision-bound evidence, claim provenance, stale-evidence invalidation, verification results, and acceptance coverage.

### EvaluationEngine
Measures trajectories, not just final text: task success, unnecessary actions, recovery, tool correctness, latency, tokens, compute, interventions, evaluator disagreement, and cost/quota usage.

### ModelRuntime
Adapters for MLX/MLX Swift, Core ML where useful, Metal-backed native inference, and remote provider endpoints. Harness Profiles are data-driven.

### VoiceRuntime
Native audio capture/playback, VAD/turn handling, ASR, TTS, barge-in, target selection, pause/stop/emergency semantics.

### MediaRuntime
Image/audio/music/video job orchestration and artifact provenance; load heavyweight models on demand.

## Brain / Hands / History

### Brain
A model invocation or deterministic planner that proposes work.

### Hands
Anything that changes or observes reality: filesystem, shell, Git, browser, simulator, Chloe, cloud execution, media runtime.

### History
The Event Journal and projections. It survives both Brain and Hand crashes.

## Execution topology options

- DIRECT
- DETERMINISTIC
- SINGLE_AGENT
- AGENT_PLUS_REVIEW
- PLANNER_EXECUTOR
- GENERATOR_EVALUATOR
- PARALLEL_RESEARCH
- ORCHESTRATED
- COMPUTER_USE
- MEDIA_PIPELINE

Router/Scheduler choose the simplest topology expected to satisfy the task.
