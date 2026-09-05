import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import DesktopShell

// OS T2: the command layer. Menus, keyboard, and the status item all emit
// AppCommands; the router maps each to a journaling engine call or a UI
// state change. Pure and testable — the AppKit surface stays thin.

@MainActor
@Test func commandsRouteToEngineEffects() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-cmd-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    let model = AppModel(store: journal)

    try await journal.append(.decisionRequested(.init(subject: "s", question: "q", blocking: true)))
    await model.refresh()

    let router = CommandRouter()
    await router.dispatch(.resolveNeedsYou(subject: "s", question: "q", answer: "done"), to: model)
    #expect(model.state?.needsUser.isEmpty == true)

    await router.dispatch(.newNote(text: "captured"), to: model)
    let notes = await model.loadNotes()
    #expect(notes.map(\.text) == ["captured"])

    await router.dispatch(.emergencyStop, to: model)
    #expect(await model.emergencyStop.engaged == true)
    #expect(model.state?.interventions.contains { $0.contains("Emergency Stop") } == true)

    await router.dispatch(.scrubToNow, to: model)
    #expect(model.historicalState == nil)
}

@MainActor
@Test func statusItemCountsComeFromProjections() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-status-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)

    try await journal.append(.decisionRequested(.init(subject: "a", question: "q", blocking: false)))
    try await journal.append(.decisionRequested(.init(subject: "b", question: "q", blocking: false)))
    try await journal.append(.attemptStarted(.init(attemptID: AttemptID(), taskID: TaskID(), workPackageID: WorkPackageID(),
                                                   worker: WorkerIdentity(workerID: "w", runtime: .mlx))))
    let model = AppModel(store: journal)
    await model.refresh()

    let status = StatusItemViewModel.summary(from: model.state)
    #expect(status.needsYou == 2)
    #expect(status.activeActivities == 1)
    #expect(status.label.contains("2")) // live counts in the menu-bar label
}
