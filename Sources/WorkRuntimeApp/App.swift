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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    final class AppDelegate: NSObject, NSApplicationDelegate {
        let commandBus = CommandBus()

        func applicationDidFinishLaunching(_ notification: Notification) {
            NSApplication.shared.setActivationPolicy(.regular)
        }
    }

    var body: some Scene {
        WindowGroup("AI Work Runtime", id: "main") { [appDelegate] in
            RootView(options: Options(arguments: Array(CommandLine.arguments.dropFirst())))
                .frame(minWidth: 960, minHeight: 600)
                .environmentObject(appDelegate.commandBus)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            OSMenus()
        }
    }
}

/// Shared command bus so menus, status item, and views dispatch identically.
/// Not MainActor-isolated at the type level so app entry points can hold it;
/// dispatch hops to the MainActor router via Task.
final class CommandBus: ObservableObject, @unchecked Sendable {
    let router: CommandRouter
    private let lock = NSLock()
    private var _model: AppModel?
    var onSwitchDesktop: ((Int) -> Void)?

    init(router: CommandRouter = MainActor.assumeIsolated { CommandRouter() }) {
        self.router = router
    }

    var model: AppModel? {
        lock.lock(); defer { lock.unlock() }
        return _model
    }

    func bind(model: AppModel?) {
        lock.lock(); defer { lock.unlock() }
        _model = model
    }

    func send(_ command: AppCommand) {
        guard let model else { return }
        Task { @MainActor in await router.dispatch(command, to: model) }
    }
}

/// The native menu bar (macOS conventions; every entry routes through the
/// tested CommandRouter).
struct OSMenus: Commands {
    @FocusedObject private var bus: CommandBus?

    var body: some Commands {
        SidebarCommands()
        CommandGroup(after: .newItem) {
            Button("New Note") { bus?.send(.newNote(text: "")) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Inbox Capture") { bus?.send(.newInboxCapture(text: "")) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Refresh Projections") { bus?.send(.refresh) }
                .keyboardShortcut("r", modifiers: [.command])
            Button("Return to Now") { bus?.send(.scrubToNow) }
                .keyboardShortcut(.cancelAction)
            Button("Toggle Timeline Ruler") { bus?.send(.toggleRuler) }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Button("Cycle Card Size") { bus?.send(.cycleCardScale) }
                .keyboardShortcut("s", modifiers: [.command, .option])
        }
        CommandMenu("Desktop") {
            ForEach(0..<9, id: \.self) { index in
                Button("Switch to Desktop \(index + 1)") {
                    bus?.onSwitchDesktop?(index)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
            }
            Divider()
            Button("Next Desktop") { bus?.onSwitchDesktop?(-1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Previous Desktop") { bus?.onSwitchDesktop?(-2) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
        }
        CommandMenu("Control") {
            Button("Emergency Stop") { bus?.send(.emergencyStop) }
                .keyboardShortcut(".", modifiers: [.command, .shift])
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var commandBus: CommandBus
    @State private var model: AppModel?
    @State private var projects: [DiscoveredProject] = []
    @State private var isFullScreen = false
    @State private var statusController: StatusBarController?
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
        .onChange(of: model?.state) { _ in
            statusController?.update(with: model?.state)
        }
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
        guard let store = try? JournalStore(projectID: project.projectID, rootDirectory: project.root) else { return }
        let loaded = AppModel(store: store)
        await loaded.refresh()
        model = loaded
        commandBus.bind(model: loaded)

        // Present as the desktop environment it is — once the window exists.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let window = NSApplication.shared.windows.first,
               !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }

        // Desktop switching restores each project's session state.
        let session = (try? DesktopSessionStore(storageRoot: project.root).load(for: project.projectID)) ?? .default
        if let scrub = session.lastScrubSequence, scrub < (loaded.state?.lastSequence ?? 0) {
            loaded.enterHistorical(at: scrub)
        }

        // Install the menu-bar status item once; it reads live projections.
        if statusController == nil {
            let controller = StatusBarController()
            controller.install(router: commandBus.router, model: loaded)
            controller.update(with: loaded.state)
            statusController = controller
        }
    }

    private func loadIfNeeded() async {
        guard model == nil else { return }
        // Journal root: explicit --journal flag, else demo projects if
        // seeded, else the standard app-support root. Launch just works.
        let root: URL
        if let rootPath = options.journalRoot {
            root = URL(fileURLWithPath: rootPath, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let demo = support.appendingPathComponent("AIOS/demo-projects", isDirectory: true)
            let standard = support.appendingPathComponent("AIOS/projects", isDirectory: true)
            if FileManager.default.fileExists(atPath: demo.path) {
                root = demo
            } else {
                root = standard
            }
        }
        let discovered = ProjectDiscovery.projects(under: root)
        projects = discovered
        guard let first = discovered.first else { return }
        await select(first)
    }
}
