import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import ComputerControl
@testable import DesktopShell

// The Chloe Deck is honest animation: every visual state maps from real
// journal events (Constitution: motion = monitorable real activity).

@Test func ghostHandStateMapsFromEngineEvents() {
    var state = ProjectState(projectID: ProjectID())

    // No lease, no actions: observing idly.
    #expect(ChloeVisualState.compute(from: state).hand == .idle)

    // Lease granted to Chloe: the hand wakes.
    state.leaseEvents.append(LeaseEventRecord(granted: true, owner: "t1/chloe", reason: "granted: export"))
    #expect(ChloeVisualState.compute(from: state).hand == .hovering)

    // A computer-control action in flight: reaching.
    let actionID = ActionID()
    state.actions[actionID] = ActionEntry(request: ActionRequest(
        actionID: actionID, workPackageID: WorkPackageID(), requestedBy: .chloe,
        capability: .operateComputer, operation: "ax.typeText", target: "AX:focus",
        parameters: [:], expectedEffect: "types", sideEffectClass: .local,
        reversibility: .reversible, idempotency: .idempotent,
        requiredPermission: .operateComputer, verificationPlan: "read back"
    ))
    #expect(ChloeVisualState.compute(from: state).hand == .reaching)

    // Result succeeds: retract to hovering.
    state.actions[actionID]?.result = ActionResult(actionID: actionID, outcome: .succeeded, startedAt: Date(), endedAt: Date())
    #expect(ChloeVisualState.compute(from: state).hand == .hovering)

    // Unknown outcome: uncertain hold.
    state.actions[actionID]?.result = ActionResult(actionID: actionID, outcome: .unknown, startedAt: Date(), endedAt: Date())
    #expect(ChloeVisualState.compute(from: state).hand == .uncertain)

    // User interaction invalidates the lease: recoil.
    state.leaseEvents.append(LeaseEventRecord(granted: false, owner: "t1/chloe", reason: "invalidated: user interaction outranks automation"))
    #expect(ChloeVisualState.compute(from: state).hand == .recoiled)

    // Emergency stop: frozen.
    state.interventions.append("Emergency Stop engaged: user pressed the red button")
    #expect(ChloeVisualState.compute(from: state).hand == .frozen)
}

@Test func shadowModeHandNeverClaimsContact() {
    var state = ProjectState(projectID: ProjectID())
    state.leaseEvents.append(LeaseEventRecord(granted: true, owner: "t1/chloe", reason: "granted: shadow drill"))
    state.actions[ActionID()] = ActionEntry(request: ActionRequest(
        actionID: ActionID(), workPackageID: WorkPackageID(), requestedBy: .chloe,
        capability: .operateComputer, operation: "ax.press", target: "button=Save",
        parameters: [:], expectedEffect: "shadow only", sideEffectClass: .none,
        reversibility: .reversible, idempotency: .idempotent,
        requiredPermission: .operateComputer, verificationPlan: "shadow"
    ))
    // Shadow operations (sideEffectClass none) show the mime, never a press.
    let visual = ChloeVisualState.compute(from: state)
    #expect(visual.hand == .shadowMime)
    #expect(visual.contact == false)
}

@Test func metronomeTracksLeaseVitality() {
    var state = ProjectState(projectID: ProjectID())

    // No lease: still.
    #expect(ChloeVisualState.compute(from: state).metronome == .still)

    // Granted and uncontested: swinging.
    state.leaseEvents.append(LeaseEventRecord(granted: true, owner: "t1/chloe", reason: "granted: p"))
    #expect(ChloeVisualState.compute(from: state).metronome == .swinging)

    // A denial means contention: contested beat.
    state.leaseEvents.append(LeaseEventRecord(granted: false, owner: "t2/chloe", reason: "denied: conflicting lease held by t1/chloe"))
    #expect(ChloeVisualState.compute(from: state).metronome == .contested)

    // Invalidated: slapped still.
    state.leaseEvents.append(LeaseEventRecord(granted: false, owner: "t1/chloe", reason: "invalidated: user interaction"))
    #expect(ChloeVisualState.compute(from: state).metronome == .slapped)
}

@Test func constellationCollectsRealActionOutcomes() {
    let projectID = ProjectID()
    var state = ProjectState(projectID: projectID)
    let good = ActionID()
    let unknown = ActionID()
    let failed = ActionID()
    for (id, outcome) in [(good, ActionOutcome.succeeded), (unknown, ActionOutcome.unknown), (failed, ActionOutcome.failed)] {
        let request = ActionRequest(
            actionID: id, workPackageID: WorkPackageID(), requestedBy: .chloe,
            capability: .operateComputer, operation: "ax.press", target: "x",
            parameters: [:], expectedEffect: "e", sideEffectClass: .local,
            reversibility: .reversible, idempotency: .idempotent,
            requiredPermission: .operateComputer, verificationPlan: "v"
        )
        state = Projection.apply(state, EventRecord(
            sequence: state.lastSequence + 1, recordedAt: Date(), projectID: projectID,
            event: .actionRequested(.init(request: request))
        ))
        state = Projection.apply(state, EventRecord(
            sequence: state.lastSequence + 1, recordedAt: Date(), projectID: projectID,
            event: .actionExecuted(.init(result: ActionResult(actionID: id, outcome: outcome, startedAt: Date(), endedAt: Date())))
        ))
    }

    let stars = ChloeVisualState.compute(from: state).constellation
    #expect(stars.count == 3)
    #expect(stars.contains { $0.phase == .settled })
    #expect(stars.contains { $0.phase == .pulsing })   // unknown stays open
    #expect(stars.contains { $0.phase == .collapsed }) // failed
    // Ordered by insertion = real history.
    #expect(stars.first?.id == good)
}

@Test func reduceMotionFallsBackToGlyphs() {
    var state = ProjectState(projectID: ProjectID())
    state.leaseEvents.append(LeaseEventRecord(granted: true, owner: "t/chloe", reason: "granted: p"))
    let visual = ChloeVisualState.compute(from: state)
    #expect(visual.staticGlyph != nil) // always available; views pick per setting
}
