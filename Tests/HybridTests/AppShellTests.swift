import Foundation
import Testing
@testable import AIOSCore
@testable import DesktopShell

@Test func projectDiscoveryFindsJournalsUnderRoot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-home-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    func makeProject(_ name: String) throws -> ProjectID {
        let id = ProjectID()
        let dir = root.appendingPathComponent(id.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("journal", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("events.journal"))
        return id
    }

    let a = try makeProject("a")
    let b = try makeProject("b")
    let discovered = ProjectDiscovery.projects(under: root)
    #expect(Set(discovered.map(\.projectID)) == Set([a, b]))
    #expect(discovered.allSatisfy { $0.projectID.rawValue != ProjectID().rawValue })
}

@Test func projectDiscoveryToleratesEmptyAndNoisyRoots() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-home-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(ProjectDiscovery.projects(under: root).isEmpty)

    // Non-UUID directories and stray files are ignored.
    try FileManager.default.createDirectory(at: root.appendingPathComponent("not-a-uuid", isDirectory: true), withIntermediateDirectories: true)
    try Data("junk".utf8).write(to: root.appendingPathComponent("stray.txt"))
    #expect(ProjectDiscovery.projects(under: root).isEmpty)
}

@Test func homeViewModelSummarizesDiscoveredProjects() {
    let projects = [
        DiscoveredProject(projectID: ProjectID(), journalURL: URL(fileURLWithPath: "/tmp/a")),
        DiscoveredProject(projectID: ProjectID(), journalURL: URL(fileURLWithPath: "/tmp/b")),
    ]
    let summary = HomeViewModel.summary(projects: projects, activeIndex: 1)
    #expect(summary.titles.count == 2)
    #expect(summary.activeTitle.hasSuffix("(active)"))
}
