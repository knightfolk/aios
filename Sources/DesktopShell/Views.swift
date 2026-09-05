import Foundation
import SwiftUI
import AIOSCore
import EventJournal
import ProjectKernel
import ExpertRuntime

// The AI-OS desktop: a full-bleed wallpaper canvas with glassy panels in a
// deliberate layout — top status bar, prominent Concierge, timeline band,
// three-panel workspace, expert dock. macOS-native feel: ultraThinMaterial,
// rounded 14, SF Symbols, subtle strokes. Everything renders projections.

// MARK: - Desktop canvas

struct DesktopCanvas<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.07, green: 0.09, blue: 0.16), Color(red: 0.10, green: 0.10, blue: 0.13), Color(red: 0.05, green: 0.06, blue: 0.10)]
                    : [Color(red: 0.85, green: 0.89, blue: 0.98), Color(red: 0.93, green: 0.92, blue: 0.96), Color(red: 0.80, green: 0.86, blue: 0.95)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: scheme == .dark ? [Color.indigo.opacity(0.25), .clear] : [Color.white.opacity(0.5), .clear],
                center: .topTrailing,
                startRadius: 50, endRadius: 900
            )
            .ignoresSafeArea()
            content
        }
    }
}

// MARK: - Glass panel primitive

struct GlassPanel<Content: View>: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    var trailing: AnyView? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                if let trailing { trailing }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Root: the desktop

public struct HomeView: View {
    @ObservedObject var model: AppModel
    @State private var conciergeInput = ""
    @State private var clock: Date = Date()
    @Environment(\.colorScheme) private var colorScheme

    public init(model: AppModel) {
        self.model = model
    }

    private var rendered: ProjectState {
        model.displayState ?? ProjectState(projectID: model.projectID)
    }

    private var scrub: ScrubPosition {
        ScrubPosition(
            sequence: model.historicalState?.lastSequence ?? model.state?.lastSequence ?? 0,
            lastSequence: model.state?.lastSequence ?? 0
        )
    }

