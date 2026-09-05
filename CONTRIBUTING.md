# Contributing to AIOS

Thanks for your interest in the AI Work Runtime.

## Read first

- `docs/02_ENGINE_CONSTITUTION.md` is the highest architecture authority.
- `AGENTS.md` binds every implementation agent (human or model) to the same
  rules: journaled state transitions, no completion without evidence, no
  fake progress, untrusted inputs never redefine policy.
- `docs/superpowers/specs/` and `docs/superpowers/plans/` hold the design
  and implementation history — check them before proposing architecture
  changes.

## Ground rules

1. **Match the doctrine.** Visible = useful; animated = monitorable; urgent
   = real intervention. No decorative UI, no invented progress numbers.
2. **Tests travel with behavior.** Engine changes need tests for crash
   recovery, stale preconditions, permission denial, Local Only, unknown
   outcomes, cancellation, replay-from-journal, and evidence invalidation
   where relevant (see AGENTS.md).
3. **Credentials never enter the tree.** Keys come from the environment or
   the Keychain. A PR containing a usable credential literal is rejected.
4. **Honest seams beat fake features.** If a capability needs a runtime you
   cannot wire for real, declare it unavailable and say why — do not stub
   success.

## Workflow

- Fork/branch, commit with clear messages, keep `swift test` green
  (`./tools/prepare-mlx-metallib.sh` after a clean build for MLX paths).
- Live gates (`AIOS_LIVE_MLX`, `AIOS_LIVE_TOOLS`, `AIOS_LIVE_ZAI`) are
  opt-in; they must skip, not fail, when unset.
- Describe engine-state changes in PRs in terms of journal events and
  projections — that is how reviewers will read them.

## Licensing

Apache-2.0 for this repository. Model weights, runtimes, and connectors
keep their own licenses; never describe open-weight models as fully
open-source AI.
