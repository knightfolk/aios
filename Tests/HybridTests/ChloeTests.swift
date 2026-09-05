import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import SecurityKernel
@testable import ComputerControl
@testable import DesktopShell

@Test func leaseExclusivityDenialsAndRelease() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-lease-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let lease = ComputerControlLease(journal: journal)

    let first = try await lease.acquire(owner: "task-42/chloe", purpose: "export report", allowedActions: [.typeText], ttlSeconds: 60)
    #expect(first.granted)

    let second = try await lease.acquire(owner: "task-43/chloe", purpose: "conflicting", allowedActions: [.typeText], ttlSeconds: 60)
    #expect(!second.granted)

    try await lease.release(reason: "work finished")
    let third = try await lease.acquire(owner: "task-43/chloe", purpose: "after release", allowedActions: [.typeText], ttlSeconds: 60)
    #expect(third.granted)

    var state = try Projection.replayAll(journal)
    #expect(state.leaseEvents.filter(\.granted).count == 2)
    #expect(state.leaseEvents.contains { !$0.granted })

    // Expiry: a TTL-1 lease is gone after sleep.
    try await lease.release(reason: "cleanup")
    _ = try await lease.acquire(owner: "task-44/chloe", purpose: "short", allowedActions: [], ttlSeconds: 1)
    try await Task.sleep(for: .milliseconds(1200))
    let postExpiry = try await lease.acquire(owner: "task-45/chloe", purpose: "after expiry", allowedActions: [], ttlSeconds: 60)
    #expect(postExpiry.granted)
}

@Test func userInteractionOutranksAutomation() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-lease-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let lease = ComputerControlLease(journal: journal)
    _ = try await lease.acquire(owner: "task-1/chloe", purpose: "p", allowedActions: [.typeText], ttlSeconds: 60)

    // The user touched the real desktop: assumptions are invalidated and the
    // lease no longer authorizes anything until re-observation.
    let invalidated = try await lease.noteUserInteraction()
    #expect(invalidated)
    #expect(try await lease.authorize(owner: "task-1/chloe", action: .typeText) == .denied)
}

@Test func emergencyStopReleasesLeaseAndFreezesDirector() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-estop-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let lease = ComputerControlLease(journal: journal)
    let director = ChloeDirector(lease: lease, adapter: ShadowAdapter())
    let stop = EmergencyStop(journal: journal)

    _ = try await lease.acquire(owner: "task-1/chloe", purpose: "p", allowedActions: [.typeText], ttlSeconds: 60)

    // Shadow mode result before stop.
    let before = try await director.perform(.init(owner: "task-1/chloe", action: .typeText, target: "AX:focus", parameters: ["text": "hi"]))
    #expect(before.executed == false)
    #expect(before.detail?.contains("shadow") == true)

    // Emergency stop: deterministic, no models, releases + freezes.
    try await stop.engage(reason: "user hit the red button")
    try await director.emergencyStopEngaged()

    let after = try await director.perform(.init(owner: "task-1/chloe", action: .typeText, target: "AX:focus", parameters: ["text": "hi"]))
    #expect(after.executed == false)
    #expect(after.detail?.contains("frozen") == true)

    let state = try Projection.replayAll(journal)
    #expect(state.interventions.contains { $0.contains("Emergency Stop") })
    #expect(state.leaseEvents.contains { $0.reason.contains("Emergency Stop") })
}

@Test func shadowModeNeverExecutesAndSaysSo() async throws {
    let director = ChloeDirector(
        lease: NoopLeaseForTests(),
        adapter: ShadowAdapter()
    )
    let result = try await director.perform(.init(owner: "t", action: .activateApp, target: "com.apple.TextEdit", parameters: [:]))
    #expect(result.executed == false)
    #expect(result.shadowRecorded)
}

/// Test double: always-granting lease for adapter-level tests.
final class NoopLeaseForTests: LeaseAuthorizing, @unchecked Sendable {
    func acquire(owner: String, purpose: String, allowedActions: [ChloeAction], ttlSeconds: TimeInterval) async throws -> LeaseGrant { LeaseGrant(granted: true, owner: owner) }
    func release(reason: String) async throws {}
    func authorize(owner: String, action: ChloeAction) async throws -> LeaseAuthorization { .allowed }
    func noteUserInteraction() async throws -> Bool { false }
    func emergencyRelease(reason: String) async throws {}
}
