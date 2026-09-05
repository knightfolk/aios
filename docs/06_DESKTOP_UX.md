# Desktop UX and Card Grammar

## Shell

Full-screen-capable native macOS application. It should feel like a persistent work environment inside macOS, not a replacement desktop.

Global surfaces:
- Home
- Project switcher
- Activity Center
- Needs You
- Concierge
- Settings / Intelligence / Permissions
- Emergency Stop

## Home

Structured rather than freeform.

Shows:
- Concierge input,
- Projects,
- project-level status/timeline previews,
- global Activity count,
- Needs You,
- deferred setup pins only when useful.

Do not fill Home with model ads, suggested prompts, news, dashboards, or telemetry that has not earned pixels.

## Project desktop

Hybrid adaptive/freeform workspace.

System may tile automatically by default. The user may detach, move, resize, pin, stack, and save layout. Once manually pinned/engaged, cards do not auto-move underneath the user.

Each Project restores its layout and working state when reopened.

## Card grammar

All cards share:
- identity,
- purpose,
- state,
- useful content,
- relevant actions,
- "Why is this here?" explanation.

### Task Card
Owned unit of work. Shows expert, task, state, blockers, and measurable progress only when real.

### Activity Card
A truly monitorable process: build, test, download, simulation, render, inference, computer control.

### Artifact Card
Produced work: diff, report, image, song, build, design, result.

### Finding Card
Discovery, contradiction, missing requirement, security concern, failing test, stale assumption.

### Decision Card
Human judgment/approval needed. Contains context, consequences, system recommendation when available, and clear choices.

Waiting does not automatically mean urgent. Only time-sensitive/unsafe blockers receive strong attention treatment.

### Expert Card
Direct conversation/inspection with an expert. Experts do not permanently occupy space just to prove they exist.

## Card lifecycle

A stable card can change content/state without changing identity or jumping location:

```text
Task: Linus implementing
→ Activity: tests running
→ Finding: two tests failed
→ Task: repair in progress
→ Artifact: implementation ready
→ Verification: evaluator reviewing
→ Verified result
→ collapse into project result/history when safe
```

## Activity Center

User-facing projection of Supervisor/execution state.

Each activity corresponds to a real object/process and may show:
- owner,
- task,
- state,
- execution location,
- compute/memory when useful,
- elapsed time,
- real progress if measurable,
- Pause/Stop/Inspect semantics,
- dependency/blocker.

## Needs You

Cross-project queue for items that cannot continue safely or correctly without user involvement:
- consequential approval,
- preference decision,
- ambiguous goal change,
- external unknown-outcome reconciliation,
- failed recovery,
- privacy/spending expansion.

## Project Health

No single fake confidence score.

Display concrete coverage:
- goal criteria covered,
- evidence current/stale,
- verification pending,
- blockers,
- unresolved decisions,
- suspected gaps,
- active failures.

## Timeline behavior

Collapsed strip available along the project edge; expands into rich lifecycle view.

Scrub backward:
- enter unmistakable Historical View,
- reconstruct relevant cards, plan revision, artifacts, evidence, and expert activity for that point,
- retain a visible `Return to Now` affordance.

Scrub forward:
- explore current projected plan,
- never imply future work has happened,
- surface expected dependencies, missing coverage, and risks.

Concurrent branches should be shown as lanes/branches rather than forcing one false global percentage.

## Setup pins

Onboarding is progressive. User can `Put a Pin in It` and start work immediately.

Deferred setup items return just-in-time when a capability needs them, without persistent nagging banners.

## Accessibility

Every spatial/freeform view must have a structured navigable equivalent. Full keyboard access, VoiceOver semantics, Reduce Motion, contrast settings, clear focus, and non-color-only state cues are mandatory.
