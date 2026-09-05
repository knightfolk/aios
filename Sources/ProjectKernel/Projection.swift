import Foundation
import AIOSCore
import EventJournal

/// Pure projection from journal events to `ProjectState`. The fold is total:
/// unknown references record a warning and never abort replay — a damaged or
/// partial journal must still project to something inspectable.
public enum Projection {
    public static func apply(_ state: ProjectState, _ record: EventRecord) -> ProjectState {
        var next = state
        next.lastSequence = max(next.lastSequence, record.sequence)

        if record.projectID != next.projectID {
            next.warnings.append("record \(record.sequence) carries foreign projectID \(record.projectID)")
        }

        switch record.event {
        case .projectOpened:
            break

        case .goalCreated(let p):
            next.goals[p.goalRevisionID] = GoalRecord(
                goalRevisionID: p.goalRevisionID,
                originalRequest: p.originalRequest,
                objective: p.objective,
                acceptanceCriteria: p.acceptanceCriteria
            )
            next.activeGoalRevisionID = p.goalRevisionID

        case .goalRevised(let p):
            guard let previous = next.goals[p.previousRevisionID] else {
                next.warnings.append("goalRevised references unknown previous revision \(p.previousRevisionID)")
                return next
            }
            next.goals[p.goalRevisionID] = GoalRecord(
                goalRevisionID: p.goalRevisionID,
                originalRequest: previous.originalRequest,
                objective: previous.objective,
                acceptanceCriteria: previous.acceptanceCriteria,
                previousRevisionID: p.previousRevisionID,
                revisionReason: p.reason
            )
            next.activeGoalRevisionID = p.goalRevisionID

        case .planProposed(let p):
            next.plans[p.planRevisionID] = PlanRecord(
                planRevisionID: p.planRevisionID,
                goalRevisionID: p.goalRevisionID,
                summary: p.summary
            )
            next.activePlanRevisionID = p.planRevisionID

        case .planRevised(let p):
            guard let previous = next.plans[p.previousRevisionID] else {
                next.warnings.append("planRevised references unknown previous revision \(p.previousRevisionID)")
                return next
            }
            next.plans[p.planRevisionID] = PlanRecord(
                planRevisionID: p.planRevisionID,
                goalRevisionID: previous.goalRevisionID,
                summary: previous.summary,
                taskIDs: previous.taskIDs,
                previousRevisionID: p.previousRevisionID,
                revisionRationale: p.rationale
            )
            next.activePlanRevisionID = p.planRevisionID

        case .taskCreated(let p):
            next.tasks[p.taskID] = TaskRecord(
                taskID: p.taskID,
                planRevisionID: p.planRevisionID,
                objective: p.objective,
                owner: p.owner
            )
            if var plan = next.plans[p.planRevisionID] {
                plan.taskIDs.append(p.taskID)
                next.plans[p.planRevisionID] = plan
            }

        case .taskStateChanged(let p):
            guard var task = next.tasks[p.taskID] else {
                next.warnings.append("taskStateChanged references unknown task \(p.taskID)")
                return next
            }
            if p.newState == .complete {
                // Constitution: completion requires passed verification, never
                // a state-change self-report.
                next.warnings.append("taskStateChanged cannot set task \(p.taskID) to Complete; verification event required")
                return next
            }
            task.state = p.newState
            next.tasks[p.taskID] = task

        case .attemptStarted(let p):
            next.attempts[p.attemptID] = AttemptRecord(
                attemptID: p.attemptID,
                taskID: p.taskID,
                workPackageID: p.workPackageID,
                worker: p.worker,
                phase: .running
            )

        case .attemptEnded(let p):
            guard var attempt = next.attempts[p.attemptID] else {
                next.warnings.append("attemptEnded references unknown attempt \(p.attemptID)")
                return next
            }
            attempt.phase = .ended
            attempt.outcome = p.outcome
            next.attempts[p.attemptID] = attempt

        case .modelSelected(let p):
            guard next.attempts[p.attemptID] != nil else {
                next.warnings.append("modelSelected references unknown attempt \(p.attemptID)")
                return next
            }
            next.attempts[p.attemptID]?.modelSelection = RuntimeSelection(
                runtime: p.runtime,
                rationale: p.rationale
            )

        case .contextCompiled(let p):
            guard next.attempts[p.attemptID] != nil else {
                next.warnings.append("contextCompiled references unknown attempt \(p.attemptID)")
                return next
            }
            next.attempts[p.attemptID]?.contextBundle = p.bundle

        case .actionRequested(let p):
            next.actions[p.request.actionID] = ActionEntry(request: p.request)
            next.actionOrder.append(p.request.actionID)

        case .actionAuthorized(let p):
            guard next.actions[p.actionID] != nil else {
                next.warnings.append("actionAuthorized references unknown action \(p.actionID)")
                return next
            }
            next.actions[p.actionID]?.authorized = true

        case .actionExecuted(let p):
            let result = p.result
            guard var entry = next.actions[result.actionID] else {
                next.warnings.append("actionExecuted references unknown action \(result.actionID)")
                return next
            }
            entry.result = result
            next.actions[result.actionID] = entry

            if result.outcome == .unknown {
                if let key = next.attempts.first(where: { $0.value.workPackageID == entry.request.workPackageID })?.key {
                    next.attempts[key]?.unreconciledUnknownActionIDs.insert(result.actionID)
                }
            }

        case .actionReconciled(let p):
            guard var entry = next.actions[p.actionID] else {
                next.warnings.append("actionReconciled references unknown action \(p.actionID)")
                return next
            }
            entry.reconciled = true
            next.actions[p.actionID] = entry
            if let key = next.attempts.first(where: { $0.value.workPackageID == entry.request.workPackageID })?.key {
                next.attempts[key]?.unreconciledUnknownActionIDs.remove(p.actionID)
            }

        case .artifactCreated(let p):
            next.artifacts[p.artifactID] = ArtifactRecord(
                artifactID: p.artifactID,
                kind: p.kind,
                path: p.path,
                revision: p.revision,
                contentHash: p.contentHash
            )

        case .artifactChanged(let p):
            guard var artifact = next.artifacts[p.artifactID] else {
                next.warnings.append("artifactChanged references unknown artifact \(p.artifactID)")
                return next
            }
            artifact.revision = p.newRevision
            artifact.contentHash = p.contentHash
            next.artifacts[p.artifactID] = artifact

        case .evidenceCreated(let p):
            next.evidence[p.evidence.evidenceID] = p.evidence

        case .evidenceInvalidated(let p):
            guard var evidence = next.evidence[p.evidenceID] else {
                next.warnings.append("evidenceInvalidated references unknown evidence \(p.evidenceID)")
                return next
            }
            evidence.status = p.mark
            next.evidence[p.evidenceID] = evidence

        case .verificationStarted(let p):
            guard var task = next.tasks[p.taskID] else {
                next.warnings.append("verificationStarted references unknown task \(p.taskID)")
                return next
            }
            task.state = .awaitingVerification
            next.tasks[p.taskID] = task

        case .verificationPassed(let p):
            guard var task = next.tasks[p.taskID] else {
                next.warnings.append("verificationPassed references unknown task \(p.taskID)")
                return next
            }
            task.state = .complete
            next.tasks[p.taskID] = task

        case .verificationFailed(let p):
            guard var task = next.tasks[p.taskID] else {
                next.warnings.append("verificationFailed references unknown task \(p.taskID)")
                return next
            }
            // Rejected by independent verification: work returns to rework.
            task.state = .inProgress
            next.tasks[p.taskID] = task
            next.warnings.append("verification failed for task \(p.taskID): \(p.detail)")

        case .verificationInconclusive(let p):
            guard next.tasks[p.taskID] != nil else {
                next.warnings.append("verificationInconclusive references unknown task \(p.taskID)")
                return next
            }
            // Task stays awaiting verification; no state change.

        case .decisionRequested(let p):
            next.needsUser.append(NeedsYouEntry(subject: p.subject, question: p.question, blocking: p.blocking))

        case .userIntervened(let p):
            next.interventions.append(p.intervention)

        case .checkpointCreated(let p):
            next.checkpoints.append(p.checkpointID)

        case .workerCrashed(let p):
            if let attemptID = p.attemptID {
                guard var attempt = next.attempts[attemptID] else {
                    next.warnings.append("workerCrashed references unknown attempt \(attemptID)")
                    return next
                }
                attempt.crashed = true
                attempt.phase = .ended
                attempt.outcome = .failed
                next.attempts[attemptID] = attempt
            }

        case .workerRecovered(let p):
            guard var attempt = next.attempts[p.attemptID] else {
                next.warnings.append("workerRecovered references unknown attempt \(p.attemptID)")
                return next
            }
            attempt.recovered = true
            next.attempts[p.attemptID] = attempt

        case .goalCompleted(let p):
            guard next.goals[p.goalRevisionID] != nil else {
                next.warnings.append("goalCompleted references unknown goal revision \(p.goalRevisionID)")
                return next
            }
            next.goals[p.goalRevisionID]?.completed = true

        case .goalBlocked(let p):
            guard next.goals[p.goalRevisionID] != nil else {
                next.warnings.append("goalBlocked references unknown goal revision \(p.goalRevisionID)")
                return next
            }
            next.goals[p.goalRevisionID]?.blockedReason = p.reason

        case .needsYouResolved(let p):
            next.needsUser.removeAll { $0.subject == p.subject && $0.question == p.question }
            next.resolvedNeedsYou.append(ResolvedNeedsYouEntry(
                subject: p.subject, question: p.question, answer: p.answer, resolvedAt: p.resolvedAt
            ))

        case .notePromoted(let p):
            next.promotions.append(PromotionRecord(noteID: p.noteID, target: p.target, summary: p.summary))

        case .inboxItemPromoted(let p):
            next.promotions.append(PromotionRecord(itemID: p.itemID, target: p.target, summary: p.summary))

        case .branchCreated(let p):
            next.branches.append(BranchRecord(
                fromCheckpointID: p.fromCheckpointID,
                newPlanRevisionID: p.newPlanRevisionID,
                previousPlanRevisionID: p.previousPlanRevisionID,
                reason: p.reason
            ))
            if next.plans[p.newPlanRevisionID] == nil {
                let inherited = next.plans[p.previousPlanRevisionID]
                next.plans[p.newPlanRevisionID] = PlanRecord(
                    planRevisionID: p.newPlanRevisionID,
                    goalRevisionID: inherited?.goalRevisionID ?? next.activeGoalRevisionID ?? GoalRevisionID(),
                    summary: inherited?.summary ?? "branched from checkpoint \(p.fromCheckpointID)",
                    taskIDs: inherited?.taskIDs ?? [],
                    previousRevisionID: p.previousPlanRevisionID,
                    revisionRationale: p.reason
                )
            }
            next.activePlanRevisionID = p.newPlanRevisionID

        case .restoredFromCheckpoint(let p):
            next.restorations.append(RestorationRecord(checkpointID: p.checkpointID, note: p.note))

        case .leaseEvent(let p):
            next.leaseEvents.append(LeaseEventRecord(granted: p.granted, owner: p.owner, reason: p.reason))
        }

        return next
    }

