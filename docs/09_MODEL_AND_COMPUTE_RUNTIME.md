# Model and Compute Runtime

## Apple-first policy

The product is native Swift and Apple-silicon-first, but not "Core ML only."

Use the best validated backend per workload:
- MLX / MLX Swift for local LLM/VLM workloads that fit.
- Core ML for workloads where conversion/runtime characteristics are advantageous, including suitable small always-on models/classifiers/embeddings.
- Metal/Accelerate for lower-level compute and specialized pipelines.
- AVFoundation/AVAudioEngine for audio.
- Isolated XPC workers for model/media execution so UI and safety controls survive worker failure.

Do not require a localhost HTTP server when a native worker interface is practical.

## Compute abstraction

Treat the Mac as a unified resource pool:
- unified memory,
- GPU,
- CPU performance/efficiency cores,
- Neural Engine where supported by the chosen runtime/workload,
- media engines,
- storage bandwidth,
- thermal state.

The scheduler reasons about resident weights plus KV/cache/temporary memory and other applications, not just model file size.

## Model residency

Expert identity does not imply dedicated model residency. Multiple experts may share one loaded model while retaining independent WorkPackages/context.

Common experts may keep preferred models warm when resource policy allows. Heavy media models load on demand.

Interactive priority order generally favors:
1. Emergency controls.
2. Concierge/user interaction/voice barge-in.
3. Foreground task execution.
4. Background verification/research.
5. Media/background throughput.

## Hybrid 32 GB mode

The same UI/workflow should remain usable on a 32 GB Mac.

Likely local roles:
- Concierge,
- routing/classification,
- embeddings/search helpers,
- small/medium general model depending on workload,
- lightweight ASR/TTS where practical.

Heavy work routes to permitted cloud services or LAN workers at explicit checkpoints.

## 256 GB mode

A high-memory Mac can keep several large local models and caches resident, increase concurrency, run local multimodal/media jobs, and serve as a private LAN worker.

Do not hard-code capacity assumptions for unreleased hardware. Benchmark actual devices and build profiles from measured memory/throughput/latency.

## Provider capability profile

A provider connection records more than a name/key:
- permitted integration/client type,
- models actually available,
- modalities,
- context/tool support,
- subscription vs credits vs PAYG behavior,
- quota windows and visibility,
- concurrency/rate limits,
- endpoint compatibility,
- last verification date,
- privacy/data-handling policy metadata.

Never silently overflow from subscription allowance into paid credits unless the user explicitly authorized that behavior.

## Harness Profiles

Versioned data per model family/revision/runtime:
- prompt/system strategy,
- tool call format,
- reasoning mode/effort,
- context maintenance strategy,
- preferred execution topologies,
- retry rules,
- known failure signatures,
- evaluator compatibility.

Harness Profiles must be updateable independently of the core engine.

## Routing evidence

Evaluate the actual configuration:
`model + revision + quantization + runtime + harness profile + task class`.

Track:
- success rate,
- verification pass rate,
- recovery rate,
- unnecessary actions,
- tool-call correctness,
- human interventions,
- latency,
- tokens/compute,
- memory footprint,
- cloud quota/cost,
- evaluator disagreement.

Use uncertainty/sample counts; do not overfit from a few tasks.

## Candidate model policy

Do not hard-code a permanent roster in architecture. Ship a curated registry that can evolve.

Prefer permissively licensed local defaults where possible. Distinguish:
- application open-source license,
- permissive model weights,
- custom/open-weight licenses,
- fully open/reproducible model status,
- proprietary cloud services.
