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

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Project \(model.projectID.rawValue.uuidString.prefix(8))")
                    .font(.title2.weight(.semibold))
                Spacer()
                TimelineStrip(segments: TimelineViewModel.segments(from: model.state ?? ProjectState(projectID: model.projectID)))
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(CardGridViewModel.cards(from: model.state ?? ProjectState(projectID: model.projectID))) { card in
                        CardView(card: card)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 480)
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
