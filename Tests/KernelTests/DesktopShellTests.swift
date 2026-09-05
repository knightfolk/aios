import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import DesktopShell

@Test func timelineSegmentsDeriveTruthfullyFromState() {
    let projectID = ProjectID()
    var state = ProjectState(projectID: projectID)

    let done = TaskID()
    let running = TaskID()
    let planned = TaskID()
    let events: [EngineEvent] = [
        .taskCreated(.init(taskID: done, planRevisionID: PlanRevisionID(), objective: "done work", owner: .linus)),
        .taskStateChanged(.init(taskID: done, oldState: .pending, newState: .inProgress)),
        .verificationPassed(.init(taskID: done, requirement: "checks")),
        .taskCreated(.init(taskID: running, planRevisionID: PlanRevisionID(), objective: "live work", owner: .linus)),
        .taskStateChanged(.init(taskID: running, oldState: .pending, newState: .inProgress)),
        .attemptStarted(.init(attemptID: AttemptID(), taskID: running, workPackageID: WorkPackageID(),
                              worker: WorkerIdentity(workerID: "w", runtime: .scripted))),
        .taskCreated(.init(taskID: planned, planRevisionID: PlanRevisionID(), objective: "future work", owner: .sherlock)),
    ]
    for (index, event) in events.enumerated() {
        state = Projection.apply(state, EventRecord(sequence: UInt64(index + 1), recordedAt: Date(), projectID: projectID, event: event))
    }
    state.warnings.append("suspected missing verification coverage")

    let segments = TimelineViewModel.segments(from: state)

    #expect(segments.first?.kind == .past)
    #expect(segments.first?.count == 1) // one completed, journaled task

    let now = segments.first { $0.kind == .now }
    #expect(now?.count == 1) // one running attempt

    let future = segments.first { $0.kind == .future }
    #expect(future?.count == 1) // one planned-but-not-started task

    let gaps = segments.first { $0.kind == .gaps }
    #expect(gaps?.count == 1) // one warning == one gap marker
}

@Test func emptyStateYieldsAllSegmentsZero() {
    let segments = TimelineViewModel.segments(from: ProjectState(projectID: ProjectID()))
    #expect(segments.count == 4)
    #expect(segments.allSatisfy { $0.count == 0 })
}

@Test func emergencyStopIsDeterministicAndJournaled() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-stop-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let stop = EmergencyStop(journal: journal)
    #expect(await stop.engaged == false)

    try await stop.engage(reason: "user pressed the stop control")

    #expect(await stop.engaged == true)
    let state = try Projection.replayAll(journal)
    #expect(state.interventions.contains { $0.contains("Emergency Stop") })
    #expect(state.interventions.contains { $0.contains("user pressed the stop control") })

    // Engaging again must not duplicate the intervention record.
    try await stop.engage(reason: "pressed again")
    let state2 = try Projection.replayAll(journal)
    #expect(state2.interventions.filter { $0.contains("Emergency Stop") }.count == 1)
}

@Test func cardSummariesComeFromProjectedState() {
    var state = ProjectState(projectID: ProjectID())
    state.needsUser.append(NeedsYouEntry(subject: "contract drift", question: "block?", blocking: true))
    state.warnings.append("stale evidence suspected")
    state.artifacts[ArtifactID()] = ArtifactRecord(
        artifactID: ArtifactID(), kind: .fileOrDiff, path: "ws/main.swift", revision: "r1", contentHash: "h1"
    )

    let cards = CardGridViewModel.cards(from: state)
    #expect(cards.contains { $0.title == "Needs You" })
    #expect(cards.contains { $0.title == "Findings" })
    #expect(cards.contains { $0.title == "Artifacts" })
    #expect(!cards.contains { $0.title == "Concierge" }) // no decorative panels
}
