# Open Ecosystem and Distribution

## Open-source core

Target a permissive license for the application/runtime; Apache-2.0 is a strong default for a serious open developer ecosystem.

Keep licenses explicit for:
- core application,
- model weights,
- runtimes/libraries,
- Skills,
- MCP servers,
- cloud connectors,
- creative media models.

Do not imply that every open-weight model is fully open-source/reproducible AI.

## Standards

### Agent Skills
Use the standard SKILL.md-style packaging model for portable instructions, references, assets, and scripts. Skills request capabilities; they do not receive them automatically.

### MCP
First-class tool/data interoperability. MCP servers remain untrusted extension processes and operate through CapabilityBroker policy.

### ACP
Consider later for interoperability with external coding/editor agents when there is a concrete client/server use case.

### A2A
Consider later for independent remote-agent federation. Do not make it part of the local engine's basic task model.

## Extension types

Do not create one universal "plugin" abstraction.

- Skills: instructions/workflow packages.
- Tools/data: MCP/native CapabilityBroker adapters.
- Models/runtimes: model manifests + Harness Profiles.
- Remote agents: later ACP/A2A adapters.
- UI extensions: initially declarative and tightly constrained.

Avoid arbitrary downloaded in-process Swift bundles/dylibs as the default extension mechanism.

## Extension trust

Require:
- publisher/source metadata,
- pinned version/hash,
- declared capabilities,
- install-time review,
- reapproval when capabilities expand,
- sandbox/out-of-process execution where practical,
- clear uninstall/data-removal behavior.

## Model manifests

Record:
- model/revision ID,
- hashes and quantization provenance,
- license/source,
- modalities,
- context/tool support,
- supported runtimes,
- estimated measured memory by supported quantization on test hardware,
- recommended roles,
- known limitations,
- remote-code requirement,
- evaluation evidence.

## Distribution

Primary early channel: signed and notarized direct macOS build.

Mac App Store should be treated as a separate compatibility target, not a foundational assumption, because the product may require helper processes, large downloaded models, executable Skills, broad developer tooling, screen/accessibility control, and background work.
