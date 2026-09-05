import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel

private func seedScript(projectID: ProjectID) -> [EngineEvent] {
    let goal = GoalRevisionID()
    let plan = PlanRevisionID()
    let task = TaskID()
    let attempt = AttemptID()
    let wp = WorkPackageID()
    let action = ActionID()
    let worker = WorkerIdentity(workerID: "inference-1", model: "fixture-brain", runtime: .scripted, revision: "1")
    let request = ActionRequest(
        actionID: action, workPackageID: wp, requestedBy: .linus,
        capability: .modifyWorkspace, operation: "fs.write",
        target: "Sources/Parser/Lexer.swift", parameters: ["contents": .text("fix")],
        expectedEffect: "lexer fix", sideEffectClass: .local,
        reversibility: .reversible, idempotency: .idempotent,
        requiredPermission: .modifyWorkspace,
        preconditions: [Precondition(target: "Sources/Parser/Lexer.swift", contentHash: "aa")],
        verificationPlan: "swift test"
    )
    return [
        .projectOpened,
        .goalCreated(.init(goalRevisionID: goal, originalRequest: "Make the parser tests pass", objective: "Fix parser", acceptanceCriteria: ["swift test green"])),
        .planProposed(.init(planRevisionID: plan, goalRevisionID: goal, summary: "fix lexer then verify")),
        .taskCreated(.init(taskID: task, planRevisionID: plan, objective: "fix lexer", owner: .linus)),
        .taskStateChanged(.init(taskID: task, oldState: .pending, newState: .inProgress)),
        .attemptStarted(.init(attemptID: attempt, taskID: task, workPackageID: wp, worker: worker)),
        .actionRequested(.init(request: request)),
        .actionAuthorized(.init(actionID: action, authorizedScope: "workspace write")),
        .actionExecuted(.init(result: ActionResult(
            actionID: action, outcome: .succeeded,
            startedAt: Date(timeIntervalSinceReferenceDate: 0), endedAt: Date(timeIntervalSinceReferenceDate: 1),
            observedEffects: ["file written"]
        ))),
        .attemptEnded(.init(attemptID: attempt, taskID: task, outcome: .completed)),
        .verificationStarted(.init(taskID: task, requirement: "swift test green")),
        .verificationPassed(.init(taskID: task, requirement: "swift test green")),
    ]
}

private func replay(_ events: [EngineEvent], projectID: ProjectID = ProjectID()) -> ProjectState {
    var state = ProjectState(projectID: projectID)
    for (index, event) in events.enumerated() {
        state = Projection.apply(state, EventRecord(
            sequence: UInt64(index + 1), recordedAt: Date(), projectID: projectID, event: event
        ))
    }
    return state
}

@Test func replayBuildsExpectedStateFromScript() throws {
    let state = replay(seedScript(projectID: ProjectID()))

    #expect(state.warnings.isEmpty)
    #expect(state.tasks.count == 1)
    #expect(state.tasks.values.first?.state == .complete)
    #expect(state.attempts.values.first?.outcome == .completed)
    #expect(state.actions.count == 1)
    #expect(state.actions.values.first?.result?.outcome == .succeeded)
    #expect(state.activeGoalRevisionID != nil)
    #expect(state.activePlanRevisionID != nil)
    #expect(state.lastSequence == 12)
}

@Test func originalGoalIntentIsImmutableAcrossRevisions() throws {
    var events = seedScript(projectID: ProjectID())
    let originalGoal = try #require(events.compactMap { event -> GoalRevisionID? in
        if case .goalCreated(let p) = event { return p.goalRevisionID } else { return nil }
    }.first)
    let newRevision = GoalRevisionID()
    events.append(.goalRevised(.init(goalRevisionID: newRevision, previousRevisionID: originalGoal, reason: "user tightened acceptance")))

    let state = replay(events)

    let original = try #require(state.goals[originalGoal])
    let revised = try #require(state.goals[newRevision])
    #expect(revised.originalRequest == original.originalRequest)
    #expect(revised.originalRequest == "Make the parser tests pass")
    #expect(state.activeGoalRevisionID == newRevision)
    #expect(revised.revisionReason == "user tightened acceptance")
}

@Test func taskCannotReachCompleteViaStateChangeAlone() throws {
    // A worker self-reporting completion must not complete the task; only a
    // verificationPassed event may.
    let taskID = TaskID()
    let state = replay([
        .taskCreated(.init(taskID: taskID, planRevisionID: PlanRevisionID(), objective: "fix lexer", owner: .linus)),
        .taskStateChanged(.init(taskID: taskID, oldState: .pending, newState: .inProgress)),
        .taskStateChanged(.init(taskID: taskID, oldState: .inProgress, newState: .complete)),
    ])

    #expect(state.tasks[taskID]?.state == .inProgress)
    #expect(state.warnings.contains { $0.contains("Complete") })
}

@Test func unknownOutcomeBlocksAttemptUntilReconciled() throws {
    var events = seedScript(projectID: ProjectID())
    let attemptID = try #require(events.compactMap { event -> AttemptID? in
        if case .attemptStarted(let p) = event { return p.attemptID } else { return nil }
    }.first)
    let actionID = try #require(events.compactMap { event -> ActionID? in
        if case .actionRequested(let p) = event { return p.request.actionID } else { return nil }
    }.first)
    events.append(.actionExecuted(.init(result: ActionResult(
        actionID: actionID, outcome: .unknown,
        startedAt: Date(timeIntervalSinceReferenceDate: 2), endedAt: Date(timeIntervalSinceReferenceDate: 3),
        reconciliationRequired: true
    ))))

    var state = replay(events)
    #expect(state.attempts[attemptID]?.hasUnreconciledUnknownOutcome == true)

    state = Projection.apply(state, EventRecord(
        sequence: 100, recordedAt: Date(), projectID: state.projectID,
        event: .actionReconciled(.init(actionID: actionID, resolvedOutcome: .failed, note: "observed no effect via diff"))
    ))
    #expect(state.attempts[attemptID]?.hasUnreconciledUnknownOutcome == false)
}

@Test func replayEqualsSnapshotPlusTail() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-kernel-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let projectID = ProjectID()
    let store = try JournalStore(projectID: projectID, rootDirectory: root)

    let script = seedScript(projectID: projectID)
    for event in script {
        _ = try await store.append(event)
    }

    let midState = try Projection.replayAll(store)
    try Projection.saveSnapshot(midState, for: projectID, under: root)

    // More work lands after the snapshot.
    _ = try await store.append(.checkpointCreated(.init(checkpointID: "cp1", note: "after verification")))
    _ = try await store.append(.decisionRequested(.init(subject: "release", question: "ship now?", blocking: false)))

    let full = try Projection.replayAll(store)
    let hybrid = try Projection.loadUsingSnapshot(store)

    #expect(full == hybrid)
    #expect(full.tasks.values.first?.state == .complete)
    #expect(full.needsUser.count == 1)
}

@Test func foldIsTotalOnUnknownReferences() throws {
    let state = replay([
        .verificationPassed(.init(taskID: TaskID(), requirement: "nonexistent")),
        .attemptEnded(.init(attemptID: AttemptID(), taskID: TaskID(), outcome: .failed)),
    ])
    #expect(state.warnings.count == 2)
    #expect(state.tasks.isEmpty)
}
