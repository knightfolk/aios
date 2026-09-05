# AI Work Runtime — Project Starter Packet

> Clean-room design packet for a native, open-source macOS AI work environment.

This repository packet defines a **native Swift/SwiftUI/AppKit AI work environment** that feels like a grounded, useful "AI computer" rather than a chat client. It is designed to scale from a 32 GB Apple-silicon Mac using hybrid cloud intelligence to a 256 GB Mac Ultra-class system capable of keeping multiple heavyweight local models resident.

The product metaphor is an AI operating environment. Architecturally, macOS remains the OS; this project is a **durable Work Runtime** for goals, agents, tools, evidence, computer use, voice, media, and long-running execution.

## Core product idea

- Full-screen native macOS workspace.
- Structured Home; each Project owns its own persistent, adaptive desktop.
- Card-based activities that expose useful state without decorative telemetry.
- A living, scrub-able Project Timeline:
  - Past = recorded history.
  - Now = live execution.
  - Future = current plan.
  - Gaps = known or suspected missing work.
- Permanent expert identities above interchangeable model backends:
  - **Linus** — engineering and coding.
  - **Jobs** — product, UX, simplification, taste.
  - **Einstein** — science, mathematics, modeling.
  - **Sherlock** — research, investigation, verification, gap finding.
  - **Henson** — art, media, music, creative production.
  - **Chloe** — computer use, application control, automation.
  - **Concierge** — lightweight system guide and front desk; not a specialist expert.
- Small local Concierge + deterministic Router + powerful on-demand Orchestrator + deterministic Supervisor.
- Apple-native runtime first: Swift, SwiftUI, AppKit, MLX/MLX Swift, Core ML where appropriate, Metal, AVFoundation, ScreenCaptureKit, Accessibility APIs, XPC.
- Hybrid local/cloud compute by design.
- Open standards where they fit: MCP for tools/data, Agent Skills for skills, later ACP/A2A only when justified.

## Design doctrine

1. **Visible = useful.**
2. **Animated = real ongoing activity that can be monitored.**
3. **Urgent emphasis = intervention genuinely needed now.**
4. **No fake progress, fake certainty, or fake activity.**
5. **The user owns goals; the system owns plans.**
6. **Models are workers, never authoritative state.**
7. **Completion requires evidence.**
8. **Context is compiled, not accumulated.**
9. **Brains propose; Hands act; History records.**
10. **The UI remains fully operable when models fail.**

## Packet map

- `PROJECT_GOAL.md` — ready-to-paste kickoff goal for a coding agent.
- `AGENTS.md` — project-wide rules for implementation agents.
- `docs/01_PRODUCT_VISION.md` — product definition and UX principles.
- `docs/02_ENGINE_CONSTITUTION.md` — non-negotiable runtime invariants.
- `docs/03_ENGINE_ARCHITECTURE.md` — subsystem architecture and data flow.
- `docs/04_CANONICAL_CONTRACTS.md` — WorkPackage, WorkResult, ActionRequest, ActionResult, Evidence.
- `docs/05_PROJECT_KERNEL.md` — Project/Goal/Plan/Task/Attempt/Action/Artifact/Evidence model.
- `docs/06_DESKTOP_UX.md` — Home, Project desktops, card grammar, Activity Center, Timeline.
- `docs/07_EXPERT_SYSTEM.md` — expert identities, temporary specialists, orchestration rules.
- `docs/08_SECURITY_AND_PERMISSIONS.md` — capability enforcement, computer-control lease, cloud/privacy rules.
- `docs/09_MODEL_AND_COMPUTE_RUNTIME.md` — Apple-first local runtime, 32 GB hybrid mode, 256 GB local mode, provider abstraction.
- `docs/10_VALIDATION_AND_ROADMAP.md` — vertical slice, adversarial acceptance tests, phased implementation.
- `docs/11_OPEN_ECOSYSTEM.md` — open-source posture, extension boundaries, interoperability.

## First milestone

Do **not** attempt to implement the entire vision in one uncontrolled pass. The first milestone is a production-quality vertical slice that proves the engine contracts:

> Open an existing Swift project → create a Goal → produce a Task Contract → execute a bounded code change in an isolated workspace → run validation → independently review it → show live Activity + Timeline state → recover correctly from a worker crash → preserve a durable audit trail.

The architecture must still support non-code work from day one, so include one secondary research/artifact scenario in tests.

## Non-goals for the first milestone

- Building a Finder replacement.
- Building a fake macOS desktop or window manager.
- A plugin marketplace.
- A2A federation.
- Full local image/music/video generation.
- Universal provider support.
- Dozens of permanent experts.
- App Store submission before sandbox/background-process feasibility is proven.

## Licensing direction

The application should target a permissive open-source license (Apache-2.0 is a strong default). Models, runtimes, skills, and cloud connectors retain their own licenses and terms. Do not describe all open-weight models as fully open-source AI.

