import Foundation
import AIOSCore
import ProjectKernel

// The Chloe Deck: honest animation for the computer-use expert. Every
// visual state is a pure projection of real journal events — the ghost
// hand, the authority metronome, and the uncertainty constellation encode
// lease vitality, action lifecycle, and outcome truth (Constitution: motion
// = monitorable real activity; decorative spinners are forbidden).

public enum HandState: String, Sendable, Equatable {
    case idle        // no lease, nothing happening
    case hovering    // lease held, observing (pulses on real AX queries)
    case reaching    // action authorized, executing
    case shadowMime  // shadow mode: mimes contact, never lands
    case uncertain   // outcome UNKNOWN, awaiting reconciliation
    case recoiled    // user interaction outranked automation
    case frozen      // Emergency Stop
}

public enum MetronomeState: String, Sendable, Equatable {
    case still      // no lease
    case swinging   // held, uncontested
    case contested  // another request was denied this lease
    case slapped    // invalidated by user interaction
}

public enum StarPhase: String, Sendable, Equatable {
    case settled    // verified/succeeded
    case pulsing    // UNKNOWN, unreconciled
    case collapsed  // failed/rejected
}

public struct ActionStar: Sendable, Equatable, Identifiable {
    public var id: ActionID
    public var phase: StarPhase
    public var label: String
}

public struct ChloeVisualState: Sendable, Equatable {
    public var hand: HandState
    public var metronome: MetronomeState
    public var constellation: [ActionStar]
    public var contact: Bool // true only when a real (non-shadow) press is live
    public var staticGlyph: String? // Reduce Motion fallback

    public static func compute(from state: ProjectState) -> ChloeVisualState {
        let emergency = state.interventions.contains { $0.contains("Emergency Stop") }
        let chloeActions = state.actions.values
            .filter { $0.request.capability == .operateComputer || $0.request.requestedBy == .chloe }
        let leaseEvents = state.leaseEvents

        // Metronome: lease vitality from the last relevant event.
        let metronome: MetronomeState
        if emergency {
            metronome = .slapped
        } else if leaseEvents.isEmpty {
            metronome = .still
        } else {
            let invalidated = leaseEvents.contains { !$0.granted && $0.reason.contains("invalidated") }
            let grantedAny = leaseEvents.contains(where: \.granted)
            let denied = leaseEvents.contains { !$0.granted && $0.reason.contains("denied") }
            if invalidated {
                metronome = .slapped
            } else if grantedAny && denied {
                metronome = .contested
            } else if grantedAny {
                metronome = .swinging
            } else {
                metronome = .still
            }
        }

        // Hand: most significant live condition wins.
        let hand: HandState
        if emergency {
            hand = .frozen
        } else if leaseEvents.contains(where: { !$0.granted && $0.reason.contains("invalidated") }) {
            hand = .recoiled // the user outranks automation — even mid-action
        } else {
            let live = chloeActions.filter { entry in
                entry.result == nil || entry.result?.outcome == .unknown
            }
            if let unresolved = live.first(where: { $0.result?.outcome == .unknown }) {
                hand = .uncertain
            } else if let executing = live.first {
                hand = executing.request.sideEffectClass == .none ? .shadowMime : .reaching
            } else if leaseEvents.contains(where: \.granted) {
                hand = .hovering
            } else {
                hand = .idle
            }
        }

        let contact = hand == .reaching

        // Constellation: every resolved or live Chloe action is a star,
        // in real journal order.
        let byID = Dictionary(uniqueKeysWithValues: chloeActions.map { ($0.request.actionID, $0) })
        let ordered = state.actionOrder.compactMap { byID[$0] }
        let stars: [ActionStar] = ordered.map { entry in
            let phase: StarPhase
            switch entry.result?.outcome {
            case .succeeded: phase = .settled
            case nil: phase = .pulsing // in flight
            case .unknown: phase = .pulsing
            case .failed, .rejected, .stalePrecondition, .timedOut, .cancelled: phase = .collapsed
            case .partiallySucceeded: phase = .pulsing
            }
            return ActionStar(
                id: entry.request.actionID,
                phase: phase,
                label: "\(entry.request.operation) → \(entry.request.target.prefix(40))"
            )
        }

        return ChloeVisualState(
            hand: hand,
            metronome: metronome,
            constellation: stars,
            contact: contact,
            staticGlyph: glyph(for: hand)
        )
    }

    private static func glyph(for hand: HandState) -> String {
        switch hand {
        case .idle: "◦"
        case .hovering: "◎"
        case .reaching: "☞"
        case .shadowMime: "◌"
        case .uncertain: "?"
        case .recoiled: "✖"
        case .frozen: "❄"
        }
    }
}
