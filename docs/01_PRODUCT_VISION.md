# Product Vision

## What this is

A native macOS environment for durable intelligent work. It combines the best ideas from coding agents, local AI runtimes, voice assistants, computer-use systems, creative tools, and agent orchestration into one coherent workspace.

The experience should feel like a grounded, useful "AI computer": calm when idle, richly inspectable when needed, and capable of running substantial work for hours without losing state or pretending success.

## What this is not

- Not a chat client with a model selector.
- Not an Electron clone of an existing coding tool.
- Not a fake operating system.
- Not an animation-heavy JARVIS dashboard.
- Not a multi-agent demo where models talk endlessly to each other.
- Not a hosted control plane required for normal use.

## Hardware philosophy

The same product should run across Apple-silicon hardware.

### 32 GB profile

- Lightweight Concierge/local helper.
- Small local model(s) for routing, quick answers, summarization, embeddings, possibly voice.
- Heavy reasoning/coding/vision/media delegated to connected cloud services when permitted.
- Lower concurrency and more aggressive memory eviction.
- Same Project Desktop and workflow semantics.

### 64–128 GB profile

- More resident local expertise.
- Cloud primarily for escalation, frontier quality, or unusually large workloads.

### 192–256 GB+ profile

- Multiple large local expert brains resident.
- Heavy local contexts and concurrent inference.
- Cloud is optional and policy-driven.
- Machine may act as a LAN worker for companion devices.

Hardware changes where intelligence runs, not the conceptual interface.

## Home

Home is structured and calm. It shows only:
- Projects.
- Global Activity.
- Needs You.
- Concierge input.
- Deferred setup pins when useful.

Project cards are compact windows into project state, including a miniature Timeline and a truthful live status.

## Project desktops

Each Project is its own persistent desktop: familiar shell, unique composition.

A software project might emphasize Linus, source files, builds, tests, diffs, simulator, and App Store checks.

A science project might emphasize Einstein, datasets, papers, notebooks, plots, and simulations.

A media project might emphasize Henson, references, generations, audio, and render artifacts.

The desktop restores its card positions, pinned experts, open artifacts, and active goals when reopened.

## Project Timeline

A persistent scrub-able lifecycle surface.

- **Past**: recorded history and retained snapshots.
- **Now**: live current state.
- **Future**: current plan, explicitly projected rather than factual.
- **Gaps**: suspected/confirmed missing work.

Scrubbing backward reconstructs a read-only historical view. Scrubbing forward explores the current projected plan. Branch, Restore, and Replay are explicit actions; scrubbing itself never mutates the project.

The future is living. It can expand, shrink, split, merge, or reveal missing work as the system learns.

## Attention doctrine

- **Visible = useful.**
- **Animated = actively changing and monitorable.**
- **Urgent emphasis = user intervention is genuinely needed.**

Examples of legitimate motion:
- tests counting upward,
- model download progress,
- media render waveform/progress,
- live simulation chart,
- Chloe actively controlling an application.

Illegitimate motion:
- fake neural-network animation,
- meaningless spinning while a model "thinks",
- blinking simply because an agent finished.

## Signature QoL features

### Activity Center
Global process monitor for actual intelligent work. Shows owner, task, state, compute, elapsed time, measurable progress when available, cancellation behavior, and dependencies.

### Needs You
A single cross-project attention queue for blocked decisions, permission requests, ambiguous choices, failed recovery, and review items.

### Project Health
Evidence-based status, never a made-up confidence score:
- goal coverage,
- verification coverage,
- blockers,
- unresolved decisions,
- suspected gaps,
- stale assumptions/evidence,
- active failures.

### Project Inbox
Capture half-formed future ideas without interrupting active work. Promote later to a Goal, Task, Timeline pin, expert consultation, or discard.

### Desk Notes
A lightweight scratch surface for typed, spoken, Pencil/trackpad notes. Notes are not instructions until explicitly promoted.

### Universal Capture
Global shortcut/menu-bar entry for text, voice, screenshot, file, or URL. Concierge can route it to an existing Project, a new Goal, the Project Inbox, or a quick question.

### Follow Me
Later: secure remote monitoring/approval from iPad/iPhone while a Mac continues work. Remote clients observe/approve/control; authoritative project state remains on the owning runtime.

## Apple-native UX

Use SwiftUI for most interface composition and AppKit where it provides superior native behavior (text editing, terminals, large diffs, advanced windowing, performance-sensitive surfaces).

Use system typography, SF Symbols, semantic colors/materials, native focus/keyboard behavior, context menus, drag/drop, Quick Look, Share, notifications, accessibility APIs, Reduce Motion, contrast settings, and standard macOS conventions.

The experience may feel futuristic through capability and responsiveness, not through fake HUD styling.
