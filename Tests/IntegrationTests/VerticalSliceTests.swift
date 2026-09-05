import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import SecurityKernel
@testable import CapabilityBroker
@testable import EvidenceEngine
@testable import EvaluationEngine
@testable import Supervisor
@testable import ExecutionFabric
@testable import Router
@testable import ExpertRuntime
@testable import ContextCompiler

// The Phase 1 vertical slice (PROJECT_GOAL.md): open a repository, state a
// goal, plan, contract, route to Linus, isolate a workspace, compile
// context, execute through the broker, verify mechanically, bind evidence to
// the exact artifact revision, independently review, complete only on
// verified evidence — and survive a worker crash plus an engine restart.
//
// The fixture's `run_checks.sh` is the mechanical check that stands in for
// `swift test` so the suite stays fast; the real test framework runs on this
// package itself.

private func makeFixture() throws -> URL {
    let fixture = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-fixture-\(UUID().uuidString)", isDirectory: true)
    let sources = fixture.appendingPathComponent("Sources/App", isDirectory: true)
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)

    try Data("""
    // Fixture app awaiting its fix.
    print("broken")
    """.utf8).write(to: sources.appendingPathComponent("main.swift"))

    let checks = fixture.appendingPathComponent("run_checks.sh")
    try Data("""
    #!/bin/sh
    # Mechanical check: the fix must introduce the FIX_MARKER constant.
    grep -q "FIX_MARKER" "Sources/App/main.swift" || exit 1
    echo "checks passed"
    """.utf8).write(to: checks)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: checks.path)
    return fixture
}

private func writeScenario(_ scenario: WorkerScenario) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-slice-\(UUID().uuidString).json")
    try JSONEncoder().encode(scenario).write(to: url)
    return url
}

private struct SliceEngine {
    let journal: JournalStore
    let broker: CapabilityBroker
    let recorder: EvidenceRecorder
    let evaluator: IndependentEvaluator
    let supervisor: Supervisor
    let policy: SecurityPolicy
    let workspace: URL

    /// Drives one attempt through the scripted worker: the worker proposes
    /// actions; the broker validates, authorizes, executes, and journals.
    func runAttempt(session: WorkerSession, package: WorkPackage, timeout: TimeInterval = 15) async throws -> WorkResult {
        try await session.sendWorkPackage(package)
        var collector = await SessionEventCollector(session: session)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let events = await collector.drain(from: session)
            for event in events {
                switch event {
                case .actionRequest(let request):
                    let result = await broker.execute(request, policy: policy)
                    try await session.sendActionResult(result)
                    if result.outcome == .rejected || result.outcome == .stalePrecondition {
                        Issue.record("broker refused an in-contract action: \(result.failureDetails ?? "")")
                    }
                case .workResult(let result):
                    return result
                case .crashed(let workerID):
                    throw WorkerCrashed(workerID: workerID)
                default:
                    continue
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw WorkerSession.TimeoutError()
    }

    struct WorkerCrashed: Error, CustomStringConvertible {
        var workerID: String
        var description: String { "worker \(workerID) crashed mid-attempt" }
    }
}

@Test func verticalSliceCompletesAndRecovers() async throws {
    // 1. Open an existing (fixture) repository and isolate a workspace copy.
    let fixture = try makeFixture()
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-slice-engine-\(UUID().uuidString)", isDirectory: true)
    let workspace = root.appendingPathComponent("worktree-1", isDirectory: true)
    try FileManager.default.createDirectory(at: workspace.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: fixture, to: workspace)
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: fixture) }

    let projectID = ProjectID()
    let journal = try JournalStore(projectID: projectID, rootDirectory: root)
    let broker = CapabilityBroker(journal: journal)
    let recorder = EvidenceRecorder(journal: journal)
    let evaluator = IndependentEvaluator(journal: journal)
    let supervisor = Supervisor(journal: journal)
    let policy = SecurityPolicy(
        workspaceRoots: [workspace.path],
        allowedCommands: ["/bin/sh", "/usr/bin/grep"],
        localOnly: true
    )
    let engine = SliceEngine(journal: journal, broker: broker, recorder: recorder, evaluator: evaluator, supervisor: supervisor, policy: policy, workspace: workspace)

    // 2. Goal with immutable original intent.
    let goal = GoalRevisionID()
    try await journal.append(.projectOpened)
    try await journal.append(.goalCreated(.init(
        goalRevisionID: goal,
        originalRequest: "Make the fixture app print its fixed marker instead of 'broken'",
        objective: "Fix main.swift and prove it with the mechanical check",
        acceptanceCriteria: ["run_checks.sh exits 0"]
    )))

