import Foundation
import SwiftUI
import AIOSCore
import ExecutionFabric
import ModelRuntime
import MLXRuntime

// Step 4: Expert Cards converse over a REAL worker session (docs 06/07).
// The chat is state fed by session events; the brain's words stay
// generatedContent — nothing here auto-promotes to fact or completion.

public struct ChatMessage: Identifiable, Sendable, Equatable {
    public var id: UUID = UUID()
    public var role: ChatRole
    public var text: String

    public enum ChatRole: String, Sendable {
        case user
        case assistant
        case system
    }

    public init(role: ChatRole, text: String) {
        self.role = role
        self.text = text
    }
}

@MainActor
public final class ExpertChatModel: ObservableObject {
    @Published public private(set) var transcript: [ChatMessage] = []
    @Published public private(set) var isRunning = false
    @Published public private(set) var lastWorkerRuntime: RuntimeKind?

    public let expertRole: ExpertRole
    private var session: WorkerSession?

    public init(expertRole: ExpertRole) {
        self.expertRole = expertRole
    }

    /// Spawns the real InferenceWorker: a resident verified model when
    /// available, else the declared echo engine (reported honestly).
    public func startConsultation(workerURL: URL, modelDirectory: URL? = nil) async throws {
        var arguments: [String] = []
        var environment: [String: String] = [:]

        let registry = (try? ModelRegistry.loadDefault()) ?? ModelRegistry(models: [])
        let store = ModelStore()
        var runtimeNote = "echo engine (declared scripted double)"
        if let manifest = registry.models.first(where: { store.isResident($0) }) {
            arguments = ["--model", store.directory(for: manifest).path]
            runtimeNote = manifest.modelID
        } else {
            arguments = ["--model", "/tmp/none"]
            environment["AIOS_FAKE_LLM"] = "1"
        }
        _ = environment

        let session = WorkerSession(
            configuration: .init(executableURL: workerURL, arguments: arguments, heartbeatTimeoutSeconds: 120),
            journal: nil
        )
        try await session.start()
        self.session = session
        // Runtime identity comes from the session's own started event —
        // never inferred from what we asked for.
        if case .started(_, let runtime)? = await session.eventHistory().first(where: { if case .started = $0 { true } else { false } }) {
            lastWorkerRuntime = runtime
            runtimeNote = runtime == .mlx ? runtimeNote : "echo engine (declared scripted double)"
        }
        transcript.append(ChatMessage(role: .system, text: "consultation started with \(runtimeNote)"))
    }

    @discardableResult
    public func send(userText: String) async throws -> WorkResult {
        guard let session else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "no active consultation"])
        }
        isRunning = true
        defer { isRunning = false }
        transcript.append(ChatMessage(role: .user, text: userText))

        let package = consultationPackage(prompt: userText)
        try await session.sendWorkPackage(package)

        var cursor = await session.eventHistory().count
        var result: WorkResult?
        var streamed = ""
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            let events = await session.eventHistory()
            while cursor < events.count {
                switch events[cursor] {
                case .generationChunk(let chunk):
                    streamed += chunk.text
                case .generationDone:
                    if !streamed.isEmpty {
                        transcript.append(ChatMessage(role: .assistant, text: streamed))
                        streamed = ""
                    }
                case .workResult(let work):
                    result = work
                    if !streamed.isEmpty {
                        transcript.append(ChatMessage(role: .assistant, text: streamed))
                    }
                default:
                    break
                }
                cursor += 1
            }
            if result != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        guard let workResult = result else {
            transcript.append(ChatMessage(role: .system, text: "no response within 120s"))
            throw CocoaError(.userActivityConnectionUnavailable)
        }
        lastWorkerRuntime = workResult.worker.runtime
        // If nothing streamed (non-model mode), surface the summary/claims.
        if transcript.last?.role != .assistant {
            let claimText = workResult.claims.map(\.statement).joined(separator: "\n")
            transcript.append(ChatMessage(role: .assistant, text: claimText.isEmpty ? workResult.handoff?.currentState ?? "(no content)" : claimText))
        }
        transcript.append(ChatMessage(role: .system, text: "turn ended: \(workResult.status.rawValue) — generated content, not verified fact"))
        return workResult
    }

    public func end() async {
        if let session {
            await session.terminate()
        }
        session = nil
        transcript.append(ChatMessage(role: .system, text: "consultation ended"))
    }

    private func consultationPackage(prompt: String) -> WorkPackage {
        WorkPackage(
            packageID: WorkPackageID(),
            projectID: ProjectID(),
            goalRevisionID: GoalRevisionID(),
            planRevisionID: PlanRevisionID(),
            taskID: TaskID(),
            attemptID: AttemptID(),
            role: expertRole,
            taskContract: TaskContract(
                objective: "consultation: \(prompt)",
                inputs: [], allowedScope: [], mustPreserve: [], forbiddenScope: [],
                expectedOutputs: [], verificationRequirements: [],
                dependencyAssumptions: [], stalenessConditions: []
            ),
            contextBundle: ContextBundle(selections: [], tokenBudget: 600),
            capabilities: [.observe],
            executionTargets: [.direct],
            resourceBudget: ResourceBudget(),
            timeBudget: TimeBudget(timeoutSeconds: 120),
            privacyPolicy: .localOnly,
            spendPolicy: SpendPolicy(),
            expectedOutputs: [],
            verificationRequirements: [],
            handoffPolicy: .continuation,
            failurePolicy: .failFast,
            harnessProfile: HarnessProfileID(value: "default-v1")
        )
    }
}
