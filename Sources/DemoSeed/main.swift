import Foundation
import AIOSCore
import EventJournal
import ProjectKernel

// Seeds a demo journal at ~/Library/Application Support/AIOS/demo-projects
// so the shell opens onto a living desktop: goal, plan, tasks, a running
// attempt, verified evidence, a checkpoint + branch, one Needs You entry,
// a crashed-and-recovered attempt, and a lease grant for the Chloe Deck.

let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("AIOS/demo-projects", isDirectory: true)
try? FileManager.default.removeItem(at: root)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

let projectID = ProjectID()
let journal = try JournalStore(projectID: projectID, rootDirectory: root)
let notes = NotesStore(journal: journal, storageRoot: root)
let inbox = InboxStore(journal: journal, storageRoot: root)

let goal = GoalRevisionID()
let plan = PlanRevisionID()
let t1 = TaskID(), t2 = TaskID(), t3 = TaskID()
let a1 = AttemptID(), a2 = AttemptID(), a3 = AttemptID()
let wp = WorkPackageID()

// Pre-generate the action ID so request and result link correctly.
let writeAction = ActionRequest(
    actionID: ActionID(), workPackageID: wp, requestedBy: .linus,
    capability: .modifyWorkspace, operation: "fs.write",
    target: "worktree-1/Sources/App/main.swift",
    parameters: ["contents": .text("let FIX_MARKER = \"fixed\"\nprint(FIX_MARKER)\n")],
    expectedEffect: "FIX_MARKER introduced",
    sideEffectClass: .local, reversibility: .reversible, idempotency: .idempotent,
    requiredPermission: .modifyWorkspace, verificationPlan: "run_checks.sh")

let failActionID = ActionID()

let events: [EngineEvent] = [
    .projectOpened,
    .goalCreated(.init(goalRevisionID: goal,
                       originalRequest: "Make the fixture app print its fixed marker instead of 'broken'",
                       objective: "Fix main.swift and prove it with the mechanical check",
                       acceptanceCriteria: ["run_checks.sh exits 0", "diff reviewed"])),
    .planProposed(.init(planRevisionID: plan, goalRevisionID: goal,
                        summary: "edit → verify → independent review")),
    .taskCreated(.init(taskID: t1, planRevisionID: plan, objective: "Introduce FIX_MARKER in main.swift", owner: .linus)),
    .taskCreated(.init(taskID: t2, planRevisionID: plan, objective: "Run mechanical check and record evidence", owner: .sherlock)),
    .taskCreated(.init(taskID: t3, planRevisionID: plan, objective: "Draft docs update for the fix", owner: .jobs)),

    // Attempt 1: crash + recovery.
    .taskStateChanged(.init(taskID: t1, oldState: .pending, newState: .inProgress)),
    .attemptStarted(.init(attemptID: a1, taskID: t1, workPackageID: wp,
                          worker: WorkerIdentity(workerID: "inference-401", model: "qwen25-7b-instruct-4bit", runtime: .mlx, revision: "1"))),
    .modelSelected(.init(attemptID: a1, runtime: .mlx, rationale: "local MLX model resident")),
    .workerCrashed(.init(workerID: "inference-401", attemptID: a1)),
    .attemptEnded(.init(attemptID: a1, taskID: t1, outcome: .failed)),

    // Attempt 2: success with evidence.
    .attemptStarted(.init(attemptID: a2, taskID: t1, workPackageID: wp,
                          worker: WorkerIdentity(workerID: "inference-402", model: "qwen25-7b-instruct-4bit", runtime: .mlx, revision: "1"))),
    .workerRecovered(.init(workerID: "inference-402", attemptID: a2, strategy: "checkpoint handoff after crash")),
    .actionRequested(.init(request: writeAction)),
    .actionExecuted(.init(result: ActionResult(
        actionID: writeAction.actionID,
        outcome: .succeeded, startedAt: Date(), endedAt: Date(),
        observedEffects: ["wrote 42 bytes"]))),
    .verificationPassed(.init(taskID: t1, requirement: "run_checks.sh exits 0")),
    .attemptEnded(.init(attemptID: a2, taskID: t1, outcome: .completed)),

    // A live-running attempt for the Activity Center.
    .taskStateChanged(.init(taskID: t2, oldState: .pending, newState: .inProgress)),
    .attemptStarted(.init(attemptID: a3, taskID: t2, workPackageID: wp,
                          worker: WorkerIdentity(workerID: "inference-403", model: "qwen25-7b-instruct-4bit", runtime: .mlx, revision: "1"))),

    // Checkpoint + branch.
    .checkpointCreated(.init(checkpointID: "cp-pre-docs", note: "before docs push")),
    .branchCreated(.init(fromCheckpointID: "cp-pre-docs",
                         newPlanRevisionID: PlanRevisionID(),
                         previousPlanRevisionID: plan,
                         reason: "docs-first approach")),

    // Needs You.
    .decisionRequested(.init(subject: "api shape", question: "struct or class for the marker?", blocking: true)),

    // Lease grant for the Chloe Deck.
    .leaseEvent(.init(granted: true, owner: "docs/chloe", reason: "granted: export report")),

    // A failing action for the constellation.
    .actionExecuted(.init(result: ActionResult(
        actionID: failActionID, outcome: .failed, startedAt: Date(), endedAt: Date(),
        failureDetails: "grep exited 1 on first pass"))),
]

for event in events {
    _ = try await journal.append(event)
}

// Evidence + notes + inbox.
let evidence = Evidence(
    evidenceID: EvidenceID(), projectID: projectID,
    subject: "mechanical check",
    proposition: "run_checks.sh exits 0 at revision r1",
    claimType: .verifiedFact, sourceType: .command,
    sourceReference: "/bin/sh run_checks.sh",
    producedBy: WorkerIdentity(workerID: "broker", runtime: .deterministic),
    observedAt: Date(), verificationMethod: .deterministicCheck("run_checks"),
    strength: .mechanicalCheck)
try await journal.append(.evidenceCreated(.init(evidence: evidence)))

_ = try await notes.create(text: "consider ring buffer for the parser")
_ = try await notes.create(text: "benchmark lexer after fix lands")
_ = try await inbox.create(text: "maybe EPG caching later")

print("Demo journal seeded at \(root.path) (\(events.count + 1) events)")
print("Launch: swift run WorkRuntimeApp --journal \(root.path)")