    // 3. Plan + task contract.
    let plan = PlanRevisionID()
    let task = TaskID()
    try await journal.append(.planProposed(.init(planRevisionID: plan, goalRevisionID: goal, summary: "edit, verify, review")))
    let contract = TaskContract(
        objective: "Introduce FIX_MARKER in main.swift",
        inputs: [workspace.appendingPathComponent("Sources/App/main.swift").path],
        allowedScope: [
            workspace.appendingPathComponent("Sources", isDirectory: true).path,
            workspace.path, // verification commands run from the workspace root
        ],
        mustPreserve: ["fixture layout"],
        forbiddenScope: [(fixture).path],
        expectedOutputs: [ExpectedOutput(artifactKind: .fileOrDiff, description: "fixed main.swift")],
        verificationRequirements: [VerificationRequirement(description: "mechanical check passes", method: .deterministicCheck("run_checks"))],
        dependencyAssumptions: [],
        stalenessConditions: ["main.swift unchanged since validation"]
    )
    try await journal.append(.taskCreated(.init(taskID: task, planRevisionID: plan, objective: contract.objective, owner: .linus)))

    // 4. Route to Linus.
    let router = Router()
    let routing = router.decide(capabilities: [.modifyWorkspace], privacyPolicy: .localOnly, spendPolicy: SpendPolicy(), localRuntimeAvailable: true)
    #expect(routing.runtime != .cloudAPI)

    // 5-7. Attempt 1: crash mid-run, recover, then succeed on re-attempt.
    var state = try Projection.replayAll(journal)

    // Attempt 1 — the worker crashes mid-run.
    let attempt1 = AttemptID()
    let package1 = WorkPackage(
        packageID: WorkPackageID(), projectID: projectID, goalRevisionID: goal,
        planRevisionID: plan, taskID: task, attemptID: attempt1, role: .linus,
        taskContract: contract,
        contextBundle: ContextBundle(selections: [], tokenBudget: 100),
        capabilities: [.modifyWorkspace], executionTargets: [routing.topology],
        resourceBudget: ResourceBudget(maxMemoryGB: 1, maxComputeCores: 1),
        timeBudget: TimeBudget(timeoutSeconds: 60),
        privacyPolicy: .localOnly, spendPolicy: SpendPolicy(),
        expectedOutputs: contract.expectedOutputs,
        verificationRequirements: contract.verificationRequirements,
        handoffPolicy: .freshShiftWithHandoffPacket, failurePolicy: .retryIdempotentOnly,
        harnessProfile: HarnessProfileID(value: "default-v1")
    )
    try await journal.append(.taskStateChanged(.init(taskID: task, oldState: .pending, newState: .inProgress)))
    try await journal.append(.attemptStarted(.init(attemptID: attempt1, taskID: task, workPackageID: package1.packageID,
                                                    worker: WorkerIdentity(workerID: "inference-?", runtime: .scripted))))
    try await journal.append(.modelSelected(.init(attemptID: attempt1, runtime: routing.runtime, rationale: routing.rationale.joined(separator: "; "))))

    let crashScenario = try writeScenario(WorkerScenario(steps: [.sleepMs(200), .crash], heartbeatIntervalSeconds: 0.5))
    let session1 = WorkerSession(
        configuration: .init(executableURL: try packageExecutable("InferenceWorker"),
                             arguments: ["--scenario", crashScenario.path],
                             heartbeatTimeoutSeconds: 10),
        journal: journal
    )
    try await session1.start()
    do {
        _ = try await engine.runAttempt(session: session1, package: package1)
        Issue.record("attempt 1 should have crashed")
    } catch is SliceEngine.WorkerCrashed {
        // expected path
    }
    try await session1.terminate()
    try await journal.append(.attemptEnded(.init(attemptID: attempt1, taskID: task, outcome: .failed)))

    state = try Projection.replayAll(journal)
    #expect(state.attempts[attempt1]?.crashed == true)
    #expect(state.attempts[attempt1]?.outcome == .failed)

