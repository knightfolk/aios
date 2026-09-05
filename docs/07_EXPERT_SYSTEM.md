# Expert System

## Permanent team

### Concierge
System guide/front desk. Small, fast, preferably local and optional.

Responsibilities:
- onboarding,
- navigation,
- explain what is happening,
- introduce the right expert,
- help configure intelligence,
- explain permissions,
- route simple requests,
- translate backend state into normal language.

Concierge does not own scheduling policy and does not solve large agentic goals itself.

### Linus
Engineering, coding, debugging, architecture, systems.

### Jobs
Product definition, UX, simplification, coherence, taste, user-facing decisions.

### Einstein
Science, math, formal reasoning, simulations, modeling, quantitative verification.

### Sherlock
Research, investigation, source verification, contradiction detection, missing-work discovery, evidence quality.

### Henson
Visual art, design production, music, sound, media, creative exploration and artifact creation.

### Chloe
Computer operation: applications, browser, accessibility-driven interaction, GUI automation, cross-app workflows.

Chloe is the Hands specialist. Task ownership remains with the expert that requested the operation.

## Expert identities are not impersonation

Names are product shorthand for stable behavior/domain, not instructions to imitate a real person's voice, likeness, private opinions, or biography.

Public release requires a naming/trademark review. Preserve role schema so display names can change without architectural impact.

## Expert schema

```text
Expert
- identity
- domain
- behavior principles
- responsibilities
- tool/capability preferences
- skill set
- model requirements
- preferred harness profiles
- escalation policy
- consultation rules
- verification standard
- project-specific memory view
```

## Temporary specialists

Created dynamically when precision is needed:
- Swift Concurrency Specialist
- Accessibility Reviewer
- Security Auditor
- 1980s Game Historian
- Audio Mastering Specialist

Temporary specialists use functional names and finite lifetimes. They return bounded work products and disappear from active UI when done.

## Lead + consultation model

Every Task has exactly one accountable owner.

Other experts/specialists provide scoped consultations rather than diffuse shared ownership.

Consultation result should be a structured handoff/artifact, not endless agent-to-agent conversation.

## Orchestrator

Not a personality. Hidden infrastructure.

Use for:
- complex goal decomposition,
- milestone planning,
- task contract creation/revision,
- topology selection,
- major blocker recovery,
- plan gap integration,
- completion coverage review.

Do not use as a constant polling loop.

## Router

Separate from Concierge.

Inputs include:
- required capabilities,
- task class,
- privacy policy,
- available local memory/compute,
- provider entitlements and quotas,
- model/runtime evidence,
- latency priority,
- user preference,
- budget.

Router selects both execution topology and model/runtime/harness profile.

## Supervisor

Event-driven/deterministic where possible.

Detect:
- repeated equivalent failure loops,
- edit/revert loops,
- no-progress windows,
- hung workers,
- stale context/preconditions,
- plan/contract drift,
- quota thresholds,
- invalid evidence after artifact changes,
- computer-control lease conflicts.

## Independent evaluator

System role, not a named expert.

Evaluator receives the Task Contract, artifact/result, and evidence. Prefer independent model family or deterministic checks when practical. Creator context should not bias evaluator unnecessarily.
