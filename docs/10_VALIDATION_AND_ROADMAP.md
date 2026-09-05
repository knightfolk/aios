# Validation Strategy and Roadmap

## First vertical slice

Prove the engine before breadth.

Representative coding flow:
1. Open existing Swift repository.
2. State bounded Goal.
3. Create GoalRevision and PlanRevision.
4. Generate Task Contract.
5. Compile context.
6. Route to Linus.
7. Create isolated workspace/worktree.
8. Execute edits through typed actions.
9. Run build/tests.
10. Bind Evidence to exact artifact revision.
11. Independent evaluator checks contract.
12. Timeline/Activity/Health update from journal.
13. Simulate worker crash and recover.

Secondary non-code test:
- Sherlock researches a bounded question, produces a sourced artifact, records facts vs judgments, and is independently checked for evidence coverage.

## Required adversarial scenarios

| Scenario | Required behavior |
|---|---|
| Model worker crashes | UI stays usable; attempt is durably failed/recoverable. |
| App restarts mid-goal | Resume from journal/checkpoint without replaying unsafe side effects. |
| Provider quota expires | Pause or use preauthorized fallback at checkpoint; no silent paid expansion. |
| User edits target file mid-run | Action returns STALE_PRECONDITION; no overwrite. |
| Two projects request Chloe | Lease serializes control or alternative interface is used. |
| Prompt injection asks to upload secrets | Permission/policy boundary blocks escalation. |
| User scrubs into past | Historical inspection does not alter live execution. |
| Heavy render while voice active | Concierge/voice interrupt/Stop remain responsive within measured SLO. |
| Worker claims completion without evidence | Task remains unverified. |
| Concierge unavailable | Core app navigation/configuration/recovery still works. |
| Non-idempotent action loses confirmation | Outcome UNKNOWN; reconcile before retry. |
| Artifact changes after passing tests | Related evidence becomes stale automatically. |
| Agent repeatedly issues equivalent failing tool call | Supervisor halts loop and requests strategy change/replan. |
| Agent modifies files outside Task Contract | Plan Drift/contract violation blocks or requests expansion. |

## Performance SLOs to establish experimentally

Do not invent final numbers before prototype measurements. Establish and test targets for:
- UI frame responsiveness under inference load,
- Emergency Stop latency,
- voice barge-in latency,
- Activity Center update latency,
- journal append/replay performance,
- context compile latency,
- worker crash detection,
- model load/unload overhead,
- memory-pressure response.

## Phased roadmap

### Phase 0: Kernel
Canonical contracts, EventJournal, ProjectKernel, state projections, tests.

### Phase 1: Native desktop vertical slice
Home, one Project desktop, cards, Timeline baseline, Activity Center, Linus path, one local runtime, build/test actions, evaluator.

### Phase 2: Hybrid scheduler
One cloud connector, provider profiles, budgets/quotas, checkpoint handoff, model/harness evaluation.

### Phase 3: Deep Project UX
Needs You, Project Health, Desk Notes, Project Inbox, projected future, branching/checkpoints, evidence graph UI.

### Phase 4: Chloe
Accessibility-first computer use, lease, Shadow Mode, reconciliation, emergency stop.

### Phase 5: Voice
ASR/TTS adapters, full-duplex interaction, barge-in, target selection, load testing.

### Phase 6: Creative/media
Henson workflows, image/audio/music generation adapters, artifact versioning, render scheduling.

### Phase 7: Ecosystem/remote
MCP, Agent Skills, extension trust/signing, LAN workers, secure iPad companion, later ACP/A2A only if concrete use cases justify them.

## Release posture

Prefer signed/notarized direct distribution first. Evaluate Mac App Store feasibility separately once sandboxing, helper processes, executable Skills/plugins, downloaded models, background workers, and computer-control requirements are proven against current Apple rules.
