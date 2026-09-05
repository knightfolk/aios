import Foundation
import Testing
@testable import AIOSCore
@testable import ExecutionFabric

// Shared RecoveryTests fixtures (extracted from WorkerBoundaryTests).

func packageExecutable(_ name: String) throws -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = packageRoot.appendingPathComponent(".build/debug/\(name)")
    #expect(FileManager.default.fileExists(atPath: url.path), "missing executable: \(url.path)")
    return url
}

func makeWorkPackage() -> WorkPackage {
    WorkPackage(
        packageID: WorkPackageID(),
        projectID: ProjectID(),
        goalRevisionID: GoalRevisionID(),
        planRevisionID: PlanRevisionID(),
        taskID: TaskID(),
        attemptID: AttemptID(),
        role: .linus,
        taskContract: TaskContract(
            objective: "fix lexer",
            inputs: [], allowedScope: [], mustPreserve: [], forbiddenScope: [],
            expectedOutputs: [], verificationRequirements: [],
            dependencyAssumptions: [], stalenessConditions: []
        ),
        contextBundle: ContextBundle(selections: [], tokenBudget: 1000),
        capabilities: [.modifyWorkspace],
        executionTargets: [.singleAgent],
        resourceBudget: ResourceBudget(),
        timeBudget: TimeBudget(),
        privacyPolicy: .localOnly,
        spendPolicy: SpendPolicy(),
        expectedOutputs: [],
        verificationRequirements: [],
        handoffPolicy: .continuation,
        failurePolicy: .retryIdempotentOnly,
        harnessProfile: HarnessProfileID(value: "default-v1")
    )
}
