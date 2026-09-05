# Post-Roadmap Completion — Five Work Items

Date: 2026-09-05
Status: Approved by standing directive ("finish all the items listed above")

## Item 1 — Agentic tool-calling
Model brains propose real `ActionRequest`s. Worker model-mode becomes
multi-turn: harness-contract JSON may carry an `actions` array; each action
becomes a real broker-gated ActionRequest; the worker blocks on the matching
ActionResult and feeds a compact observation back for the next turn (max 4
turns/attempt). Echo engine gains a declared two-turn action script
(env-gated) so the full loop is tested offline: file written through the
broker, journaled request/execute, completion claims stay `generatedContent`.
Acceptance: offline integration test proves write-through-broker + result
feedback + final WorkResult with `completedActionRefs`; existing suites stay
green. Live-model tool tuning is documented as deferred (harness tuning, not
engine work).

## Item 2 — Ship engineering
Tag `v0.1.0` on final `main`; CI workflow (macOS: `swift build`, `swift
test`); delete the burner Z.ai key from the local Keychain; create the
GitHub remote and push if `gh` is authenticated, else record the blocker.
Notarization: documented as requiring Apple Developer credentials (scaffold
only). No credential literals anywhere (env/Keychain only).

## Item 3 — Real speech + media adapters
TTS: `SayTTSAdapter` driving `/usr/bin/say` (real local synthesis; tests
render to file and verify AIFF bytes). ASR: `SpeechASRAdapter` over
Speech.framework file-based recognition (live-gated `AIOS_LIVE_ASR=1`,
needs user authorization; offline tests use the echo seam). Media: attempt
a real Z.ai image-generation adapter (`cogview`) behind the existing seam;
if the provider rejects, it stays a declared unavailable adapter with the
attempt recorded — never faked.

## Item 4 — Chloe depth
AX selector engine: pure matcher (role/title/substring) over an
injectable element-tree protocol with fake-based tests; `clickElement`
resolves via the matcher and executes `AXPress` on real AX (live-gated).
ScreenCaptureKit: availability probe via the real permission API; capture
stays a declared seam until an entitled app shell exists.

## Item 5 — Multi-project app shell
Home lists every project found under the journal root (one per project
directory); a switcher selects the active project; full-screen-capable
window. Project discovery is a tested pure function over the filesystem.
