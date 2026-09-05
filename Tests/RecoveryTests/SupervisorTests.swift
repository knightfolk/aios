import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import Supervisor

private func makeSupervisor(strikeLimit: Int = 3, maxSpend: Double = 0) throws -> (Supervisor, JournalStore, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-supervisor-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    let supervisor = Supervisor(
        configuration: .init(equivalentFailureStrikeLimit: strikeLimit, maxSpendUSD: maxSpend),
        journal: journal
    )
    return (supervisor, journal, root)
}

private func failedResult(actionID: ActionID = ActionID(), outcome: ActionOutcome = .failed) -> ActionResult {
    ActionResult(
        actionID: actionID, outcome: outcome,
        startedAt: Date(), endedAt: Date(),
        failureDetails: "boom"
    )
}

private func request(operation: String, target: String) -> ActionRequest {
    ActionRequest(
        actionID: ActionID(), workPackageID: WorkPackageID(), requestedBy: .linus,
        capability: .modifyWorkspace, operation: operation, target: target,
        parameters: [:], expectedEffect: "x", sideEffectClass: .local,
        reversibility: .reversible, idempotency: .idempotent,
        requiredPermission: .modifyWorkspace, verificationPlan: "x"
    )
}

private func contract(allowed: [String]) -> TaskContract {
    TaskContract(
        objective: "o", inputs: [], allowedScope: allowed, mustPreserve: [],
        forbiddenScope: [], expectedOutputs: [], verificationRequirements: [],
        dependencyAssumptions: [], stalenessConditions: []
    )
}

@Test func repeatedEquivalentFailuresHaltAndEscalate() async throws {
    let (supervisor, journal, root) = try makeSupervisor()
    defer { try? FileManager.default.removeItem(at: root) }
    let req = request(operation: "fs.write", target: "ws/a.swift")

    let first = await supervisor.inspect(failedResult(), for: req, contract: nil)
    let second = await supervisor.inspect(failedResult(), for: req, contract: nil)
    #expect(first == .proceed)
    #expect(second == .proceed)

    let third = await supervisor.inspect(failedResult(), for: req, contract: nil)
    guard case .haltAndEscalate(let reason) = third else {
        Issue.record("expected halt on third equivalent failure, got \(third)")
        return
    }
    #expect(reason.contains("repeated"))

    let replay = try JournalReader.readAllEvents(at: journal.journalFileURL)
    let escalations = replay.records.filter { record in
        if case .decisionRequested = record.event { return true } else { return false }
    }
    #expect(escalations.count == 1)
}

@Test func distinctFailuresDoNotAccumulate() async throws {
    let (supervisor, _, root) = try makeSupervisor()
    defer { try? FileManager.default.removeItem(at: root) }

    let a = await supervisor.inspect(failedResult(), for: request(operation: "fs.write", target: "ws/a"), contract: nil)
    let b = await supervisor.inspect(failedResult(), for: request(operation: "fs.write", target: "ws/b"), contract: nil)
    let c = await supervisor.inspect(failedResult(), for: request(operation: "fs.read", target: "ws/a"), contract: nil)
    #expect(a == .proceed)
    #expect(b == .proceed)
    #expect(c == .proceed)
}

@Test func successResetsStrikeCount() async throws {
    let (supervisor, _, root) = try makeSupervisor()
    defer { try? FileManager.default.removeItem(at: root) }
    let req = request(operation: "fs.write", target: "ws/a.swift")

    _ = await supervisor.inspect(failedResult(), for: req, contract: nil)
    _ = await supervisor.inspect(failedResult(), for: req, contract: nil)
    let success = ActionResult(actionID: ActionID(), outcome: .succeeded, startedAt: Date(), endedAt: Date())
    _ = await supervisor.inspect(success, for: req, contract: nil)
    _ = await supervisor.inspect(failedResult(), for: req, contract: nil)
    let afterReset = await supervisor.inspect(failedResult(), for: req, contract: nil)
    #expect(afterReset == .proceed)
}

@Test func outOfContractScopeActionIsBlocked() async throws {
    let (supervisor, journal, root) = try makeSupervisor()
    defer { try? FileManager.default.removeItem(at: root) }

    let outside = request(operation: "fs.write", target: "/tmp/elsewhere/secret.swift")
    let directive = await supervisor.inspect(failedResult(), for: outside, contract: contract(allowed: ["ws/Sources/"]))
    guard case .blockAttempt(let reason) = directive else {
        Issue.record("expected contract-drift block, got \(directive)")
        return
    }
    #expect(reason.contains("contract"))

    let inside = request(operation: "fs.write", target: "ws/Sources/Fix.swift")
    let allowed = await supervisor.inspect(failedResult(), for: inside, contract: contract(allowed: ["ws/Sources/"]))
    #expect(allowed == .proceed)

    let replay = try JournalReader.readAllEvents(at: journal.journalFileURL)
    let blocks = replay.records.filter { record in
        if case .decisionRequested(let p) = record.event { return p.subject.contains("contract") } else { return false }
    }
    #expect(blocks.count == 1)
}

@Test func spendAboveCeilingIsRefusedAndJournaled() async throws {
    let (supervisor, journal, root) = try makeSupervisor(maxSpend: 1.0)
    defer { try? FileManager.default.removeItem(at: root) }

    let free = await supervisor.checkSpend(projectedAdditionUSD: 0)
    #expect(free == .proceed)

    let over = await supervisor.checkSpend(projectedAdditionUSD: 1.5)
    guard case .refuseSpend(let reason) = over else {
        Issue.record("expected spend refusal, got \(over)")
        return
    }
    #expect(reason.contains("budget"))

    let replay = try JournalReader.readAllEvents(at: journal.journalFileURL)
    let spendEvents = replay.records.filter { record in
        if case .decisionRequested(let p) = record.event { return p.subject.contains("spend") } else { return false }
    }
    #expect(spendEvents.count == 1)
}
