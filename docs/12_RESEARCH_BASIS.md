# Research Basis

This design is clean-room and model-neutral, but it intentionally incorporates lessons demonstrated by current production/research agent harnesses.

Checked/reviewed in September 2026. These links are research inputs, not implementation dependencies.

## OpenAI

### Harness engineering: leveraging Codex in an agent-first world
https://openai.com/index/harness-engineering/

Relevant lessons:
- reliable agent performance depends heavily on environment design, feedback loops, observability, and navigable system-of-record documentation;
- humans specify intent and constraints while agents execute;
- repository/tool legibility can matter as much as model capability.

### The next evolution of the Agents SDK
https://openai.com/index/the-next-evolution-of-the-agents-sdk/

Relevant lessons:
- orchestration and sandboxed execution should be separable;
- long-running work benefits from controlled execution environments and explicit infrastructure around tools/files.

## Anthropic

Engineering publications on long-running agents, managed agents, context engineering, tool use, and containment:
https://www.anthropic.com/engineering

Relevant lessons incorporated here:
- separate Brain, Hands, and durable session/history;
- use structured progress/handoffs rather than assuming one endless context;
- independent evaluator patterns are stronger than creator self-grading;
- task/sprint contracts improve clarity around what “done” means;
- containment and deterministic permissions are more dependable than repeated model-mediated approval prompts;
- context selection and compaction strategy should be model/harness specific.

## Google Agent Development Kit

ADK documentation:
https://google.github.io/adk-docs/

Agent Runtime code execution:
https://google.github.io/adk-docs/tools/google-cloud/code-exec-agent-engine/

Relevant lessons:
- sessions/events are durable primitives;
- sequential/parallel/loop workflows should be explicit rather than hidden inside one prompt;
- evaluation should consider tool trajectories and recovery, not only final text;
- persistent sandbox state is valuable for multi-step execution.

## MiniMax Mini-Agent

https://github.com/MiniMax-AI/Mini-Agent

Production guide:
https://github.com/MiniMax-AI/Mini-Agent/blob/main/docs/PRODUCTION_GUIDE.md

Relevant lessons:
- even a minimal harness needs context management, persistent notes, tool integration, logging, retry/step boundaries, and production hardening;
- Skills and MCP should be supported without making them the authoritative runtime model.

## Z.ai / GLM

GLM-5 series repository:
https://github.com/zai-org/GLM-5

Relevant lessons:
- long-horizon agentic behavior is a distinct capability worth evaluating directly;
- model/harness combinations can degrade over long tool-heavy contexts, reinforcing the need for harness profiles, compaction/fresh-shift strategies, and loop/tool-format watchdogs.

## SWE-agent / Agent-Computer Interface

SWE-agent paper:
https://arxiv.org/abs/2405.15793

Relevant lesson:
- the interface exposed to an agent materially affects performance. The CapabilityBroker should therefore expose purpose-built, compact, typed operations instead of raw low-level tools whenever possible.

## Agentless

https://arxiv.org/abs/2407.01489

Relevant lesson:
- autonomous/multi-agent execution is not always the best topology. The Scheduler should choose deterministic or simple pipelines when sufficient.

## Apple platform foundations

Primary Apple developer documentation should be consulted at implementation time for the current APIs and distribution rules, especially:
- SwiftUI / AppKit
- XPC
- MLX / MLX Swift
- Core ML
- Metal / Accelerate
- AVFoundation / AVAudioEngine
- ScreenCaptureKit
- Accessibility / AXUIElement
- Keychain
- App Sandbox and Mac App Store Review Guidelines

The packet deliberately avoids freezing unreleased-hardware performance claims or a permanent model leaderboard. Those belong in measured Runtime Profiles and Model Registry data.
