import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal

private func makeStore(in root: URL? = nil) throws -> JournalStore {
    let dir = root ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-journal-\(UUID().uuidString)", isDirectory: true)
    return try JournalStore(projectID: ProjectID(), rootDirectory: dir)
}

@Test func appendAndReplayYieldsIdenticalRecords() async throws {
    let store = try makeStore()
    defer { try? FileManager.default.removeItem(at: store.rootDirectory) }

    let projectID = store.projectID
    let r1 = try await store.append(.projectOpened)
    let r2 = try await store.append(.goalCreated(.init(goalRevisionID: GoalRevisionID(), originalRequest: "ship it", objective: "ship", acceptanceCriteria: ["tests pass"])))
    let action = ActionRequest.makeJournalFixture()
    let r3 = try await store.append(.actionRequested(.init(request: action)))

    #expect(r1.sequence == 1)
    #expect(r2.sequence == 2)
    #expect(r3.sequence == 3)
    #expect(r1.projectID == projectID)

    let replay = try JournalReader.readAllEvents(at: store.journalFileURL)
    #expect(!replay.tornTail)
    #expect(replay.records.count == 3)
    #expect(replay.records.map(\.sequence) == [1, 2, 3])
    #expect(replay.records[0].event == .projectOpened)
    #expect(replay.records[2].event == .actionRequested(.init(request: action)))
}

@Test func tornTailIsDetectedAfterTruncation() async throws {
    let store = try makeStore()
    defer { try? FileManager.default.removeItem(at: store.rootDirectory) }

    for _ in 0..<3 { _ = try await store.append(.projectOpened) }

    // Chop bytes off the last frame to simulate a crash mid-write.
    let url = store.journalFileURL
    var data = try Data(contentsOf: url)
    data.removeLast(10)
    try data.write(to: url)

    let replay = try JournalReader.readAllEvents(at: url)
    #expect(replay.tornTail)
    #expect(replay.records.count == 2)
    #expect(replay.records.map(\.sequence) == [1, 2])
}

@Test func crcCorruptionIsDetected() async throws {
    let store = try makeStore()
    defer { try? FileManager.default.removeItem(at: store.rootDirectory) }

    for _ in 0..<3 { _ = try await store.append(.projectOpened) }

    let url = store.journalFileURL
    var data = try Data(contentsOf: url)
    // Flip one byte in the middle of the file — lands inside a frame payload.
    data[data.count / 2] ^= 0xFF
    try data.write(to: url)

    let replay = try JournalReader.readAllEvents(at: url)
    #expect(replay.tornTail)
    #expect(replay.records.count < 3)
    #expect(replay.records.count >= 1)
}

@Test func concurrentAppendsStayStrictlyMonotonic() async throws {
    let store = try makeStore()
    defer { try? FileManager.default.removeItem(at: store.rootDirectory) }

    let writers = (0..<20).map { writer in
        Task<Void, Error> {
            for _ in 0..<10 { _ = try await store.append(.projectOpened) }
        }
    }
    for writer in writers { try await writer.value }

    let replay = try JournalReader.readAllEvents(at: store.journalFileURL)
    #expect(!replay.tornTail)
    #expect(replay.records.count == 200)
    #expect(replay.records.map(\.sequence) == Array(1...200))
}

@Test func sequenceContinuesAfterReopen() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-journal-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let first = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    for _ in 0..<4 { _ = try await first.append(.projectOpened) }

    let reopened = try JournalStore(projectID: first.projectID, rootDirectory: root)
    let next = try await reopened.append(.projectOpened)
    #expect(next.sequence == 5)
}

@Test func unknownFrameVersionStopsReplayAsTornTail() async throws {
    let store = try makeStore()
    defer { try? FileManager.default.removeItem(at: store.rootDirectory) }
    _ = try await store.append(.projectOpened)

    // Hand-craft a frame with an unsupported version after the valid one.
    var bogus = Data()
    func put32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { bogus.append(contentsOf: $0) } }
    put32(0x41494F53) // magic
    put32(99)         // unsupported frame version
    put32(4)
    put32(0)
    bogus.append(contentsOf: [1, 2, 3, 4])

    let url = store.journalFileURL
    var data = try Data(contentsOf: url)
    data.append(bogus)
    try data.write(to: url)

    let replay = try JournalReader.readAllEvents(at: url)
    #expect(replay.tornTail)
    #expect(replay.records.count == 1)
}

@Test func replayOf100kEventsStaysFast() async throws {
    let store = try makeStore()
    defer { try? FileManager.default.removeItem(at: store.rootDirectory) }

    let payload = EngineEvent.taskCreated(.init(
        taskID: TaskID(), planRevisionID: PlanRevisionID(),
        objective: "sample objective for size", owner: .linus
    ))
    let clock = ContinuousClock()
    let appendStart = clock.now
    for _ in 0..<100_000 { _ = try await store.append(payload) }
    let appendElapsed = clock.now - appendStart

    let replayStart = clock.now
    let replay = try JournalReader.readAllEvents(at: store.journalFileURL)
    let replayElapsed = clock.now - replayStart

    #expect(replay.records.count == 100_000)
    #expect(!replay.tornTail)
    #expect(appendElapsed < .seconds(20), "append took \(appendElapsed)")
    #expect(replayElapsed < .seconds(5), "replay took \(replayElapsed)")
}

// MARK: - Fixtures

extension ActionRequest {
    static func makeJournalFixture() -> ActionRequest {
        ActionRequest(
            actionID: ActionID(),
            workPackageID: WorkPackageID(),
            requestedBy: .linus,
            capability: .modifyWorkspace,
            operation: "fs.write",
            target: "Sources/Parser/Lexer.swift",
            parameters: ["contents": .text("let x = 1\n")],
            expectedEffect: "lexer fix applied",
            sideEffectClass: .local,
            reversibility: .reversible,
            idempotency: .idempotent,
            requiredPermission: .modifyWorkspace,
            preconditions: [Precondition(target: "Sources/Parser/Lexer.swift", contentHash: "aa11")],
            verificationPlan: "swift test --filter Lexer"
        )
    }
}
