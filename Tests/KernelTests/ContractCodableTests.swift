import Foundation
import Testing
@testable import AIOSCore

// MARK: - Identifiers

@Test func typedIdentifiersRoundTripThroughCodable() throws {
    let original = TaskID(rawValue: UUID())
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TaskID.self, from: data)
    #expect(decoded == original)
}

@Test func typedIdentifierDescribesItsKind() {
    let fixed = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let id = EvidenceID(rawValue: fixed)
    #expect(String(describing: id).contains("EvidenceID"))
    #expect(String(describing: id).contains(fixed.uuidString))
}

// MARK: - Wire-stable enum raw values

@Test func actionOutcomeRawValuesAreStable() {
    #expect(ActionOutcome.succeeded.rawValue == "SUCCEEDED")
    #expect(ActionOutcome.failed.rawValue == "FAILED")
    #expect(ActionOutcome.partiallySucceeded.rawValue == "PARTIALLY_SUCCEEDED")
    #expect(ActionOutcome.cancelled.rawValue == "CANCELLED")
    #expect(ActionOutcome.timedOut.rawValue == "TIMED_OUT")
    #expect(ActionOutcome.unknown.rawValue == "UNKNOWN")
    #expect(ActionOutcome.rejected.rawValue == "REJECTED")
    #expect(ActionOutcome.stalePrecondition.rawValue == "STALE_PRECONDITION")
}

@Test func evidenceEnumsRawValuesAreStable() {
    #expect(EvidenceStrength.mechanicalCheck.rawValue == "MECHANICAL_CHECK")
    #expect(EvidenceStrength.independentReview.rawValue == "INDEPENDENT_REVIEW")
    #expect(EvidenceStatus.stale.rawValue == "STALE")
    #expect(EvidenceStatus.invalidated.rawValue == "INVALIDATED")
    #expect(EvidenceStatus.inconclusive.rawValue == "INCONCLUSIVE")
    #expect(EvidenceStatus.superseded.rawValue == "SUPERSEDED")
}

@Test func semanticStatementTypesMatchDocs05() {
    #expect(SemanticStatementType.allCases.count == 8)
    #expect(SemanticStatementType.userRequirement.rawValue == "USER_REQUIREMENT")
    #expect(SemanticStatementType.generatedContent.rawValue == "GENERATED_CONTENT")
}

@Test func executionTopologyCoversAllTen() {
    #expect(ExecutionTopology.allCases.count == 10)
    #expect(ExecutionTopology.computerUse.rawValue == "COMPUTER_USE")
    #expect(ExecutionTopology.mediaPipeline.rawValue == "MEDIA_PIPELINE")
}

@Test func runtimeKindDeclaresScriptedHonestly() {
    #expect(RuntimeKind.scripted.rawValue == "SCRIPTED")
}

// MARK: - Contract round-trips

@Test func workPackageRoundTrips() throws {
    let value = WorkPackage.makeForTesting()
    let decoded = try roundTrip(value)
    #expect(decoded == value)
}

@Test func taskContractRoundTrips() throws {
    let value = TaskContract.makeForTesting()
    let decoded = try roundTrip(value)
    #expect(decoded == value)
}

@Test func workResultRoundTrips() throws {
    let value = WorkResult.makeForTesting()
    let decoded = try roundTrip(value)
    #expect(decoded == value)
}

@Test func actionRequestRoundTrips() throws {
    let value = ActionRequest.makeForTesting()
    let decoded = try roundTrip(value)
    #expect(decoded == value)
}

@Test func actionResultRoundTrips() throws {
    let value = ActionResult.makeForTesting()
    let decoded = try roundTrip(value)
    #expect(decoded == value)
}

@Test func evidenceRoundTrips() throws {
    let value = Evidence.makeForTesting()
    let decoded = try roundTrip(value)
    #expect(decoded == value)
}

@Test func handoffRoundTrips() throws {
    let value = Handoff.makeForTesting()
    let decoded = try roundTrip(value)
    #expect(decoded == value)
}

// MARK: - Golden JSON decode (wire stability)

