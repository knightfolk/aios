import Foundation
import SwiftUI
import AIOSCore
import EventJournal
import ProjectKernel

// Interactive panels for the desktop: Needs You resolution, Notes/Inbox
// promotion, Checkpoints branch/restore, Expert consultations, the timeline
// strip and event ruler. Every action maps to a journaling engine call.

// MARK: - Timeline strip (header chips)

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
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint(for: segment.kind).opacity(0.16), in: Capsule())
                .foregroundStyle(tint(for: segment.kind))
                .help(segment.detail)
            }
        }
    }

    private func tint(for kind: TimelineSegmentKind) -> Color {
        switch kind {
        case .past: return .secondary
        case .now: return .accentColor
        case .future: return .blue
        case .gaps: return .orange
        }
    }
}

// MARK: - Timeline event ruler

struct TimelineRulerView: View {
    @ObservedObject var model: AppModel
    @State private var ruler = TimelineRuler(totalEvents: 0, marks: [], lanes: [])

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
                        .fill(lane.branchID == nil ? Color.indigo.opacity(0.5) : Color.purple.opacity(0.5))
                        .frame(width: laneWidth(for: lane), height: 4)
                    Text(lane.label)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .task { ruler = TimelineRulerViewModel.build(from: model.storeForRuler) }
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
        return max(24, (end - start) * 640)
    }
}

// MARK: - Needs You (with resolution)

struct NeedsYouPanel: View {
    @ObservedObject var model: AppModel
    let summary: NeedsYouSummary
    @State private var answers: [String: String] = [:]

    var body: some View {
        GlassPanel(
            title: "Needs You", symbol: "person.badge.questionmark", tint: .orange,
            trailing: AnyView(Text(summary.active.isEmpty ? "clear · \(summary.resolvedCount) resolved" : "\(summary.active.count) open")
                .font(.caption2).foregroundStyle(.tertiary))
        ) {
            if summary.active.isEmpty {
                Text("nothing needs your attention").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(summary.active, id: \.question) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.subject)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(entry.blocking ? .orange : .primary)
                    Text(entry.question).font(.callout).foregroundStyle(.secondary)
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
                        .accessibilityLabel("Resolve decision: \(entry.subject)")
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - Desk Notes + Inbox (with promotion)

struct NotesInboxPanel: View {
    @ObservedObject var model: AppModel
    @State private var notes: [NoteRecord] = []
    @State private var inbox: [InboxItemRecord] = []
    @State private var newNote = ""

    var body: some View {
        GlassPanel(title: "Desk Notes · Inbox", symbol: "note.text", tint: .yellow) {
            HStack {
                TextField("capture a note", text: $newNote)
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
        .task { await reload() }
    }

    private func reload() async {
        notes = await model.loadNotes()
        inbox = await model.loadInbox()
    }
}

// MARK: - Checkpoints (branch / restore)

struct CheckpointsPanel: View {
    @ObservedObject var model: AppModel
    let state: ProjectState
    @State private var branchReason = ""

    var body: some View {
        GlassPanel(title: "Checkpoints", symbol: "smallcircle.filled.circle", tint: .purple) {
            HStack {
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
    }
}

// MARK: - Expert consultation card

struct ExpertCard: View {
    @ObservedObject var model: AppModel
    let role: ExpertRole
    @State private var chat: ExpertChatModel?
    @State private var input = ""

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

    var body: some View {
        GlassPanel(title: "Expert — \(displayName)", symbol: "person.crop.circle", tint: .indigo) {
            if let chat {
                ForEach(chat.transcript.suffix(4)) { message in
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
                Text("start a consultation over a live worker session")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button("Consult") { start() }
            }
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
