import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import DesktopShell

// Step 2: timeline depth — the ruler derives event marks and branch lanes
// from the journal (pure projection), and the scrub position pins to it.

@Test func rulerDerivesMarksAndBranchLanes() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-ruler-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let goal = GoalRevisionID()
    let planA = PlanRevisionID()
    let planB = PlanRevisionID()
    let events: [EngineEvent] = [
        .projectOpened,
        .goalCreated(.init(goalRevisionID: goal, originalRequest: "r", objective: "o", acceptanceCriteria: ["c"])),
        .planProposed(.init(planRevisionID: planA, goalRevisionID: goal, summary: "A")),
        .attemptStarted(.init(attemptID: AttemptID(), taskID: TaskID(), workPackageID: WorkPackageID(),
                              worker: WorkerIdentity(workerID: "w", runtime: .mlx))),
        .verificationPassed(.init(taskID: TaskID(), requirement: "r")),
        .checkpointCreated(.init(checkpointID: "cp1", note: "n")),
        .branchCreated(.init(fromCheckpointID: "cp1", newPlanRevisionID: planB, previousPlanRevisionID: planA, reason: "alt")),
        .attemptEnded(.init(attemptID: AttemptID(), taskID: TaskID(), outcome: .completed)),
    ]
    for event in events {
        _ = try await journal.append(event)
    }

    let ruler = TimelineRulerViewModel.build(from: journal)
    #expect(ruler.totalEvents == 8)
    #expect(ruler.marks.contains { $0.label == "Goal" })
    #expect(ruler.marks.contains { $0.label == "Checkpoint" })
    #expect(ruler.marks.contains { $0.label == "Verified" })
    #expect(ruler.lanes.count == 2) // mainline + one branch
    #expect(ruler.lanes[1].branchID != nil)
    #expect(ruler.lanes[1].startsAtSequence == 7) // branchCreated event, 1-indexed
    #expect(ruler.lanes[1].label.contains("alt"))
}

@Test func scrubPinsToNearestMark() {
    let marks: [TimelineMark] = [
        TimelineMark(sequence: 2, label: "Goal"),
        TimelineMark(sequence: 6, label: "Checkpoint"),
    ]
    #expect(TimelineRulerViewModel.nearestMark(to: 1, in: marks)?.label == "Goal")
    #expect(TimelineRulerViewModel.nearestMark(to: 5, in: marks)?.label == "Checkpoint")
    #expect(TimelineRulerViewModel.nearestMark(to: 3, in: marks)?.label == "Goal")
    #expect(TimelineRulerViewModel.nearestMark(to: 99, in: marks)?.label == "Checkpoint")
}
