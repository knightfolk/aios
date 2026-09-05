import Foundation
import SwiftUI
import AIOSCore
import EventJournal
import ProjectKernel

/// Loads and refreshes projected state. UI state is never authoritative —
/// every visible fact comes from the journal via `Projection`.
@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var state: ProjectState?
    /// Non-nil while scrubbing history: the read-only reconstructed state.
    @Published public private(set) var historicalState: ProjectState?
    @Published public private(set) var stopEngaged = false
    @Published public private(set) var lastRouting: String?
    @Published public private(set) var layout: ProjectLayout = .default

    public let projectID: ProjectID
    private let store: JournalStore
    /// Read-only handle for ruler/projection builders.
    public var storeForRuler: JournalStore { store }
    public let emergencyStop: EmergencyStop
    private let notes: NotesStore
    private let inbox: InboxStore

    public init(store: JournalStore) {
        self.store = store
        self.projectID = store.projectID
        self.emergencyStop = EmergencyStop(journal: store)
        self.notes = NotesStore(journal: store, storageRoot: store.rootDirectory)
        self.inbox = InboxStore(journal: store, storageRoot: store.rootDirectory)
        self.checkpoints = CheckpointStore(journal: store)
        self.layoutStore = ProjectLayoutStore(storageRoot: store.rootDirectory)
        if let stored = try? layoutStore.load(for: store.projectID) {
            layout = stored
        }
    }

    private let layoutStore: ProjectLayoutStore

    public func saveLayout(_ newLayout: ProjectLayout) async {
        layout = newLayout
        try? layoutStore.save(newLayout, for: store.projectID)
    }

    /// Concierge front desk: deterministic routing, journaled effects.
    public func submitConcierge(_ raw: String) async {
        guard let routing = ConciergeRouter.route(raw) else { return }
        lastRouting = "\(routing.destination.rawValue): \(routing.payload)"
        try? await ConciergeRouter.deliver(raw, journal: store, notes: notes, inbox: inbox)
        await refresh()
    }

    // MARK: - Interactive card actions (each maps to a journaling engine call)

    private let checkpoints: CheckpointStore

    public func resolveNeedsYou(subject: String, question: String, answer: String) async {
        try? await store.append(.needsYouResolved(.init(subject: subject, question: question, answer: answer)))
        await refresh()
    }

    @discardableResult
    public func createNote(text: String) async -> NoteRecord {
        (try? await notes.create(text: text)) ?? NoteRecord(id: "note-error", text: text, createdAt: Date())
    }

    public func promoteNote(id: String, target: String) async {
        let summary = (await loadNotes()).first { $0.id == id }?.text ?? ""
        try? await notes.promote(noteID: id, target: target, summary: String(summary.prefix(120)))
        await refresh()
    }

    @discardableResult
    public func createInboxItem(text: String) async -> InboxItemRecord {
        (try? await inbox.create(text: text)) ?? InboxItemRecord(id: "inb-error", text: text, createdAt: Date())
    }

    public func promoteInboxItem(id: String, target: String) async {
        let summary = (await loadInbox()).first { $0.id == id }?.text ?? ""
        try? await inbox.promote(itemID: id, target: target, summary: String(summary.prefix(120)))
        await refresh()
    }

    public func loadNotes() async -> [NoteRecord] {
        (try? await notes.load()) ?? []
    }

    public func loadInbox() async -> [InboxItemRecord] {
        (try? await inbox.load()) ?? []
    }

    @discardableResult
    public func createCheckpoint(note: String) async -> CheckpointRecord {
        (try? await checkpoints.createCheckpoint(note: note, artifactRefs: []))
            ?? CheckpointRecord(checkpointID: "cp-error", atSequence: 0, note: note, artifactRefs: [])
    }

    @discardableResult
    public func branchFrom(checkpointID: String, reason: String) async -> PlanRevisionID? {
        let result = try? await checkpoints.branch(from: checkpointID, reason: reason)
        await refresh()
        return result ?? nil
    }

    public func restore(checkpointID: String, note: String) async {
        try? await checkpoints.restore(checkpointID: checkpointID, note: note)
        await refresh()
    }

    /// Stop control for a live activity: deterministic, journaled, no models.
    public func cancelAttempt(attemptID: AttemptID, reason: String) async {
        try? await store.append(.userIntervened(.init(
            intervention: "stop requested for attempt \(attemptID.rawValue.uuidString.prefix(8)): \(reason)"
        )))
        await refresh()
    }

    public func refresh() async {
        state = try? Projection.replayAll(store)
        stopEngaged = await emergencyStop.engaged
    }

    /// Scrub to a journal position: pure prefix replay, never a rollback.
    public func enterHistorical(at sequence: UInt64) {
        historicalState = try? Projection.state(at: sequence, of: store)
    }

    public func returnToNow() {
        historicalState = nil
    }

    /// The state the UI should render: historical when scrubbing, live now.
    public var displayState: ProjectState? {
        historicalState ?? state
    }

    /// Deterministic emergency path — no models involved.
    public func engageEmergencyStop() async {
        try? await emergencyStop.engage(reason: "user pressed the stop control")
        await refresh()
    }
}

