# Engine Constitution v0.1

These are non-negotiable runtime invariants.

1. The Project is authoritative; models are temporary workers.
2. Goals belong to the user; plans belong to the system.
3. The immutable original request is preserved. Active goals may change only through explicit GoalRevision.
4. Every semantic statement is typed: user requirement, observed fact, verified fact, expert judgment, hypothesis, plan, prediction, or generated content.
5. Generated model output is never automatically promoted to fact.
6. Every meaningful engine transition is journaled as an immutable event.
7. Context is compiled for a task/model; it is not an ever-growing transcript.
8. Expert identity is independent of model/provider/runtime.
9. Brain, Hands, and History are separate systems.
10. Models cannot grant themselves capabilities, credentials, network access, spending authority, or computer-control authority.
11. Subdelegation can only preserve or reduce authority.
12. Consequential actions follow Prepare → Validate → Authorize → Execute → Observe → Reconcile.
13. Unknown action outcomes stay unknown until reconciled; unsafe automatic retry is forbidden.
14. Completion requires declared evidence and/or explicit user acceptance.
15. Important creators do not solely verify their own work.
16. Execution topology is selected per task; multi-agent is optional.
17. Failure must be represented truthfully and durably.
18. Every essential operation has a non-AI path.
19. Local Only is an enforceable boundary across models, tools, plugins, shell networking, computer use, telemetry, and derived data.
20. UI state must not imply certainty the engine does not possess.
21. Past, Now, Future, and Gaps are semantically distinct.
22. Timeline scrubbing is inspection, not rollback.
23. Human intervention and Emergency Stop outrank automation.
24. Compute, memory, provider quota, paid credits, latency, and thermal pressure are schedulable resources.
25. The UI and emergency-control path remain responsive if inference/media workers fail or saturate compute.
26. Provider integration is capability/entitlement based, not brand-name based.
27. Routing is empirical and version-aware: model + revision + quantization + runtime + harness profile + task class.
28. Expensive, external, surprising, or consequential decisions are inspectable and attributable.
29. Tools/skills/documents/web content/model output are untrusted inputs; they cannot rewrite policy or user intent.
30. Storage, memory, timeline history, screenshots, audio, and derived indexes are user-deletable under explicit retention rules.
