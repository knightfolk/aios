# Phase 3 — Project Desktop Depth Design

Date: 2026-09-05
Status: Approved by standing directive ("move on to the next phase"); pre-implementation
Parent docs: `PROJECT_GOAL.md` (Phase 3), `docs/01_PRODUCT_VISION.md`, `docs/06_DESKTOP_UX.md`, `docs/05_PROJECT_KERNEL.md`

## Goal

Give Project desktops their planned depth, engine-first: a resolvable **Needs
You** queue, evidence-based **Project Health**, **Desk Notes** and **Project
Inbox** with explicit promotion, **Projected Future** inspection, explicit
**branching/checkpoints**, and **structured historical scrub** that is
visually and semantically inspect-only. No decorative UI: every panel reads
real projected state; historical views never mutate.

## Scope decisions (from the locked docs)

- Needs You entries resolve through a journaled event; resolution removes
  them from the active queue and records the answer.
- Project Health shows concrete coverage (goal criteria, verification,
  blockers, unresolved decisions, suspected gaps, stale evidence, active
  failures) — never a single confidence number.
- Desk Notes are scratch, stored outside the journal; they are **not**
  instructions until explicitly promoted (promotion journals an event).
- Project Inbox captures half-formed ideas; promotion targets: Goal, Task,
  Timeline pin, or discard.
- Historical scrub reconstructs read-only state at any journal sequence via a
  pure replay prefix; Return to Now is always one action away; scrubbing
  never mutates the journal (Constitution #22).
- Checkpoints record journal position + note + artifact refs. Branch creates
  a new PlanRevision lineage referencing the checkpoint. Restore is explicit,
  warns about local changes, and never claims to undo external side effects.
- The projected future is the active plan's task graph, clearly labeled as
  projection, with dependency and risk hints from real fields only.

## New journal events (additive, versioned)

- `needsYouResolved(NeedsYouResolvedPayload{subject, question, answer, resolvedAt})`
- `notePromoted(NotePromotedPayload{noteID, target: .goal/.task/.timelinePin, summary})`
- `inboxItemPromoted(InboxItemPromotedPayload{itemID, target: .goal/.task/.timelinePin/.discarded, summary})`
- `branchCreated(BranchCreatedPayload{fromCheckpointID, newPlanRevisionID, previousPlanRevisionID, reason})`
- `restoredFromCheckpoint(RestoredFromCheckpointPayload{checkpointID, note})`

`CheckpointCreated` (docs 05) already exists.

## Non-goals

- Freeform card dragging/persistence beyond layout basics (hybrid tiling
  refinement waits).
- Evidence-graph visualization beyond counts/links in Health.
- Remote Follow Me, Chloe, voice, media (later phases).

## Components

| Unit | Responsibility |
|---|---|
| `ProjectKernel/NeedsYou.swift` | queue projection incl. resolution state |
| `ProjectKernel/Notes.swift` | Notes + Inbox JSON stores, promotion API journaling events |
| `ProjectKernel/Checkpoints.swift` | checkpoint records, branch/restore helpers |
| `ProjectKernel/Projection.swift` (ext) | fold for new events; `state(at:sequence:)` historical prefix |
| `ProjectKernel/Health.swift` | pure ProjectHealth view model from ProjectState |
| `DesktopShell/*` | Needs You panel, Health panel, Notes/Inbox, Timeline scrubber + projected future inspector |

## Testing

Kernel: fold/projection tests per new event; scrub purity (journal
byte-identical before/after); checkpoint→branch lineage; restore semantics;
health coverage math on synthetic states; notes promotion journals; inbox
promotions. Shell: view models tested against scripted journals; UI smoke
via `swift run WorkRuntimeApp --journal <dir>`.