@Test func workPackageDecodesFromGoldenJSON() throws {
    let golden = """
    {
      "schemaVersion": 1,
      "packageID": "00000000-0000-0000-0000-0000000000A1",
      "projectID": "00000000-0000-0000-0000-0000000000B2",
      "goalRevisionID": "00000000-0000-0000-0000-0000000000C3",
      "planRevisionID": "00000000-0000-0000-0000-0000000000D4",
      "taskID": "00000000-0000-0000-0000-0000000000E5",
      "attemptID": "00000000-0000-0000-0000-0000000000F6",
      "role": "linus",
      "taskContract": {
        "schemaVersion": 1,
        "objective": "Fix the failing parser test",
        "inputs": [],
        "allowedScope": ["Sources/Parser/"],
        "mustPreserve": ["public API"],
        "forbiddenScope": ["Package.swift"],
        "expectedOutputs": [{"artifactKind": "FILE_OR_DIFF", "description": "parser fix"}],
        "verificationRequirements": [
          {"description": "test suite passes", "method": {"testsPass": {}}}
        ],
        "dependencyAssumptions": [],
        "stalenessConditions": ["parser files unchanged since validation"]
      },
      "contextBundle": {"selections": [], "tokenBudget": 8000},
      "capabilities": ["MODIFY_WORKSPACE"],
      "executionTargets": ["SINGLE_AGENT"],
      "resourceBudget": {"maxMemoryGB": 4, "maxComputeCores": 2},
      "timeBudget": {"timeoutSeconds": 600},
      "privacyPolicy": "LOCAL_ONLY",
      "spendPolicy": {"maxSpendUSD": 0, "allowPaidCredits": false},
      "expectedOutputs": [{"artifactKind": "FILE_OR_DIFF", "description": "parser fix"}],
      "verificationRequirements": [
        {"description": "test suite passes", "method": {"testsPass": {}}}
      ],
      "handoffPolicy": "FRESH_SHIFT_WITH_HANDOFF_PACKET",
      "failurePolicy": "RETRY_IDEMPOTENT_ONLY",
      "harnessProfile": {"value": "default-v1"}
    }
    """
    let decoded = try JSONDecoder().decode(WorkPackage.self, from: Data(golden.utf8))
    #expect(decoded.schemaVersion == 1)
    #expect(decoded.role == .linus)
    #expect(decoded.privacyPolicy == .localOnly)
    #expect(decoded.capabilities == [.modifyWorkspace])
    #expect(decoded.taskContract.allowedScope == ["Sources/Parser/"])
    #expect(decoded.taskContract.verificationRequirements.first?.method == .testsPass)
}

@Test func actionResultDecodesFromGoldenJSON() throws {
    let golden = """
    {
      "schemaVersion": 1,
      "actionID": "00000000-0000-0000-0000-000000000011",
      "outcome": "UNKNOWN",
      "startedAt": 0,
      "endedAt": 5,
      "observedEffects": ["process exited without confirmation"],
      "artifacts": [],
      "stdoutReference": null,
      "stderrReference": "logs/stderr-1.txt",
      "verificationResults": [],
      "stateBeforeReference": null,
      "stateAfterReference": null,
      "reconciliationRequired": true,
      "failureDetails": "connection lost after send"
    }
    """
    let decoded = try JSONDecoder().decode(ActionResult.self, from: Data(golden.utf8))
    #expect(decoded.outcome == .unknown)
    #expect(decoded.reconciliationRequired == true)
    #expect(decoded.stderrReference == "logs/stderr-1.txt")
}

@Test func evidenceDecodesFromGoldenJSON() throws {
    let golden = """
    {
      "schemaVersion": 1,
      "evidenceID": "00000000-0000-0000-0000-000000000021",
      "projectID": "00000000-0000-0000-0000-0000000000B2",
      "subject": "parser test suite",
      "proposition": "All parser tests pass at artifact revision r3",
      "claimType": "VERIFIED_FACT",
      "sourceType": "COMMAND",
      "sourceReference": "swift test --filter ParserTests",
      "producedBy": {
        "workerID": "tool-worker-1",
        "model": null,
        "runtime": "SCRIPTED",
        "revision": null
      },
      "observedAt": 100,
      "verificationMethod": {"testsPass": {}},
      "strength": "MECHANICAL_CHECK",
      "artifactRevisionRefs": [{"artifactID": "00000000-0000-0000-0000-000000000031", "revision": "r3"}],
      "dependencies": [],
      "invalidatedBy": [],
      "status": "VALID"
    }
    """
    let decoded = try JSONDecoder().decode(Evidence.self, from: Data(golden.utf8))
    #expect(decoded.claimType == .verifiedFact)
    #expect(decoded.strength == .mechanicalCheck)
    #expect(decoded.producedBy?.runtime == .scripted)
    #expect(decoded.artifactRevisionRefs == [ArtifactRevisionRef(artifactID: ArtifactID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!), revision: "r3")])
}

// MARK: - Helpers

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let encoder = JSONEncoder()
    let data = try encoder.encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}

// MARK: - Test factories (test-target only; product module ships no test doubles)

extension WorkPackage {
    static func makeForTesting() -> WorkPackage {
        WorkPackage(
            packageID: WorkPackageID(),
            projectID: ProjectID(),
            goalRevisionID: GoalRevisionID(),
            planRevisionID: PlanRevisionID(),
            taskID: TaskID(),
            attemptID: AttemptID(),
            role: .sherlock,
            taskContract: .makeForTesting(),
            contextBundle: ContextBundle(selections: [ContextSelection(path: "docs/report.md", reason: "primary source")], tokenBudget: 4096),
            capabilities: [.observe, .modifyWorkspace],
            executionTargets: [.singleAgent],
            resourceBudget: ResourceBudget(maxMemoryGB: 8, maxComputeCores: 4),
            timeBudget: TimeBudget(timeoutSeconds: 300, deadline: nil),
            privacyPolicy: .localOnly,
            spendPolicy: SpendPolicy(maxSpendUSD: 0, allowPaidCredits: false),
            expectedOutputs: [ExpectedOutput(artifactKind: .report, description: "findings report")],
            verificationRequirements: [VerificationRequirement(description: "independent review", method: .independentReview)],
            handoffPolicy: .continuation,
            failurePolicy: .retryIdempotentOnly,
            harnessProfile: HarnessProfileID(value: "default-v1")
        )
    }
}

