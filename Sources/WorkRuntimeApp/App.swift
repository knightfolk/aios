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
        }
    }
}

struct RootView: View {
    @State private var model: AppModel?
    let options: Options

    var body: some View {
        Group {
            if let model {
                HomeView(model: model)
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
        .task { await loadIfNeeded() }
    }

    private func loadIfNeeded() async {
        guard model == nil, let rootPath = options.journalRoot else { return }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard let projectDir = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ).first,
            let projectUUID = UUID(uuidString: projectDir.lastPathComponent),
            let store = try? JournalStore(
                projectID: ProjectID(rawValue: projectUUID),
                rootDirectory: root
            ) else { return }
        let loaded = AppModel(store: store)
        await loaded.refresh()
        model = loaded
    }
}
