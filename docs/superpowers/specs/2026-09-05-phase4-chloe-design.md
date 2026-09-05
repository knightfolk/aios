# Phase 4 — Chloe Computer Control Design

Date: 2026-09-05
Status: Approved by standing directive (finish all phases overnight)
Parent docs: `PROJECT_GOAL.md` (Phase 4), `docs/08_SECURITY_AND_PERMISSIONS.md`, `docs/06_DESKTOP_UX.md`

## Goal

Chloe's Hands, engine-first: an exclusive **computer-control lease**, ranked
**interaction adapters** (native → MCP → AX → DOM → vision) with real
Accessibility-first execution, **Shadow Mode** (propose, never execute),
**reconciliation** for uncertain external actions, and a **hard emergency
stop** that is local, deterministic, and lease-releasing.

## Honest scope for this pass

- Real: lease state machine + journaled grant/release/deny; AX adapter over
  `AXUIElement` (focus, read focused element, type text, activate app);
  Shadow adapter (records proposals, executes nothing — used in tests and
  as safe default); broker enforcement of `.operateComputer`; UNKNOWN →
  Needs-You reconciliation; emergency-stop integration (release + freeze).
- Typed seams, declared not faked: ScreenCaptureKit observation
  (`ScreenObserver` protocol, offline adapter), browser-DOM and pixel-vision
  adapters (last resort per docs; not implemented, listed in registry as
  unavailable — never silently substituted).
- Live AX gate `AIOS_LIVE_AX=1` (requires Accessibility permission for the
  runner; skips when unset or unauthorized).

## New journal events

`leaseGranted(owner,purpose,expiresAt)`, `leaseReleased(reason)`,
`leaseDenied(owner,conflictingOwner)` — additive; fold tracks `activeLease`.

## Safety invariants (tested)

1. Exactly ≤1 active lease; second acquire → `leaseDenied` journaled.
2. Lease expiry and explicit release both clear it; stale lease never
   authorizes actions.
3. `noteUserInteraction()` outranks automation: invalidates the lease's
   focus/screen assumptions and pauses Chloe pending re-observation.
4. Emergency Stop engages → lease released, director frozen (no new
   proposals execute), all journaled; LLM never in the path.
5. External-consequence operations with unverifiable effects → outcome
   UNKNOWN + Needs You (no auto-retry), reusing Phase 1 semantics.
6. Shadow Mode executes nothing and says so in every result.
