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

    public let projectID: ProjectID
    private let store: JournalStore
    public let emergencyStop: EmergencyStop

    public init(store: JournalStore) {
        self.store = store
        self.projectID = store.projectID
        self.emergencyStop = EmergencyStop(journal: store)
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
    public func engageEmergencyStop() {
        Task {
            try? await emergencyStop.engage(reason: "user pressed the stop control")
            await refresh()
        }
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
            Text(card.title).font(.headline)
            Text(card.body).font(.body).foregroundStyle(.secondary)
            Text("Why: \(card.whyHere)").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
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
                .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            }

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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
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

/// Phase 3 panels: Needs You, Project Health, Projected Future. Every line
/// reads projected state; nothing decorative.
struct DepthPanels: View {
    @ObservedObject var model: AppModel
    let rendered: ProjectState

    var body: some View {
        let needsYou = NeedsYouViewModel.summary(from: rendered)
        let health = ProjectHealth.compute(from: rendered)
        let future = FutureViewModel.items(from: rendered)

        Group {
            CardView(card: CardSummary(
                title: "Needs You",
                body: needsYou.active.isEmpty
                    ? "queue empty (\(needsYou.resolvedCount) resolved)"
                    : needsYou.active.map { "\($0.subject)\($0.blocking ? " [blocking]" : "")" }.joined(separator: " · "),
                whyHere: "blocked on human decisions"
            ))
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
        }
    }
}

public struct HomeView: View {
    @ObservedObject var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Work Runtime").font(.title.weight(.bold))
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
    }
}
