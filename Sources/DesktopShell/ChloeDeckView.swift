import Foundation
import SwiftUI
import AIOSCore
import ProjectKernel

// The Chloe Deck panel: ghost hand, authority metronome, uncertainty
// constellation. Every animation below is driven by ChloeVisualState,
// a pure projection of journal events — never by timers or fake cycles.
// Reduce Motion swaps the hand for its static glyph.

public struct ChloeDeckView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visual: ChloeVisualState {
        ChloeVisualState.compute(from: model.displayState ?? ProjectState(projectID: model.projectID))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hand.point.up.left")
                Text("Chloe — Computer Control").font(.headline)
                Spacer()
                Text(visual.metronome.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(metronomeTint)
                Text(visual.hand.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(handTint)
            }

            HStack(alignment: .center, spacing: 24) {
                GhostHandView(hand: visual.hand, reduceMotion: reduceMotion, glyph: visual.staticGlyph)
                    .frame(width: 150, height: 150)

                MetronomeView(state: visual.metronome, reduceMotion: reduceMotion)
                    .frame(width: 90, height: 150)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Actions").font(.subheadline.weight(.medium))
                    if visual.constellation.isEmpty {
                        Text("no computer actions yet").font(.caption).foregroundStyle(.tertiary)
                    }
                    ForEach(visual.constellation.suffix(6)) { star in
                        HStack(spacing: 6) {
                            StarView(phase: star.phase, reduceMotion: reduceMotion)
                            Text(star.label).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIOSDesign.token(.surfacePanel), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chloe computer control: \(visual.hand.rawValue), lease \(visual.metronome.rawValue)")
    }

    private var handTint: Color {
        switch visual.hand {
        case .idle: return .secondary
        case .hovering: return AIOSDesign.token(.textPrimary)
        case .reaching: return .accentColor
        case .shadowMime: return .purple
        case .uncertain: return AIOSDesign.token(.attentionNeeded)
        case .recoiled: return .red
        case .frozen: return .blue
        }
    }

    private var metronomeTint: Color {
        switch visual.metronome {
        case .still: return .secondary
        case .swinging: return .accentColor
        case .contested: return AIOSDesign.token(.attentionNeeded)
        case .slapped: return .red
        }
    }
}

/// The ghost hand: state-driven gesture, contact only on real execution.
struct GhostHandView: View {
    let hand: HandState
    let reduceMotion: Bool
    let glyph: String?

    var body: some View {
        ZStack {
            // Contact ripple — only for real presses (shadow mimes bend away).
            if hand == .reaching {
                Circle()
                    .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                    .frame(width: 60, height: 60)
                    .scaleEffect(hand == .reaching ? 1.6 : 0.4)
                    .opacity(hand == .reaching ? 0 : 0.8)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: hand)
            }

            if reduceMotion, let glyph {
                Text(glyph)
                    .font(.system(size: 56))
                    .foregroundStyle(tint)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(tint)
                    .opacity(opacity)
                    .scaleEffect(scale)
                    .offset(y: offsetY)
                    .animation(reduceMotion ? nil : animation, value: hand)
            }

            if hand == .frozen {
                // Shattered static: the freeze is the state.
                ForEach(0..<8, id: \.self) { index in
                    Rectangle()
                        .fill(Color.blue.opacity(0.4))
                        .frame(width: 3, height: CGFloat(8 + index * 3))
                        .rotationEffect(.degrees(Double(index) * 45))
                        .offset(x: index.isMultiple(of: 2) ? -30 : 30)
                }
            }
        }
        .help("Chloe: \(hand.rawValue) — lease-gated, journaled, stoppable")
    }

    private var symbol: String {
        switch hand {
        case .idle: "hand.raised"
        case .hovering: "hand.point.up.left"
        case .reaching: "hand.point.down"
        case .shadowMime: "hand.point.up.left"
        case .uncertain: "questionmark.circle"
        case .recoiled: "hand.raised"
        case .frozen: "snowflake"
        }
    }

    private var tint: Color {
        switch hand {
        case .idle: return .secondary
        case .hovering: return .primary
        case .reaching: return .accentColor
        case .shadowMime: return .purple.opacity(0.55) // translucent: a hologram
        case .uncertain: return .orange
        case .recoiled: return .red
        case .frozen: return .blue
        }
    }

    private var opacity: Double {
        hand == .shadowMime ? 0.45 : 1.0
    }

    private var scale: CGFloat {
        switch hand {
        case .reaching: return 1.15
        case .recoiled: return 0.8
        case .frozen: return 0.9
        default: return 1.0
        }
    }

    private var offsetY: CGFloat {
        switch hand {
        case .reaching: return 14   // descends toward the target
        case .recoiled: return -14  // snaps back
        default: return 0
        }
    }

    private var animation: Animation {
        switch hand {
        case .recoiled: return .spring(response: 0.2, dampingFraction: 0.5) // the snap
        case .reaching: return .spring(response: 0.35, dampingFraction: 0.7)
        case .frozen: return .linear(duration: 0) // frozen means no motion
        default: return .easeInOut(duration: 0.4)
        }
    }
}

/// The authority metronome: a pendulum that swings only while a lease
/// lives, stops dead when the user outranks automation.
struct MetronomeView: View {
    let state: MetronomeState
    let reduceMotion: Bool

    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(AIOSDesign.token(.surfacePanel))
                    .frame(width: 60, height: 110)
                PendulumShape()
                    .stroke(tint, lineWidth: 2)
                    .frame(width: 44, height: 90)
                    .rotationEffect(.degrees(angle))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: phase)
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                    .offset(x: pendulumBobX, y: 38)
            }
            Text(state.rawValue)
                .font(.caption2)
                .foregroundStyle(tint)
        }
        .onAppear {
            if state == .swinging || state == .contested {
                phase = 1 // start the swing only for live leases
            }
        }
        .onChange(of: state) { newState in
            if newState == .swinging || newState == .contested {
                phase = phase == 1 ? 0 : 1
            }
        }
    }

    private var angle: Double {
        guard state == .swinging || state == .contested else { return 0 }
        return phase == 1 ? 18 : -18
    }

    private var pendulumBobX: CGFloat {
        guard state == .swinging || state == .contested else { return 0 }
        return phase == 1 ? 14 : -14
    }

    private var tint: Color {
        switch state {
        case .still: return .secondary
        case .swinging: return .accentColor
        case .contested: return .orange
        case .slapped: return .red
        }
    }
}

struct PendulumShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// Constellation stars: settled, pulsing (unknown), collapsed.
struct StarView: View {
    let phase: StarPhase
    let reduceMotion: Bool

    @State private var pulse = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11))
            .foregroundStyle(tint)
            .scaleEffect(phase == .pulsing && pulse ? 1.4 : 1.0)
            .opacity(phase == .pulsing && pulse ? 0.6 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear {
                if phase == .pulsing {
                    pulse = true // only unknowns pulse — until reconciled
                }
            }
    }

    private var symbol: String {
        switch phase {
        case .settled: return "star.fill"
        case .pulsing: return "sparkle"
        case .collapsed: return "minus.circle"
        }
    }

    private var tint: Color {
        switch phase {
        case .settled: return .green
        case .pulsing: return .orange
        case .collapsed: return .red
        }
    }
}