    // Attempt 2 — full success path.
    let attempt2 = AttemptID()
    let compiler = ContextCompiler()
    let contextBundle = compiler.compile(
        contract: contract,
        candidates: [ContextSelection(path: contract.inputs[0], reason: "contract input")],
        priorHandoff: nil,
        tokenBudget: 400
    )
    let package2 = WorkPackage(
        packageID: WorkPackageID(), projectID: projectID, goalRevisionID: goal,
        planRevisionID: plan, taskID: task, attemptID: attempt2, role: .linus,
        taskContract: contract, contextBundle: contextBundle,
        capabilities: [.modifyWorkspace], executionTargets: [routing.topology],
        resourceBudget: ResourceBudget(maxMemoryGB: 1, maxComputeCores: 1),
        timeBudget: TimeBudget(timeoutSeconds: 60),
        privacyPolicy: .localOnly, spendPolicy: SpendPolicy(),
        expectedOutputs: contract.expectedOutputs,
        verificationRequirements: contract.verificationRequirements,
        handoffPolicy: .freshShiftWithHandoffPacket, failurePolicy: .retryIdempotentOnly,
        harnessProfile: HarnessProfileID(value: "default-v1")
    )
    try await journal.append(.attemptStarted(.init(attemptID: attempt2, taskID: task, workPackageID: package2.packageID,
                                                    worker: WorkerIdentity(workerID: "inference-2", runtime: .scripted))))
    try await journal.append(.modelSelected(.init(attemptID: attempt2, runtime: routing.runtime, rationale: routing.rationale.joined(separator: "; "))))
    try await journal.append(.contextCompiled(.init(attemptID: attempt2, bundle: contextBundle)))
    try await journal.append(.workerRecovered(.init(workerID: "inference-2", attemptID: attempt2, strategy: "retry from task checkpoint after crash")))

    let fixContents = """
    // Fixture app fixed.
    let FIX_MARKER = "fixed"
    print(FIX_MARKER)
    """
    let scenario2 = try writeScenario(WorkerScenario(steps: [
        .action(.init(operation: "fs.write",
                      target: workspace.appendingPathComponent("Sources/App/main.swift").path,
                      contents: fixContents,
                      expectedEffect: "FIX_MARKER introduced",
                      verificationPlan: "run_checks.sh")),
        .finish(.init(status: "COMPLETED", claims: [["edit applied", "EXPERT_JUDGMENT"]], summary: "fix written"))
    ], heartbeatIntervalSeconds: 0.5))
    let session2 = WorkerSession(
        configuration: .init(executableURL: try packageExecutable("InferenceWorker"),
                             arguments: ["--scenario", scenario2.path],
                             heartbeatTimeoutSeconds: 10),
        journal: journal
    )
    try await session2.start()
    let workResult = try await engine.runAttempt(session: session2, package: package2)
    try await session2.terminate()
    try await journal.append(.attemptEnded(.init(attemptID: attempt2, taskID: task, outcome: workResult.status)))

    #expect(workResult.status == .completed)
    #expect(workResult.attemptID == attempt2)

    // Engine restart mid-goal: state rebuilds purely from the journal.
    state = try Projection.loadUsingSnapshot(try JournalStore(projectID: projectID, rootDirectory: root))
    #expect(state.tasks[task]?.state == .inProgress)
    #expect(state.attempts[attempt2]?.phase == .ended)

    // 8. Run the mechanical check through the broker (typed action).
    let checkTarget = workspace.appendingPathComponent("Sources/App/main.swift").path
    let checkRequest = ActionRequest(
        actionID: ActionID(), workPackageID: package2.packageID, requestedBy: .linus,
        capability: .modifyWorkspace, operation: "shell.run", target: "/bin/sh",
        parameters: ["arguments": .text("run_checks.sh"), "cwd": .text(workspace.path)],
        expectedEffect: "mechanical check exits 0",
        sideEffectClass: .local, reversibility: .reversible, idempotency: .idempotent,
        requiredPermission: .modifyWorkspace, verificationPlan: "exit code"
    )
    let checkResult = await broker.execute(checkRequest, policy: policy)
    #expect(checkResult.outcome == .succeeded, "mechanical check failed: \(checkResult.failureDetails ?? "")")

    // 9. Evidence bound to the exact artifact revision (content hash).
    let artifactID = ArtifactID()
    let revision = CapabilityBroker.contentHash(at: checkTarget)
    try await recorder.recordArtifact(artifactID: artifactID, kind: .fileOrDiff, path: checkTarget, revision: revision, contentHash: revision)
    let evidence = Evidence(
        evidenceID: EvidenceID(), projectID: projectID,
        subject: "mechanical check",
        proposition: "run_checks.sh exits 0 at revision \(revision.prefix(8))",
        claimType: .verifiedFact, sourceType: .command,
        sourceReference: "/bin/sh run_checks.sh",
        producedBy: WorkerIdentity(workerID: "broker", runtime: .deterministic),
        observedAt: Date(),
        verificationMethod: .deterministicCheck("run_checks"),
        strength: .mechanicalCheck,
        artifactRevisionRefs: [ArtifactRevisionRef(artifactID: artifactID, revision: revision)]
    )
    try await recorder.record(evidence: evidence)

