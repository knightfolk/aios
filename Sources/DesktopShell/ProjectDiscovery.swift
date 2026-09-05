import Foundation
import AIOSCore
import EventJournal

// Item 5: multi-project Home. Discovery is a pure function over the journal
// root; the switcher selects the active project; the shell can go
// full-screen.

public struct DiscoveredProject: Sendable, Equatable, Identifiable {
    public var id: ProjectID { projectID }
    public var projectID: ProjectID
    public var journalURL: URL
    /// The journal ROOT (parent of the <uuid> dir) — the store's rootDirectory.
    public var root: URL

    public init(projectID: ProjectID, journalURL: URL, root: URL) {
        self.projectID = projectID
        self.journalURL = journalURL
        self.root = root
    }
}

public enum ProjectDiscovery {
    /// Every `<uuid>/journal/events.journal` under the root. Non-UUID
    /// entries and missing journals are ignored.
    public static func projects(under root: URL) -> [DiscoveredProject] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return contents.compactMap { entry in
            guard let uuid = UUID(uuidString: entry.lastPathComponent),
                  (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                return nil
            }
            let journal = entry.appendingPathComponent("journal", isDirectory: true)
                .appendingPathComponent("events.journal")
            guard FileManager.default.fileExists(atPath: journal.path) else { return nil }
            // root = the journal root (parent of <uuid>) — the store's
            // rootDirectory, from which it derives <uuid>/journal/events.journal.
            return DiscoveredProject(
                projectID: ProjectID(rawValue: uuid),
                journalURL: journal,
                root: entry.deletingLastPathComponent()
            )
        }
        .sorted { $0.projectID.rawValue.uuidString < $1.projectID.rawValue.uuidString }
    }
}

public struct HomeSummary: Sendable, Equatable {
    public var titles: [String]
    public var activeTitle: String
}

public enum HomeViewModel {
    public static func summary(projects: [DiscoveredProject], activeIndex: Int) -> HomeSummary {
        let titles = projects.map { $0.projectID.rawValue.uuidString.prefix(8) }
        let active = titles.indices.contains(activeIndex) ? "\(titles[activeIndex]) (active)" : "none"
        return HomeSummary(titles: titles.map(String.init), activeTitle: active)
    }
}
