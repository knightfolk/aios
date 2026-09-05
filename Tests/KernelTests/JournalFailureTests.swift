import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import SecurityKernel
@testable import CapabilityBroker
@testable import ComputerControl

// Wave 1.1: journal appends in state-transition paths must not silently
// fail. When the journal is unwritable, the engine surfaces degraded health
// instead of proceeding as if it recorded something. The seam: a real
// JournalStore pointed at a read-only directory makes appends genuinely fail.

@Test func brokerSurfacesJournalWriteFailure() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-jfail-ro-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-jfail-ws-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }

    // Store init creates the journal directory; lock it BEFORE the first
    // append so the file-creation inside obtainFileHandle genuinely fails.
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    let journalDir = journal.journalFileURL.deletingLastPathComponent()
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: journalDir.path)
    do {
        _ = try await journal.append(.projectOpened)
        Issue.record("append should fail against a read-only journal dir")
    } catch {
        // expected
    }
    let failures = await journal.appendFailureCount
    #expect(failures >= 1)

    let broker = CapabilityBroker(journal: journal)
    let policy = SecurityPolicy(workspaceRoots: [workspace.path], allowedCommands: [], localOnly: true)
    let request = ActionRequest(
        actionID: ActionID(), workPackageID: WorkPackageID(), requestedBy: .linus,
        capability: .observe, operation: "fs.read", target: workspace.appendingPathComponent("x").path,
        parameters: [:], expectedEffect: "read", sideEffectClass: .none,
        reversibility: .reversible, idempotency: .idempotent,
        requiredPermission: .observe, verificationPlan: "v"
    )
    let prepared = await broker.prepare(request, policy: policy)
    #expect(prepared.rejection != nil, "journal write failure must surface as rejection, not silent success")
    #expect(prepared.rejection?.failureDetails?.contains("journal") == true)
}

@Test func leaseRefusesGrantWhenJournalUnwritable() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-lfail-ro-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    let leaseDir = journal.journalFileURL.deletingLastPathComponent()
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: leaseDir.path)
    let lease = ComputerControlLease(journal: journal)
    do {
        _ = try await lease.acquire(owner: "t/chloe", purpose: "p", allowedActions: [], ttlSeconds: 10)
        Issue.record("acquire must throw when the journal is unwritable")
    } catch {
        // expected: a lease that cannot be journaled is not granted
    }
    let authorize = try await lease.authorize(owner: "t/chloe", action: .activateApp)
    #expect(authorize == .denied)
}

@Test func journalFailureCounterVisible() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-hfail-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)

    _ = try await journal.append(.projectOpened)
    let healthy = await journal.appendFailureCount
    #expect(healthy == 0)

    await journal.noteAppendFailure()
    let failures = await journal.appendFailureCount
    #expect(failures == 1)
}
