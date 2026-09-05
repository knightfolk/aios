# Locked Decisions and Open Questions

## Locked product decisions

- Clean-room new project; no requirement to inherit OpenHarness or any previous codebase.
- Native macOS application in Swift/SwiftUI/AppKit.
- Full-screen-capable OS-like work environment, while macOS remains the OS.
- Structured Home; persistent project-specific desktops.
- Hybrid intelligent tiling/freeform cards.
- Card UI obeys: visible = useful, animated = monitorable real activity, urgent emphasis = real intervention.
- Living scrub-able Timeline with factual past, live now, projected future, and gap markers.
- Project desktop can reconstruct historical views without implying rollback of external reality.
- Setup can be deferred using “Put a Pin in It.”
- Lightweight optional Concierge; essential functionality never depends on Concierge.
- Router is separate from Concierge.
- Heavy Orchestrator is selectively invoked for large agentic goals.
- Deterministic/event-driven Supervisor monitors execution.
- Experts are stable identities above replaceable models.
- Permanent roles: Linus, Jobs, Einstein, Sherlock, Henson, Chloe; Concierge is system guide.
- Temporary functional specialists are created as needed.
- One accountable task owner; consultations return bounded work products.
- Apple-first local runtime, with cloud/LAN compute as first-class hybrid extensions.
- 32 GB Macs are first-class acceptance hardware; high-memory Mac Ultra-class systems are scale targets.
- Tools via typed CapabilityBroker; MCP and Agent Skills supported as ecosystem standards.
- Local Only is an enforceable runtime boundary.
- Evidence-backed completion and independent evaluation for important work.
- Computer use is Accessibility/API first, screenshot/pixel fallback last.
- One computer-control lease for the real desktop.
- Event journal is authoritative; Timeline/Activity/UI are projections.
- Direct signed/notarized distribution is the safest initial release assumption; Mac App Store feasibility remains a separate target.

## Working names, not guaranteed shipping trademarks

- Linus
- Jobs
- Einstein
- Sherlock
- Henson
- Chloe

Before public release, perform naming/trademark/personality review and retain the ability to rebrand display names without changing role IDs or stored project state.

## Open architecture questions to resolve through prototypes

### Native process topology
- Which modules should be XPC services vs Swift packages in the main process?
- What is the best isolation mechanism for shell/tool workers under direct distribution and under a possible App Sandbox build?

### Local inference
- MLX Swift integration shape for current best local LLM/VLMs.
- Core ML workloads that materially outperform or simplify MLX equivalents.
- Model residency/eviction strategy under 32, 64, 128, and 256 GB measured systems.
- Feasibility/performance of multiple concurrent model sessions sharing weights/caches.

### Context Compiler
- Relevance/ranking architecture.
- File/repository indexing strategy.
- Knowledge graph persistence and invalidation.
- Safe summarization/memory promotion policies.

### Cloud/subscription integration
- Which providers explicitly permit third-party client use under subscription plans vs API-only use.
- How quota/billing metadata can be obtained reliably.
- How to prevent unapproved subscription-to-PAYG overflow.

### Computer use
- Accessibility element identification stability.
- Browser DOM strategy.
- ScreenCaptureKit latency and privacy behavior.
- Reconciliation strategy for external unknown outcomes.

### Voice
- Best local ASR/TTS models/runtimes at release time.
- Full-duplex audio/echo cancellation strategy.
- Performance targets while large local inference is active.

### App Store
- Sandbox impact on developer-tool workflows, shell execution, worktrees, model downloads, helper services, computer control, and executable Skills.

### Remote companion
- Secure pairing and transport for iPad/iPhone observer/approval clients.
- Which controls are safe remotely, especially Emergency Stop and approvals.

## Product questions that can wait

- Final product name/branding.
- Marketplace.
- A2A federation.
- Third-party UI plugins.
- Windows/Linux first-party desktop clients.
- Exact permanent bundled model roster.