    // 10-11. Independent review; completion only if the contract verifies.
    let verdict = try await evaluator.evaluate(
        taskID: task,
        requirements: contract.verificationRequirements,
        evidence: [evidence],
        result: workResult
    )
    #expect(verdict.decision == .passed)

    // Supervisor saw only successes in this endgame.
    let directive = await supervisor.inspect(checkResult, for: checkRequest, contract: contract)
    #expect(directive == .proceed)

    // 12. Projection drives cards/timeline: task complete, goal completed.
    try await journal.append(.goalCompleted(.init(goalRevisionID: goal)))
    state = try Projection.replayAll(journal)
    #expect(state.tasks[task]?.state == .complete)
    #expect(state.goals[goal]?.completed == true)
    #expect(state.goals[goal]?.originalRequest.contains("fixed marker") == true)
    #expect(state.evidence[evidence.evidenceID]?.status == .valid)
    #expect(state.attempts[attempt1]?.crashed == true)
    #expect(state.attempts[attempt2]?.recovered == true)

    // The journal contains the full audit trail.
    let replay = try JournalReader.readAllEvents(at: journal.journalFileURL)
    let kinds = replay.records.map { record -> String in
        Mirror(reflecting: record.event).children.first?.label ?? "projectOpened"
    }
    #expect(replay.records.count >= 20)
    #expect(kinds.filter { $0 == "workerCrashed" }.count == 1)
    #expect(kinds.filter { $0 == "workerRecovered" }.count == 1)
    #expect(kinds.filter { $0 == "verificationPassed" }.count == 1)
}

@Test func sherlockScenarioSeparatesFactsFromJudgments() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-sherlock-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    let recorder = EvidenceRecorder(journal: journal)
    let evaluator = IndependentEvaluator(journal: journal)

    // A bounded research task: findings artifact + typed claims.
    let task = TaskID()
    try await journal.append(.taskCreated(.init(taskID: task, planRevisionID: PlanRevisionID(),
                                                 objective: "verify the release date claim", owner: .sherlock)))
    try await journal.append(.taskStateChanged(.init(taskID: task, oldState: .pending, newState: .inProgress)))

    let result = WorkResult(
        packageID: WorkPackageID(), attemptID: AttemptID(),
        worker: WorkerIdentity(workerID: "inference-s", runtime: .scripted),
        status: .completed,
        claims: [
            Claim(statement: "Vendor changelog lists 2026-08-14", statementType: .observedFact),
            Claim(statement: "The changelog date is credible", statementType: .expertJudgment),
        ]
    )
    let artifactID = ArtifactID()
    try await recorder.recordArtifact(artifactID: artifactID, kind: .report, path: "ws/findings.md",
                                      revision: "r1", contentHash: "h1")
    let sourceEvidence = Evidence(
        evidenceID: EvidenceID(), projectID: journal.projectID,
        subject: "vendor changelog",
        proposition: "changelog entry dated 2026-08-14 exists",
        claimType: .verifiedFact, sourceType: .external,
        sourceReference: "changelog.html#entry",
        observedAt: Date(),
        verificationMethod: .independentReview,
        strength: .primarySource,
        artifactRevisionRefs: [ArtifactRevisionRef(artifactID: artifactID, revision: "r1")]
    )
    try await recorder.record(evidence: sourceEvidence)

    // Claims are typed: facts and judgments are distinct semantic classes.
    let facts = result.claims.filter { $0.statementType == .observedFact }
    let judgments = result.claims.filter { $0.statementType == .expertJudgment }
    #expect(facts.count == 1)
    #expect(judgments.count == 1)

    let verdict = try await evaluator.evaluate(
        taskID: task,
        requirements: [VerificationRequirement(description: "independent evidence coverage", method: .independentReview)],
        evidence: [sourceEvidence],
        result: result
    )
    #expect(verdict.decision == .passed)
    let state = try Projection.replayAll(journal)
    #expect(state.tasks[task]?.state == .complete)
}
