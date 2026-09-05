# Canonical Contracts

These contracts are the model-neutral center of the Work Runtime.

## WorkPackage

Represents one bounded unit of intelligent work.

```text
WorkPackage
- packageID
- projectID
- goalRevisionID
- planRevisionID
- taskID
- attemptID
- role / expert identity
- taskContract
- contextBundle
- capabilities[]
- executionTargets[]
- resourceBudget
- timeBudget
- privacyPolicy
- spendPolicy
- expectedOutputs[]
- verificationRequirements[]
- handoffPolicy
- failurePolicy
- harnessProfile
```

### TaskContract

```text
TaskContract
- objective
- inputs
- allowedScope
- mustPreserve
- forbiddenScope
- expectedOutputs
- verificationRequirements
- dependencyAssumptions
- expiry/staleness conditions
```

Task Contract is frozen for an Attempt. Scope expansion creates a new contract/attempt or requires an explicit approved revision.

## WorkResult

A worker's structured report. It is not itself proof of completion.

```text
WorkResult
- packageID
- attemptID
- worker identity/model/runtime
- status
- artifacts[]
- claims[]
- evidenceRefs[]
- actionRequests[]
- completedActionRefs[]
- discoveredIssues[]
- unresolvedAssumptions[]
- blockers[]
- recommendedNextSteps[]
- handoff
```

## ActionRequest

A typed proposal to use a capability.

```text
ActionRequest
- actionID
- workPackageID
- requestedBy
- capability
- operation
- target
- parameters
- expectedEffect
- sideEffectClass
- reversibility
- idempotency
- requiredPermission
- preconditions[]
- verificationPlan
- timeout
```

No Brain executes reality directly; it requests an Action through the broker.

## ActionResult

What the Hand actually observed.

```text
ActionResult
- actionID
- outcome
- startedAt / endedAt
- observedEffects[]
- artifacts[]
- stdout/stderr references
- verificationResults[]
- stateBefore/stateAfter refs
- reconciliationRequired
- failure details
```

Required outcome classes:
- SUCCEEDED
- FAILED
- PARTIALLY_SUCCEEDED
- CANCELLED
- TIMED_OUT
- UNKNOWN
- REJECTED
- STALE_PRECONDITION

`UNKNOWN` is not retryable until reconciled.

## Evidence

Evidence is first-class and revision-bound.

```text
Evidence
- evidenceID
- projectID
- subject
- proposition
- claimType
- sourceType
- sourceReference
- producedBy
- observedAt
- verificationMethod
- strength
- artifactRevisionRefs[]
- dependencies[]
- invalidatedBy[]
- status
```

Evidence strengths may include:
- OBSERVATION
- PRIMARY_SOURCE
- MECHANICAL_CHECK
- REPRODUCED_RESULT
- INDEPENDENT_REVIEW
- EXPERT_JUDGMENT
- USER_ACCEPTANCE

Evidence statuses:
- VALID
- STALE
- INVALIDATED
- INCONCLUSIVE
- SUPERSEDED

## Handoff Packet

A structured transition between sessions/models/experts.

```text
Handoff
- task
- currentState
- artifactsChanged
- verifiedFacts
- unverifiedAssumptions
- failedApproaches
- blockers
- recommendedNextAction
- evidenceRefs
```

Do not use raw transcript as the handoff format unless explicitly required.
