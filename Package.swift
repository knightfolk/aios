// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "AIOS",
    platforms: [.macOS(.v15)],
    targets: [
        // Libraries — authoritative state, security, execution stay in separate modules.
        .target(name: "AIOSCore"),
        .target(name: "EventJournal", dependencies: ["AIOSCore"]),
        .target(name: "ProjectKernel", dependencies: ["AIOSCore", "EventJournal"]),
        .target(name: "Scheduler", dependencies: ["AIOSCore"]),
        .target(name: "Router", dependencies: ["AIOSCore"]),
        .target(name: "Supervisor", dependencies: ["AIOSCore", "EventJournal"]),
        .target(name: "CapabilityBroker", dependencies: ["AIOSCore", "EventJournal", "SecurityKernel", "ExecutionFabric"]),
        .target(name: "SecurityKernel", dependencies: ["AIOSCore"]),
        .target(name: "ExecutionFabric", dependencies: ["AIOSCore", "EventJournal"]),
        .target(name: "ExpertRuntime", dependencies: ["AIOSCore"]),
        .target(name: "EvidenceEngine", dependencies: ["AIOSCore", "EventJournal", "ProjectKernel"]),
        .target(name: "ContextCompiler", dependencies: ["AIOSCore"]),
        .target(name: "EvaluationEngine", dependencies: ["AIOSCore", "EventJournal"]),

        // Executables — workers and the app run out of the UI/host process.
        .executableTarget(name: "WorkRuntimeApp", dependencies: ["AIOSCore"]),
        .executableTarget(name: "InferenceWorker", dependencies: ["AIOSCore", "ExecutionFabric"]),
        .executableTarget(name: "ToolWorker", dependencies: ["AIOSCore", "ExecutionFabric"]),

        // Tests
        .testTarget(name: "KernelTests", dependencies: ["AIOSCore", "EventJournal", "ProjectKernel", "EvidenceEngine", "EvaluationEngine", "Scheduler", "Router", "ExpertRuntime", "ContextCompiler"]),
        .testTarget(name: "RecoveryTests", dependencies: ["AIOSCore", "EventJournal", "ProjectKernel", "ExecutionFabric", "Supervisor"]),
        .testTarget(name: "SecurityTests", dependencies: ["AIOSCore", "EventJournal", "SecurityKernel", "CapabilityBroker"]),
        .testTarget(name: "IntegrationTests", dependencies: ["AIOSCore", "EventJournal", "ProjectKernel", "SecurityKernel", "CapabilityBroker", "EvidenceEngine", "EvaluationEngine", "Supervisor", "ExecutionFabric", "Router", "ContextCompiler"]),
    ]
)
