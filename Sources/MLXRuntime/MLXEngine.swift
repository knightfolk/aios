import Foundation
import MLXLLM
import MLXLMCommon
import Tokenizers
import AIOSCore
import ModelRuntime

/// One loaded brain. Implemented by the real MLX engine and by the declared
/// offline echo engine used by tests (never a silent stand-in: the echo
/// engine reports `.scripted`).
public protocol LLMEngine: Sendable {
    func complete(_ request: GenerationRequest, onChunk: @Sendable (String) -> Void) async -> GenerationResult
}

/// Real local inference over MLX (the only MLX-linked engine in the system).
public final class MLXEngine: LLMEngine, @unchecked Sendable {
    public enum EngineError: Error, Equatable {
        case notLoaded
        case loadFailed(String)
    }

    private let modelDirectory: URL
    private let state = StateLock()

    final class StateLock: @unchecked Sendable {
        private let lock = NSLock()
        private var container: ModelContainer?

        func get() -> ModelContainer? {
            lock.lock(); defer { lock.unlock() }
            return container
        }

        func set(_ value: ModelContainer?) {
            lock.lock(); defer { lock.unlock() }
            container = value
        }
    }

    public init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    /// Loads weights + tokenizer from a verified local directory.
    public func load() async throws {
        do {
            let container = try await LLMModelFactory.shared.loadContainer(
                from: modelDirectory,
                using: AutoTokenizerLoader()
            )
            state.set(container)
        } catch {
            throw EngineError.loadFailed("\(error)")
        }
    }

    public func complete(_ request: GenerationRequest, onChunk: @Sendable (String) -> Void) async -> GenerationResult {
        guard let container = state.get() else {
            return GenerationResult(text: "", promptTokens: 0, completionTokens: 0, latencyMs: 0,
                                    outcome: .failed, detail: "engine not loaded")
        }

        let started = Date()
        let parameters = GenerateParameters(
            temperature: Float(request.temperature),
            topP: 1.0,
            repetitionPenalty: 1.1
        )
        let session = ChatSession(container, generateParameters: parameters)
        let chatMessages = request.messages.map { message in
            Chat.Message(role: .init(rawValue: message.role.rawValue) ?? .user, content: message.content)
        }

        var text = ""
        do {
            for try await chunk in session.streamResponse(to: chatMessages) {
                text += chunk
                onChunk(chunk)
            }
        } catch {
            return GenerationResult(text: text, promptTokens: 0, completionTokens: 0,
                                    latencyMs: Date().timeIntervalSince(started) * 1000,
                                    outcome: .failed, detail: "\(error)")
        }

        // Token counts via the tokenizer when reachable; zero (never
        // invented) otherwise.
        final class TokenBox: @unchecked Sendable {
            var prompt = 0
            var completion = 0
        }
        let box = TokenBox()
        let generated = text
        let promptText = request.messages.map(\.content).joined()
        _ = await container.perform { context in
            box.prompt = context.tokenizer.encode(text: promptText).count
            box.completion = context.tokenizer.encode(text: generated).count
        }
        let promptTokens = box.prompt
        let completionTokens = box.completion

        return GenerationResult(
            text: text,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            latencyMs: Date().timeIntervalSince(started) * 1000,
            outcome: .succeeded
        )
    }
}

/// Declared offline engine for tests (and as a boot-time smoke). It echoes a
/// fixed shape and always reports itself honestly; callers surface it as
/// `RuntimeKind.scripted`. `AIOS_FAKE_LLM_DELAY_MS` spaces its chunks for
/// crash-mid-generation tests.
public final class EchoEngine: LLMEngine, @unchecked Sendable {
    private let delayMs: Int

    public init(delayMs: Int? = nil) {
        if let delayMs {
            self.delayMs = delayMs
        } else if let raw = ProcessInfo.processInfo.environment["AIOS_FAKE_LLM_DELAY_MS"], let parsed = Int(raw) {
            self.delayMs = parsed
        } else {
            self.delayMs = 0
        }
    }

    public func complete(_ request: GenerationRequest, onChunk: @Sendable (String) -> Void) async -> GenerationResult {
        let started = Date()
        let userText = request.messages.last(where: { $0.role == .user })?.content ?? ""

        // Declared two-turn action script (tests only): turn 1 proposes one
        // real fs.write action; turn 2 completes after the observation.
        let actionsEnabled = ProcessInfo.processInfo.environment["AIOS_FAKE_LLM_ACTIONS"] == "1"
        let actionTarget = ProcessInfo.processInfo.environment["AIOS_ECHO_ACTION_TARGET"] ?? ""
        let isFollowUpTurn = request.messages.count >= 3
        let payload: String
        if actionsEnabled && !actionTarget.isEmpty && !isFollowUpTurn {
            payload = """
            {"status": "IN_PROGRESS", "summary": "echo brain will write the marker file", "actions": [{"operation": "fs.write", "target": "\(actionTarget)", "parameters": {"contents": "ECHO_ACTION_OK"}, "expectedEffect": "marker file written", "verificationPlan": "read back"}], "unresolvedAssumptions": [], "recommendedNextSteps": []}
            """
        } else if actionsEnabled && !actionTarget.isEmpty && isFollowUpTurn {
            payload = """
            {"status": "COMPLETED", "summary": "echo brain observed the write result and finished", "claims": [{"statement": "marker file written through the broker", "statementType": "GENERATED_CONTENT"}], "unresolvedAssumptions": [], "recommendedNextSteps": []}
            """
        } else {
            // JSON-encode properly: interpolated prompts contain newlines
            // that would break a hand-written literal.
            struct SafeClaim: Codable {
                var statement: String
                var statementType: String
            }
            struct SafePayload: Codable {
                var status: String
                var summary: String
                var claims: [SafeClaim]
                var unresolvedAssumptions: [String]
                var recommendedNextSteps: [String]
            }
            let safe = SafePayload(
                status: "COMPLETED",
                summary: "echo engine acknowledged the package",
                claims: [SafeClaim(statement: "ECHO: \(userText.prefix(120))", statementType: "GENERATED_CONTENT")],
                unresolvedAssumptions: [],
                recommendedNextSteps: []
            )
            payload = (try? JSONEncoder().encode(safe)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        }
        for piece in payload.split(separator: " ") {
            onChunk(String(piece) + " ")
            if delayMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
        }
        return GenerationResult(
            text: payload,
            promptTokens: userText.count / 4,
            completionTokens: payload.count / 4,
            latencyMs: Date().timeIntervalSince(started) * 1000,
            outcome: .succeeded,
            detail: "echo engine (declared offline test double)"
        )
    }
}

// MARK: - Tokenizer adapter (swift-transformers → MLXLMCommon)

public struct AutoTokenizerLoader: MLXLMCommon.TokenizerLoader {
    public init() {}

    public func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return MLXTokenizerAdapter(base: tokenizer)
    }
}

struct MLXTokenizerAdapter: MLXLMCommon.Tokenizer {
    let base: Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        base.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        base.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        base.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        base.convertIdToToken(id)
    }

    var bosToken: String? { base.bosToken }
    var eosToken: String? { base.eosToken }
    var unknownToken: String? { base.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        // ToolSpec is a dictionary typealias on both sides — pass through.
        return try base.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
    }
}