extension TaskContract {
    static func makeForTesting() -> TaskContract {
        TaskContract(
            objective: "Investigate the flaky test",
            inputs: ["Tests/Flaky/"],
            allowedScope: ["Tests/Flaky/"],
            mustPreserve: ["test independence"],
            forbiddenScope: ["Package.swift"],
            expectedOutputs: [ExpectedOutput(artifactKind: .report, description: "root cause")],
            verificationRequirements: [VerificationRequirement(description: "suite passes", method: .testsPass)],
            dependencyAssumptions: ["CI matches local"],
            stalenessConditions: ["no edits under Tests/Flaky/ since validation"]
        )
    }
}

extension WorkResult {
    static func makeForTesting() -> WorkResult {
        WorkResult(
            packageID: WorkPackageID(),
            attemptID: AttemptID(),
            worker: WorkerIdentity(workerID: "inference-worker-1", model: "fixture-brain", runtime: .scripted, revision: "1"),
            status: .completed,
            artifacts: [ArtifactID()],
            claims: [Claim(statement: "root cause identified", statementType: .expertJudgment)],
            evidenceRefs: [EvidenceID()],
            actionRequests: [ActionID()],
            completedActionRefs: [ActionID()],
            discoveredIssues: ["race in setup"],
            unresolvedAssumptions: ["timer precision"],
            blockers: [],
            recommendedNextSteps: ["retry with serial setup"],
            handoff: .makeForTesting()
        )
    }
}

extension ActionRequest {
    static func makeForTesting() -> ActionRequest {
        ActionRequest(
            actionID: ActionID(),
            workPackageID: WorkPackageID(),
            requestedBy: .linus,
            capability: .modifyWorkspace,
            operation: "fs.write",
            target: "Sources/Parser/Lexer.swift",
            parameters: ["contents": .text("let x = 1")],
            expectedEffect: "lexer handles newline in string literal",
            sideEffectClass: .local,
            reversibility: .reversible,
            idempotency: .idempotent,
            requiredPermission: .modifyWorkspace,
            preconditions: [Precondition(target: "Sources/Parser/Lexer.swift", contentHash: "abc123")],
            verificationPlan: "run swift test --filter LexerTests",
            timeout: 30
        )
    }
}

extension ActionResult {
    static func makeForTesting() -> ActionResult {
        ActionResult(
            actionID: ActionID(),
            outcome: .succeeded,
            startedAt: Date(timeIntervalSinceReferenceDate: 0),
            endedAt: Date(timeIntervalSinceReferenceDate: 5),
            observedEffects: ["file written"],
            artifacts: [ArtifactID()],
            stdoutReference: "logs/out-1.txt",
            stderrReference: nil,
            verificationResults: [VerificationResult(requirement: "file compiles", passed: true, detail: "no diagnostics")],
            stateBeforeReference: "snap/before-1",
            stateAfterReference: "snap/after-1",
            reconciliationRequired: false,
            failureDetails: nil
        )
    }
}

extension Evidence {
    static func makeForTesting() -> Evidence {
        Evidence(
            evidenceID: EvidenceID(),
            projectID: ProjectID(),
            subject: "parser test suite",
            proposition: "All parser tests pass at revision r1",
            claimType: .verifiedFact,
            sourceType: .command,
            sourceReference: "swift test --filter ParserTests",
            producedBy: WorkerIdentity(workerID: "tool-worker-1", model: nil, runtime: .deterministic, revision: nil),
            observedAt: Date(timeIntervalSinceReferenceDate: 100),
            verificationMethod: .testsPass,
            strength: .mechanicalCheck,
            artifactRevisionRefs: [ArtifactRevisionRef(artifactID: ArtifactID(), revision: "r1")],
            dependencies: [],
            invalidatedBy: [],
            status: .valid
        )
    }
}

extension Handoff {
    static func makeForTesting() -> Handoff {
        Handoff(
            task: "investigate flaky test",
            currentState: "root cause found, fix not applied",
            artifactsChanged: [ArtifactID()],
            verifiedFacts: ["failure is order-dependent"],
            unverifiedAssumptions: ["CI scheduler behaves like local"],
            failedApproaches: ["adding sleep to setup"],
            blockers: [],
            recommendedNextAction: "serialize setup",
            evidenceRefs: [EvidenceID()]
        )
    }
}