struct TimelineStrip: View {
    let segments: [TimelineSegment]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(segments) { segment in
                HStack(spacing: 4) {
                    Text(segment.kind.rawValue)
                        .font(.caption2.weight(.bold))
                        .monospaced()
                    Text("\(segment.count)")
                        .font(.caption2.monospacedDigit())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(backgroundColor(for: segment.kind), in: RoundedRectangle(cornerRadius: 4))
                .help(segment.detail)
            }
        }
    }

    private func backgroundColor(for kind: TimelineSegmentKind) -> Color {
        switch kind {
        case .past: return Color.gray.opacity(0.22) // recorded history reads muted
        case .now: return Color.accentColor.opacity(0.18)
        case .future: return Color.blue.opacity(0.12)
        case .gaps: return Color.orange.opacity(0.15)
        }
    }
}

struct CardView: View {
    let card: CardSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.system(size: AIOSDesign.fontRole("cardTitle").size, weight: AIOSDesign.fontRole("cardTitle").weight))
            Text(card.body).font(.body).foregroundStyle(.secondary)
            Text("Why: \(card.whyHere)").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AIOSDesign.token(.surfacePanel), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

public struct ProjectDesktopView: View {
    @ObservedObject var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    private var rendered: ProjectState {
        model.displayState ?? ProjectState(projectID: model.projectID)
    }

    public var body: some View {
        let scrub = ScrubPosition(
            sequence: model.historicalState?.lastSequence ?? (model.state?.lastSequence ?? 0),
            lastSequence: model.state?.lastSequence ?? 0
        )
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Project \(model.projectID.rawValue.uuidString.prefix(8))")
                    .font(.title2.weight(.semibold))
                Spacer()
                TimelineStrip(segments: TimelineViewModel.segments(from: rendered))
            }

