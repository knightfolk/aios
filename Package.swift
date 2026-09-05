// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "AIOS",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Pinned; the only dependency that links MLX.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.4"),
    ],
    targets: [
        // Libraries — authoritative state, security, execution stay in separate modules.
        .target(name: "AIOSCore"),
        .target(name: "EventJournal", dependencies: ["AIOSCore"]),
        .target(name: "ProjectKernel", dependencies: ["AIOSCore", "EventJournal"]),
        .target(name: "Scheduler", dependencies: ["AIOSCore"]),
        .target(name: "Router", dependencies: ["AIOSCore", "ModelRuntime"]),
        .target(name: "Supervisor", dependencies: ["AIOSCore", "EventJournal", "ModelRuntime"]),
        .target(name: "CapabilityBroker", dependencies: ["AIOSCore", "EventJournal", "SecurityKernel", "ExecutionFabric"]),
        .target(name: "SecurityKernel", dependencies: ["AIOSCore"]),
        .target(name: "ExecutionFabric", dependencies: ["AIOSCore", "EventJournal", "ModelRuntime"]),
        .target(name: "ExpertRuntime", dependencies: ["AIOSCore"]),
        .target(name: "EvidenceEngine", dependencies: ["AIOSCore", "EventJournal", "ProjectKernel"]),
        .target(name: "ContextCompiler", dependencies: ["AIOSCore"]),
        .target(name: "DesktopShell", dependencies: ["AIOSCore", "EventJournal", "ProjectKernel"]),

        // Phase 2 — hybrid intelligence.
        .target(name: "ModelRuntime", dependencies: ["AIOSCore"], resources: [
            .copy("Resources/default-models.json"),
            .copy("Resources/HarnessProfiles/default-v1.json"),
        ]),
        .target(name: "MLXRuntime", dependencies: [
            "AIOSCore", "ModelRuntime",
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "Tokenizers", package: "swift-transformers"),
        ]),
        .target(name: "CloudRuntime", dependencies: ["AIOSCore", "ModelRuntime", "SecurityKernel"], resources: [
            .copy("Resources/zai-profile.json"),
        ]),
        .target(name: "EvaluationEngine", dependencies: ["AIOSCore", "EventJournal", "ModelRuntime"]),

        // Executables — workers and the app run out of the UI/host process.
        .executableTarget(name: "WorkRuntimeApp", dependencies: ["AIOSCore", "EventJournal", "DesktopShell"]),
        .executableTarget(name: "InferenceWorker", dependencies: ["AIOSCore", "ExecutionFabric", "ModelRuntime", "MLXRuntime"]),
        .executableTarget(name: "ToolWorker", dependencies: ["AIOSCore", "ExecutionFabric"]),
        .executableTarget(name: "ModelFetch", dependencies: ["AIOSCore", "ModelRuntime", "MLXRuntime"]),
        .executableTarget(name: "ProviderSetup", dependencies: ["AIOSCore", "ModelRuntime", "SecurityKernel", "CloudRuntime"]),

        // Tests
        .testTarget(name: "KernelTests", dependencies: ["AIOSCore", "EventJournal", "ProjectKernel", "EvidenceEngine", "EvaluationEngine", "Scheduler", "Router", "ExpertRuntime", "ContextCompiler", "DesktopShell", "ModelRuntime", "ExecutionFabric"]),
        .testTarget(name: "RecoveryTests", dependencies: ["AIOSCore", "EventJournal", "ProjectKernel", "ExecutionFabric", "Supervisor"]),
        .testTarget(name: "SecurityTests", dependencies: ["AIOSCore", "EventJournal", "SecurityKernel", "CapabilityBroker"]),
        .testTarget(name: "IntegrationTests", dependencies: ["AIOSCore", "EventJournal", "ProjectKernel", "SecurityKernel", "CapabilityBroker", "EvidenceEngine", "EvaluationEngine", "Supervisor", "ExecutionFabric", "Router", "ContextCompiler"]),
        .testTarget(name: "HybridTests", dependencies: ["AIOSCore", "EventJournal", "ProjectKernel", "SecurityKernel", "ExecutionFabric", "Supervisor", "Router", "ModelRuntime", "MLXRuntime", "CloudRuntime", "CapabilityBroker", "EvidenceEngine", "EvaluationEngine"]),
    ]
)