    public var body: some View {
        DesktopCanvas {
            VStack(spacing: 14) {
                headerBar
                ConciergeBar(model: model, input: $conciergeInput)
                if model.layout.showsTimelineRuler {
                    timelineBand
                }
                if scrub.isHistorical {
                    historyBanner
                }
                workspace
                ExpertDock()
            }
            .padding(20)
        }
        .frame(minWidth: 1200, minHeight: 760)
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "cubetransparent")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("Demo Project")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Project \(model.projectID.rawValue.uuidString.prefix(8)) · AI Work Runtime")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.stopEngaged {
                Label("Emergency Stop", systemImage: "octagon.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
            }
            TimelineStrip(segments: TimelineViewModel.segments(from: rendered))
            Text(clock, style: .time)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                Task { @MainActor in clock = Date() }
            }
        }
    }

    // MARK: Concierge

    private struct ConciergeBar: View {
        @ObservedObject var model: AppModel
        @Binding var input: String

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(.tint)
                TextField("Ask, command, or capture —  goal: · note: · inbox: · ask:", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .onSubmit {
                        let raw = input
                        input = ""
                        Task { await model.submitConcierge(raw) }
                    }
                    .accessibilityLabel("Concierge input")
                if let last = model.lastRouting {
                    Text(last)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        }
    }

    // MARK: Timeline band

    private var timelineBand: some View {
        GlassPanel(title: "Timeline", symbol: "clock.arrow.circlepath", tint: .indigo) {
            TimelineRulerView(model: model)
            HStack(spacing: 16) {
                Text("Scrub").font(.caption)
                Slider(
                    value: Binding(
                        get: { Double(model.historicalState?.lastSequence ?? model.state?.lastSequence ?? 0) },
                        set: { model.enterHistorical(at: UInt64($0)) }
                    ),
                    in: 0...Double(max(model.state?.lastSequence ?? 0, 1)),
                    step: scrubStep
                )
                .disabled(model.state == nil)
                .accessibilityLabel("Timeline position \(scrub.sequence) of \(scrub.lastSequence)")
                Text("#\(scrub.sequence)/\(scrub.lastSequence)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 140)
    }

    /// Snap granularity: 1 for short journals; coarser steps keep 50k-event
    /// journals scrubable.
    private var scrubStep: Double {
        let total = model.state?.lastSequence ?? 0
        if total < 100 { return 1 }
        if total < 1_000 { return 5 }
        if total < 10_000 { return 25 }
        return 100
    }

    private var historyBanner: some View {        HStack {
            Label("HISTORICAL VIEW — recorded state at #\(scrub.sequence); inspection only", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Return to Now") { model.returnToNow() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(10)
        .background(AIOSDesign.historicalSurface(colorScheme), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Workspace: three columns

    private var workspace: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 14) {
                NeedsYouPanel(model: model, summary: NeedsYouViewModel.summary(from: rendered))
                CheckpointsPanel(model: model, state: rendered)
                HealthPanel(health: ProjectHealth.compute(from: rendered))
            }
            VStack(spacing: 14) {
                ActivityCenterPanel(model: model, rendered: rendered)
                FuturePanel(items: FutureViewModel.items(from: rendered))
                NotesInboxPanel(model: model)
            }
            VStack(spacing: 14) {
                ChloeDeckView(model: model)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private struct HealthPanel: View {
        let health: ProjectHealth

        var body: some View {
            GlassPanel(title: "Project Health", symbol: "pulse", tint: .mint) {
                VStack(alignment: .leading, spacing: 6) {
                    countMeter("Goal criteria", value: health.goalCriteriaCovered, of: max(health.goalCriteriaTotal, 1), tint: .mint)
                    fractionMeter("Verification", value: health.verificationCoverage, tint: .green)
                    HStack(spacing: 10) {
                        chip("Blockers \(health.blockers)", tone: health.blockers > 0 ? .red : .secondary)
                        chip("Decisions \(health.unresolvedDecisions)", tone: health.unresolvedDecisions > 0 ? .orange : .secondary)
                        chip("Gaps \(health.suspectedGaps)", tone: health.suspectedGaps > 0 ? .orange : .secondary)
                        chip("Stale \(health.staleEvidence)", tone: health.staleEvidence > 0 ? .red : .secondary)
                    }
                }
            }
        }

        private func countMeter(_ label: String, value: Int, of total: Int, tint: Color) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label).font(.caption)
                    Spacer()
                    Text("\(value)/\(total)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(value), total: Double(total))
                    .tint(tint)
            }
        }

        private func fractionMeter(_ label: String, value: Double, tint: Color) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label).font(.caption)
                    Spacer()
                    Text("\(Int(value * 100))%").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                ProgressView(value: value)
                    .tint(tint)
            }
        }

        private func chip(_ text: String, tone: Color) -> some View {
            Text(text)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tone.opacity(0.14), in: Capsule())
                .foregroundStyle(tone == .secondary ? Color.secondary : tone)
        }
    }

    private struct FuturePanel: View {
        let items: [FutureItem]

        var body: some View {
            GlassPanel(
                title: "Projected Future", symbol: "calendar.badge.clock", tint: .blue,
                trailing: AnyView(Text("planned — has not happened").font(.caption2).foregroundStyle(.tertiary))
            ) {
                if items.isEmpty {
                    Text("no planned tasks").font(.caption).foregroundStyle(.tertiary)
                }
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "circle.dashed").foregroundStyle(.tint)
                        Text(item.objective).font(.callout).lineLimit(1)
                        Spacer()
                        Text(item.ownerDisplay).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

extension FutureItem {
    var ownerDisplay: String {
        switch owner {
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
}

// MARK: - Expert dock (bottom of the desktop)

struct ExpertDock: View {
    var body: some View {
        HStack(spacing: 18) {
            ForEach(ExpertTeam.permanentTeam(), id: \.identity) { expert in
                ExpertDockItem(expert: expert)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

struct ExpertDockItem: View {
    let expert: Expert

    private var initials: String {
        String(expert.displayName.prefix(2))
    }

    private var ring: LinearGradient {
        switch expert.role {
        case .linus: LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
        case .jobs: LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom)
        case .einstein: LinearGradient(colors: [.teal, .mint], startPoint: .top, endPoint: .bottom)
        case .sherlock: LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom)
        case .henson: LinearGradient(colors: [.pink, .red], startPoint: .top, endPoint: .bottom)
        case .chloe: LinearGradient(colors: [.indigo, .blue], startPoint: .top, endPoint: .bottom)
        case .concierge: LinearGradient(colors: [.gray, .secondary], startPoint: .top, endPoint: .bottom)
        case .specialist: LinearGradient(colors: [.gray, .secondary], startPoint: .top, endPoint: .bottom)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().strokeBorder(ring, lineWidth: 2.5)
                    .frame(width: 44, height: 44)
                Text(initials)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Text(expert.displayName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
            Text(expert.domain)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .help("\(expert.displayName) — \(expert.domain): \(expert.responsibilities.joined(separator: ", "))")
        .accessibilityElement(children: .combine)
    }
}