    /// Read-only historical state at a journal position: a pure replay
    /// prefix (Constitution #22 — scrubbing is inspection, not rollback).
    public static func state(at sequence: UInt64, of store: JournalStore) throws -> ProjectState {
        let journal = try JournalReader.readAllEvents(at: store.journalFileURL)
        let prefix = journal.records.prefix { $0.sequence <= sequence }
        return replay(records: prefix, projectID: store.projectID)
    }

    /// Folds a full event stream from empty state.
    public static func replay(records: some Sequence<EventRecord>, projectID: ProjectID) -> ProjectState {
        records.reduce(ProjectState(projectID: projectID)) { apply($0, $1) }
    }

    /// Rebuilds state from the store's journal file, ignoring snapshots.
    public static func replayAll(_ store: JournalStore) throws -> ProjectState {
        let journal = try JournalReader.readAllEvents(at: store.journalFileURL)
        return replay(records: journal.records, projectID: store.projectID)
    }

    // MARK: - Snapshots (accelerators, never authoritative)

    private static func snapshotURL(for projectID: ProjectID, under root: URL) -> URL {
        root.appendingPathComponent(projectID.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("journal", isDirectory: true)
            .appendingPathComponent("snapshot.json")
    }

    private struct Snapshot: Codable {
        var lastSequence: UInt64
        var state: ProjectState
    }

    public static func saveSnapshot(_ state: ProjectState, for projectID: ProjectID, under root: URL) throws {
        let snapshot = Snapshot(lastSequence: state.lastSequence, state: state)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: snapshotURL(for: projectID, under: root), options: .atomic)
    }

    /// Loads snapshot (if present) and folds only journal records after it.
    public static func loadUsingSnapshot(_ store: JournalStore) throws -> ProjectState {
        let url = snapshotURL(for: store.projectID, under: store.rootDirectory)
        let journal = try JournalReader.readAllEvents(at: store.journalFileURL)

        if FileManager.default.fileExists(atPath: url.path),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url)) {
            let tail = journal.records.filter { $0.sequence > snapshot.lastSequence }
            return tail.reduce(snapshot.state) { apply($0, $1) }
        }
        return replay(records: journal.records, projectID: store.projectID)
    }
}
