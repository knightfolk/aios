# Phase 3 — Desktop Depth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: executing-plans (subagents unavailable in this harness). Steps use checkbox (`- [ ]`) tracking.

**Goal:** Ship Phase 3 per `docs/superpowers/specs/2026-09-05-phase3-desktop-depth-design.md`: resolvable Needs You, evidence-based Project Health, Desk Notes + Inbox with explicit promotion, projected-future inspection, branching/checkpoints, and inspect-only historical scrub.

**Architecture:** All depth is engine-first: new additive journal events fold into `ProjectState`; notes/inbox are non-journal stores whose promotions journal events; scrub is a pure replay-prefix; UI panels read projections only.

## Global Constraints
- Scrubbing never mutates the journal (byte-identical, tested).
- Historical views are visually unmistakable and one action from Return to Now.
- Notes are never instructions until promoted; promotion is journaled.
- Health = concrete coverage fields, no composite confidence score.
- Restore never claims to undo external side effects.

## Tasks
- [ ] **T1 New events + fold**: `needsYouResolved`, `notePromoted`, `inboxItemPromoted`, `branchCreated`, `restoredFromCheckpoint` payloads + `EngineEvent` cases + `Projection.apply` handling + tests (fold, resolution removes from queue, branch lineage recorded, restore recorded).
- [ ] **T2 Historical scrub**: `Projection.state(at: UInt64, of:) -> ProjectState` replay-prefix + test asserting purity (journal bytes identical), correctness at N, and independence from snapshots.
- [ ] **T3 Checkpoints & branching**: `CheckpointStore` (record = sequence + note + artifact refs via `CheckpointCreated`; list), `branch(from:reason:)` journaling `branchCreated` + new PlanRevision, `restore(checkpointID:)` journaling `restoredFromCheckpoint` with explicit local-change warning text surfaced. Tests: lineage, double-branch, restore-after-work.
- [ ] **T4 Notes & Inbox**: `NotesStore`/`InboxStore` (JSON under project storage root, injectable), `promote(note:target:)` / `promote(item:target:)` journaling events; discard for inbox. Tests: round-trip, promotion journals, notes never touch model context (store has no engine import path beyond events).
- [ ] **T5 ProjectHealth**: pure `ProjectHealth.compute(from: ProjectState) -> ProjectHealth` (goalCriteriaTotal/Covered, verificationPending, blockers, unresolvedDecisions, suspectedGaps, staleEvidence, activeFailures) + tests on synthetic states incl. empty project.
- [ ] **T6 Shell UI**: Needs You panel (list + resolve action), Health panel, Notes/Inbox views with promote buttons, Timeline scrubber (slider over journal sequences; historical mode banner + Return to Now), Projected Future list (pending tasks + dependencies, labeled projection). View models tested; AppModel gains `historicalState(at:)`.
- [ ] **T7 Integration + ship**: scripted-journal test driving all view models (checkpoint → branch → scrub → health → needs-you resolve → note promote); README update; review pass; merge to `main`.