            if scrub.isHistorical {
                // Unmistakable historical mode (docs 06): muted, labeled,
                // one action from Return to Now.
                HStack {
                    Label("HISTORICAL VIEW — recorded state at #\(scrub.sequence); inspection only", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Return to Now") { model.returnToNow() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(10)
                .background(AIOSDesign.token(.surfaceHistory), in: RoundedRectangle(cornerRadius: 8))
            }

            TimelineRulerView(model: model)

            HStack(spacing: 16) {
                Text("Timeline scrub").font(.caption)
                Slider(
                    value: Binding(
                        get: { Double(model.historicalState?.lastSequence ?? model.state?.lastSequence ?? 0) },
                        set: { model.enterHistorical(at: UInt64($0)) }
                    ),
                    in: 0...Double(max(model.state?.lastSequence ?? 0, 1))
                )
                .disabled(model.state == nil)
                Text("#\(scrub.sequence)/\(scrub.lastSequence)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: model.layout.cardScale.minimumCardWidth), spacing: 12)], spacing: 12) {
                    ForEach(CardGridViewModel.cards(from: rendered)) { card in
                        CardView(card: card)
                    }
                    DepthPanels(model: model, rendered: rendered)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 480)
    }
}

/// Depth panels with teeth: Needs You resolves, Notes/Inbox promote,
/// checkpoints branch and restore, live activities stop. Every button maps
/// to a journaling engine call; nothing decorative.
struct DepthPanels: View {
    @ObservedObject var model: AppModel
    let rendered: ProjectState

    var body: some View {
        let needsYou = NeedsYouViewModel.summary(from: rendered)
        let health = ProjectHealth.compute(from: rendered)
        let future = FutureViewModel.items(from: rendered)

        Group {
            NeedsYouPanel(model: model, summary: needsYou)
            CardView(card: CardSummary(
                title: "Project Health",
                body: HealthViewModel.lines(from: health).joined(separator: " · "),
                whyHere: "evidence-based coverage, not a confidence score"
            ))
            CardView(card: CardSummary(
                title: future.isEmpty ? "Projected Future (empty)" : "Projected Future",
                body: future.isEmpty
                    ? "no planned tasks"
                    : future.map { "\($0.objective) (\($0.dependencyCount) deps)" }.joined(separator: " · "),
                whyHere: "the current plan — has not happened"
            ))
            NotesInboxPanel(model: model)
            CheckpointsPanel(model: model, state: rendered)
            ExpertCard(model: model, role: .linus)
            ExpertCard(model: model, role: .sherlock)
        }
    }
}

struct NeedsYouPanel: View {
    @ObservedObject var model: AppModel
    let summary: NeedsYouSummary
    @State private var answers: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Needs You").font(.headline)
                Spacer()
                Text(summary.active.isEmpty ? "queue empty (\(summary.resolvedCount) resolved)" : "\(summary.active.count) open")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(summary.active, id: \.question) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.subject)\(entry.blocking ? " [blocking]" : "")").font(.subheadline.weight(.medium))
                    Text(entry.question).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("your decision", text: Binding(
                            get: { answers[entry.question] ?? "" },
                            set: { answers[entry.question] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Button("Resolve") {
                            let answer = answers[entry.question] ?? "(no answer given)"
                            Task {
                                await model.resolveNeedsYou(
                                    subject: entry.subject, question: entry.question, answer: answer
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled((answers[entry.question] ?? "").isEmpty)
                    }
                }
                .padding(8)
                .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIOSDesign.token(.surfacePanel), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

/// Expert Card: direct conversation with one expert over a real worker
/// session (docs 06/07). Output stays generatedContent.
struct ExpertCard: View {
    @ObservedObject var model: AppModel
    let role: ExpertRole
    @State private var chat: ExpertChatModel?
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.crop.circle")
                Text("Expert — \(displayName)").font(.headline)
                Spacer()
                if chat == nil {
                    Button("Consult") { start() }
                } else if chat?.isRunning != true {
                    Button("End") { Task { await chat?.end(); chat = nil } }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            if let chat {
                ForEach(chat.transcript.suffix(6)) { message in
                    Text(message.text)
                        .font(.caption)
                        .foregroundStyle(message.role == .assistant ? .primary : .secondary)
                        .lineLimit(3)
                        .padding(6)
                        .background(AIOSDesign.token(.surfacePanel), in: RoundedRectangle(cornerRadius: 6))
                }
                HStack {
                    TextField("ask…", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)
                    Button("Send", action: send)
                        .disabled(input.isEmpty || chat.isRunning)
                }
            } else {
                Text("stable identity above interchangeable model backends").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIOSDesign.token(.surfacePanel), in: RoundedRectangle(cornerRadius: 8))
    }

    private var displayName: String {
        switch role {
        case .linus: "Linus"
        case .jobs: "Jobs"
        case .einstein: "Einstein"
        case .sherlock: "Sherlock"
        case .henson: "Henson"
        case .chloe: "Chloe"
        case .concierge: "Concierge"
        case .specialist(let name): name
        }
    }

    private func start() {
        chat = ExpertChatModel(expertRole: role)
        Task {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            try? await chat?.startConsultation(workerURL: packageRoot.appendingPathComponent(".build/debug/InferenceWorker"))
        }
    }

    private func send() {
        let text = input
        guard !text.isEmpty, let chat else { return }
        input = ""
        Task { _ = try? await chat.send(userText: text) }
    }
}

struct NotesInboxPanel: View {
    @ObservedObject var model: AppModel
    @State private var notes: [NoteRecord] = []
    @State private var inbox: [InboxItemRecord] = []
    @State private var newNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Desk Notes · Inbox").font(.headline)
            HStack {
                TextField("new note", text: $newNote)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let text = newNote
                    newNote = ""
                    Task {
                        _ = await model.createNote(text: text)
                        await reload()
                    }
                }
                .disabled(newNote.isEmpty)
            }
            ForEach(notes) { note in
                HStack {
                    Text(note.text).font(.callout).lineLimit(2)
                    Spacer()
                    Button("→ Goal") { Task { await model.promoteNote(id: note.id, target: "GOAL"); await reload() } }
                    Button("→ Pin") { Task { await model.promoteNote(id: note.id, target: "TIMELINE_PIN"); await reload() } }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            ForEach(inbox.filter { !$0.discarded }) { item in
                HStack {
                    Text(item.text).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button("→ Task") { Task { await model.promoteInboxItem(id: item.id, target: "TASK"); await reload() } }
                    Button("Discard") { Task { await model.promoteInboxItem(id: item.id, target: "DISCARDED"); await reload() } }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            if notes.isEmpty && inbox.isEmpty {
                Text("nothing captured").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIOSDesign.token(.surfacePanel), in: RoundedRectangle(cornerRadius: 8))
        .task { await reload() }
    }

    private func reload() async {
        notes = await model.loadNotes()
        inbox = await model.loadInbox()
    }
}

struct CheckpointsPanel: View {
    @ObservedObject var model: AppModel
    let state: ProjectState
    @State private var branchReason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Checkpoints").font(.headline)
                Spacer()
                Button("Checkpoint Now") {
                    Task { _ = await model.createCheckpoint(note: "from shell"); await model.refresh() }
                }
            }
            ForEach(state.checkpoints, id: \.self) { checkpointID in
                HStack {
                    Text(checkpointID).font(.caption.monospaced())
                    Spacer()
                    TextField("branch reason", text: $branchReason)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                    Button("Branch") {
                        let reason = branchReason.isEmpty ? "branched from shell" : branchReason
                        branchReason = ""
                        Task { _ = await model.branchFrom(checkpointID: checkpointID, reason: reason) }
                    }
                    Button("Restore") {
                        Task { await model.restore(checkpointID: checkpointID, note: "restored from shell") }
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            ForEach(state.branches, id: \.newPlanRevisionID) { branch in
                Text("branch → \(branch.newPlanRevisionID.rawValue.uuidString.prefix(8)) from \(branch.fromCheckpointID): \(branch.reason)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if state.checkpoints.isEmpty {
                Text("no checkpoints yet").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIOSDesign.token(.surfacePanel), in: RoundedRectangle(cornerRadius: 8))
    }
}

public struct HomeView: View {
    @ObservedObject var model: AppModel
    @State private var conciergeInput = ""

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Work Runtime").font(.title.weight(.bold))
            HStack {
                Image(systemName: "sparkles")
                TextField("goal: … / note: … / inbox: … / ask: …", text: $conciergeInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let raw = conciergeInput
                        conciergeInput = ""
                        Task { await model.submitConcierge(raw) }
                    }
                if let last = model.lastRouting {
                    Text(last).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            if model.stopEngaged {
                Label("Emergency Stop engaged — automation halted", systemImage: "octagon.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
            }
            ProjectDesktopView(model: model)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 520)
        .background(
            // Keyboard-first navigation (docs 06): declared shortcuts.
            Group {
                Button("p1") { Task { await model.returnToNow() } }.keyboardShortcut(.cancelAction)
            }
        )
    }
}

/// Event ruler with branch lanes over the scrub range (docs 06: branches
/// as lanes; the playhead snaps to meaningful history).
struct TimelineRulerView: View {
    @ObservedObject var model: AppModel
    @State private var ruler: TimelineRuler = TimelineRuler(totalEvents: 0, marks: [], lanes: [])

    var body: some View {
        let position = model.historicalState?.lastSequence ?? model.state?.lastSequence ?? 0
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                ForEach(ruler.marks) { mark in
                    Rectangle()
                        .fill(color(for: mark.label))
                        .frame(width: 2, height: mark.sequence == position ? 18 : 10)
                        .help("\(mark.label) @#\(mark.sequence)")
                }
                Spacer(minLength: 0)
            }
            .frame(height: 20)
            ForEach(ruler.lanes) { lane in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(lane.branchID == nil ? Color.accentColor.opacity(0.5) : Color.purple.opacity(0.5))
                        .frame(width: laneWidth(for: lane), height: 4)
                    Text(lane.label)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            if let nearest = TimelineRulerViewModel.nearestMark(to: position, in: ruler.marks) {
                Text("nearest: \(nearest.label) @#\(nearest.sequence)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .task {
            ruler = TimelineRulerViewModel.build(from: model.storeForRuler)
        }
        .onChange(of: model.state?.lastSequence) { _ in
            ruler = TimelineRulerViewModel.build(from: model.storeForRuler)
        }
    }

    private func color(for label: String) -> Color {
        switch label {
        case "Verified": return .green
        case "Verification failed": return .red
        case "Crash": return .orange
        case "Branch", "Restored", "Checkpoint": return .purple
        default: return .accentColor
        }
    }

    private func laneWidth(for lane: BranchLane) -> CGFloat {
        let total = max(Double(ruler.totalEvents), 1)
        let start = Double(lane.startsAtSequence) / total
        let end = Double(lane.endsAtSequence ?? ruler.totalEvents) / total
        return max(24, (end - start) * 320)
    }
}
