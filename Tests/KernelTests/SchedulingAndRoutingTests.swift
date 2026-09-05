import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import Scheduler
@testable import Router
@testable import ExpertRuntime
@testable import ContextCompiler

// MARK: - Scheduler

@Test func schedulerAdmitsDependencyFreeWorkFirst() {
    let scheduler = Scheduler(configuration: .init(maxConcurrentAttempts: 4, availableMemoryGB: 32, availableComputeCores: 8))
    let a = Scheduler.WorkOrder(taskID: TaskID(), dependencies: [], resourceCost: ResourceBudget(maxMemoryGB: 2, maxComputeCores: 1), priority: 2)
    let b = Scheduler.WorkOrder(taskID: TaskID(), dependencies: [a.taskID], resourceCost: ResourceBudget(maxMemoryGB: 2, maxComputeCores: 1), priority: 1)
    let c = Scheduler.WorkOrder(taskID: TaskID(), dependencies: [], resourceCost: ResourceBudget(maxMemoryGB: 2, maxComputeCores: 1), priority: 1)

    let admitted = scheduler.admit(pending: [b, c, a], running: [])
    #expect(Set(admitted.map(\.taskID)) == Set([a.taskID, c.taskID]))
}

@Test func schedulerRespectsConcurrencyAndMemory() {
    let scheduler = Scheduler(configuration: .init(maxConcurrentAttempts: 2, availableMemoryGB: 4, availableComputeCores: 8))
    let heavy = Scheduler.WorkOrder(taskID: TaskID(), dependencies: [], resourceCost: ResourceBudget(maxMemoryGB: 3, maxComputeCores: 1), priority: 3)
    let light1 = Scheduler.WorkOrder(taskID: TaskID(), dependencies: [], resourceCost: ResourceBudget(maxMemoryGB: 1, maxComputeCores: 1), priority: 2)
    let light2 = Scheduler.WorkOrder(taskID: TaskID(), dependencies: [], resourceCost: ResourceBudget(maxMemoryGB: 1, maxComputeCores: 1), priority: 1)

    // One heavy attempt is already running: 1 GB headroom, one slot free.
    let admitted = scheduler.admit(pending: [heavy, light1, light2], running: [heavy])
    #expect(admitted.count == 1)
    #expect(admitted.first?.taskID == light1.taskID)
}

// MARK: - Router

@Test func routerNeverSelectsCloudUnderLocalOnlyOrZeroBudget() {
    let router = Router()
    let localOnly = router.decide(
        capabilities: [.modifyWorkspace], privacyPolicy: .localOnly,
        spendPolicy: SpendPolicy(maxSpendUSD: 100, allowPaidCredits: true),
        localRuntimeAvailable: true
    )
    #expect(localOnly.runtime != .cloudAPI)
    #expect(!localOnly.rationale.isEmpty)

    let zeroBudget = router.decide(
        capabilities: [.modifyWorkspace], privacyPolicy: .hybridAllowed,
        spendPolicy: SpendPolicy(maxSpendUSD: 0, allowPaidCredits: false),
        localRuntimeAvailable: true
    )
    #expect(zeroBudget.runtime != .cloudAPI)
    #expect(zeroBudget.rationale.contains { $0.contains("budget") })
}

@Test func routerExplainsItsChoice() {
    let router = Router()
    let decision = router.decide(
        capabilities: [.observe], privacyPolicy: .localOnly,
        spendPolicy: SpendPolicy(), localRuntimeAvailable: true
    )
    #expect(!decision.rationale.isEmpty)
    #expect(decision.topology == .singleAgent || decision.topology == .direct)
}

// MARK: - ExpertRuntime

@Test func permanentTeamHasSevenStableMembers() {
    let team = ExpertTeam.permanentTeam()
    #expect(team.count == 7)
    let roles = Set(team.map(\.role))
    #expect(roles.contains(.linus))
    #expect(roles.contains(.chloe))
    #expect(roles.contains(.concierge))
    #expect(team.allSatisfy { !$0.displayName.isEmpty })
}

@Test func expertIdentityIsIndependentOfRuntime() throws {
    // Swap the worker runtime under one expert: the expert ownership of the
    // task never changes, and only a ModelSelected event appears.
    let taskID = TaskID()
    let attemptID = AttemptID()
    let projectID = ProjectID()
    var state = ProjectState(projectID: projectID)
    let events: [EngineEvent] = [
        .taskCreated(.init(taskID: taskID, planRevisionID: PlanRevisionID(), objective: "fix", owner: .linus)),
        .attemptStarted(.init(attemptID: attemptID, taskID: taskID, workPackageID: WorkPackageID(),
                              worker: WorkerIdentity(workerID: "w1", runtime: .scripted))),
        .modelSelected(.init(attemptID: attemptID, runtime: .mlx, rationale: "local model now available")),
        .modelSelected(.init(attemptID: attemptID, runtime: .scripted, rationale: "fell back to scripted runtime")),
    ]
    for (index, event) in events.enumerated() {
        state = Projection.apply(state, EventRecord(sequence: UInt64(index + 1), recordedAt: Date(), projectID: projectID, event: event))
    }
    #expect(state.tasks[taskID]?.owner == .linus)
    #expect(state.attempts[attemptID]?.modelSelection?.runtime == .scripted)
    #expect(state.attempts[attemptID]?.worker?.runtime == .scripted)
}

// MARK: - ContextCompiler

@Test func contextCompilerRespectsTokenBudget() {
    let compiler = ContextCompiler()
    let big = String(repeating: "a", count: 4000) // ~1000 estimated tokens
    let selections = (0..<5).map { index in
        ContextSelection(path: "ws/file\(index).txt", reason: big)
    }
    let bundle = compiler.compile(
        contract: TaskContract(objective: "fix", inputs: ["ws/file0.txt"], allowedScope: [], mustPreserve: [], forbiddenScope: [], expectedOutputs: [], verificationRequirements: [], dependencyAssumptions: [], stalenessConditions: []),
        candidates: selections,
        priorHandoff: nil,
        tokenBudget: 1500
    )
    let estimated = ContextCompiler.estimatedTokens(in: bundle)
    #expect(estimated <= 1500)
    #expect(!bundle.selections.isEmpty)
}

@Test func contextCompilerPrioritizesContractInputs() {
    let compiler = ContextCompiler()
    let contractInput = ContextSelection(path: "ws/important.swift", reason: String(repeating: "b", count: 2000))
    let filler = ContextSelection(path: "ws/filler.txt", reason: String(repeating: "c", count: 2000))
    let bundle = compiler.compile(
        contract: TaskContract(objective: "fix", inputs: ["ws/important.swift"], allowedScope: [], mustPreserve: [], forbiddenScope: [], expectedOutputs: [], verificationRequirements: [], dependencyAssumptions: [], stalenessConditions: []),
        candidates: [filler, contractInput],
        priorHandoff: nil,
        tokenBudget: 700
    )
    #expect(bundle.selections.first?.path == "ws/important.swift")
}
