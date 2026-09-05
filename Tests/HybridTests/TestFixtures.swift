import Foundation
import Testing
@testable import AIOSCore
@testable import ExecutionFabric

// Shared HybridTests fixtures. Previously `workerBinary()` was duplicated
// in 6 files, `makePackage()` in 2, and the cursor-loop in 3 — all
// consolidated here.

/// Resolves a built executable under `.build/debug/`.
func packageExecutable(_ name: String) throws -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // TestFixtures.swift
        .deletingLastPathComponent() // HybridTests/
        .deletingLastPathComponent() // Tests/
    let url = packageRoot.appendingPathComponent(".build/debug/\(name)")
    #expect(FileManager.default.fileExists(atPath: url.path), "missing executable: \(url.path)")
    return url
}

/// The InferenceWorker binary.
func workerBinary() throws -> URL {
    try packageExecutable("InferenceWorker")
}

/// A standard bounded work package for worker tests.
func makeWorkPackage(
    role: ExpertRole = .linus,
    objective: String = "fix the parser",
    attemptID: AttemptID = AttemptID()
) -> WorkPackage {
    WorkPackage(
        packageID: WorkPackageID(),
        projectID: ProjectID(),
        goalRevisionID: GoalRevisionID(),
        planRevisionID: PlanRevisionID(),
        taskID: TaskID(),
        attemptID: attemptID,
        role: role,
        taskContract: TaskContract(
            objective: objective,
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

/// Cursor-based event collector for a WorkerSession: call `drain()` in a
/// poll loop to process only NEW events (no double-processing on re-poll).
struct SessionEventCollector {
    private var cursor: Int

    init(session: WorkerSession) async {
        cursor = await session.eventHistory().count
    }

    /// Returns events appended since the last drain.
    mutating func drain(from session: WorkerSession) async -> [WorkerSession.Event] {
        let events = await session.eventHistory()
        guard cursor < events.count else { return [] }
        let new = Array(events[cursor...])
        cursor = events.count
        return Array(new)
    }
}
