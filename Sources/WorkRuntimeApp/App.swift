import SwiftUI
import AIOSCore
import EventJournal
import DesktopShell

// Minimal shell host: inspect one project's journal truthfully. Launch with
// `swift run WorkRuntimeApp --journal <root>` where <root> is the directory
// containing <projectUUID>/journal/events.journal.

struct Options {
    var journalRoot: String?

    init(arguments: [String]) {
        var iterator = arguments.makeIterator()
        while let flag = iterator.next() {
            switch flag {
            case "--journal":
                journalRoot = iterator.next()
            default:
                break
            }
        }
    }
}

@main
struct WorkRuntimeApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("AI Work Runtime") {
            RootView(options: Options(arguments: Array(CommandLine.arguments.dropFirst())))
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowStyle(.automatic)
    }
}

struct RootView: View {
    @State private var model: AppModel?
    @State private var projects: [DiscoveredProject] = []
    @State private var isFullScreen = false
    let options: Options

    var body: some View {
        Group {
            if let model {
                VStack(spacing: 0) {
                    if projects.count > 1 {
                        projectSwitcher.padding(8).background(.bar)
                    }
                    HomeView(model: model)
                }
            } else {
                VStack(spacing: 8) {
                    Text("No project loaded")
                        .font(.title3)
                    Text("Relaunch with --journal <directory> pointing at a project journal root.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 520, minHeight: 320)
            }
        }
        .toolbar {
            Toggle(isOn: $isFullScreen) {
                Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right.square")
            }
            .toggleStyle(.button)
            .onChange(of: isFullScreen) { enabled in
                if enabled {
                    NSApp?.windows.first?.toggleFullScreen(nil)
                } else if let window = NSApp?.windows.first, window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            }
        }
        .task { await loadIfNeeded() }
    }

    private var projectSwitcher: some View {
        HStack {
            Label("Projects", systemImage: "square.grid.2x2").font(.headline)
            ForEach(projects) { project in
                Button(String(project.projectID.rawValue.uuidString.prefix(8))) {
                    Task { await select(project) }
                }
                .buttonStyle(.bordered)
                .disabled(project.projectID == model?.projectID)
            }
            Spacer()
        }
    }

    private func select(_ project: DiscoveredProject) async {
        let root = project.journalURL
            .deletingLastPathComponent() // journal/
            .deletingLastPathComponent() // <uuid>/
        guard let store = try? JournalStore(projectID: project.projectID, rootDirectory: root) else { return }
        let loaded = AppModel(store: store)
        await loaded.refresh()
        model = loaded
    }

    private func loadIfNeeded() async {
        guard model == nil, let rootPath = options.journalRoot else { return }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let discovered = ProjectDiscovery.projects(under: root)
        projects = discovered
        guard let first = discovered.first else { return }
        await select(first)
    }
}
