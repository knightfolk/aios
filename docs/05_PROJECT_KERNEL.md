# Project Kernel Data Model

## Project

A persistent desktop and cognitive boundary.

Owns:
- project metadata,
- privacy/spend policy,
- goals,
- project memory/knowledge graph,
- expert project-specific context,
- artifacts,
- desktop layout preferences,
- Timeline projection,
- retention settings.

## GoalRevision

The user-owned contract.

Fields:
- immutable original request reference,
- objective,
- acceptance criteria,
- constraints,
- privacy boundary,
- budget/spend rules,
- explicit exclusions,
- revision reason,
- user approval evidence.

Orchestrator cannot silently modify a GoalRevision.

## PlanRevision

The system-owned proposed route to satisfying the active GoalRevision.

May change automatically within policy. Records:
- milestones,
- task graph,
- dependencies,
- projected future,
- known gaps,
- assumptions,
- revision rationale.

Historical PlanRevisions are retained so Timeline can show what was believed/planned at any point.

## Task

Logical work requirement. Stable across multiple execution attempts.

Fields include:
- objective,
- responsible expert,
- dependencies,
- expected outputs,
- verification requirements,
- logical state.

## Attempt

One concrete execution of a Task under a frozen TaskContract.

Includes:
- WorkPackage,
- selected model/runtime/profile,
- context compilation reference,
- workspace/checkpoint,
- actions,
- result,
- failure/recovery state.

## Action

One capability operation with request/result lifecycle and exact authorization scope.

## Artifact

Produced or modified work product with immutable revision identity.

Examples:
- file/diff/commit,
- report,
- design,
- image/audio/video,
- dataset,
- build,
- simulation output,
- decision record.

## Evidence

Proposition support tied to exact source/artifact revisions.

## Project Knowledge Graph

Model important semantic relationships explicitly:

```text
Requirement
  → satisfied by Feature/Decision
  → implemented by Artifact(s)
  → verified by Evidence/Test(s)
  → invalidated by later Artifact changes when applicable
```

Semantic state types:
- USER_REQUIREMENT
- OBSERVED_FACT
- VERIFIED_FACT
- EXPERT_JUDGMENT
- HYPOTHESIS
- PLAN
- PREDICTION
- GENERATED_CONTENT

Do not collapse these into generic "memory."

## Memory layers

### Global
User preferences, connected compute/services, expert configuration, general skills, user-approved cross-project preferences.

### Project
Canonical project decisions, terminology, important verified facts, architecture, artifact map, completed goals, project-specific expert patterns.

### Goal
Current objective, acceptance criteria, plan, task/evidence coverage, blockers, important decisions.

### Working context
Disposable, task-specific compiled context. It is not permanent memory.

## Memory promotion

Permanent project knowledge must retain provenance, type, scope, relevant revision, and validity status. Model-generated summaries can propose memory candidates; they do not self-authorize permanent truth.

## Event Journal

Authoritative append-only engine history. Typical events:
- ProjectOpened
- GoalCreated / GoalRevised
- PlanProposed / PlanRevised
- TaskCreated / TaskStateChanged
- AttemptStarted / AttemptEnded
- ModelSelected
- ContextCompiled
- ActionRequested / Authorized / Executed / Reconciled
- ArtifactCreated / ArtifactChanged
- EvidenceCreated / EvidenceInvalidated
- VerificationStarted / Passed / Failed / Inconclusive
- DecisionRequested / UserIntervened
- CheckpointCreated
- WorkerCrashed / Recovered
- GoalCompleted / GoalBlocked

Snapshots may accelerate replay but do not replace the journal.

## Branching and checkpoints

A checkpoint records enough project/runtime state to create a safe new branch or restore local project artifacts.

- `Inspect historical state` is read-only.
- `Branch from here` creates a new execution lineage.
- `Restore` is explicit and shows local changes that will be affected.
- External side effects are never undone implicitly by local restore.

## Timeline projection

Derived from journal + active PlanRevision + evidence graph.

- Past: retained factual events/milestones.
- Now: current active execution and unresolved state.
- Future: plan graph from current PlanRevision.
- Gap markers: suspected/confirmed missing requirements or verification coverage.

The Timeline is a projection, not its own source-of-truth database.
