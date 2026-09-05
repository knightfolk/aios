import Foundation

// Generation contracts shared by every runtime (scripted, mlx, cloud).

public enum ChatRole: String, Codable, Sendable, Hashable {
    case system
    case user
    case assistant
}

public struct ChatMessage: Codable, Sendable, Hashable {
    public var role: ChatRole
    public var content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct GenerationRequest: Codable, Sendable, Hashable {
    public static let currentSchemaVersion: UInt = 1

    public var schemaVersion: UInt
    public var messages: [ChatMessage]
    public var maxTokens: Int
    public var temperature: Double
    public var harnessProfileID: String

    public init(
        messages: [ChatMessage],
        maxTokens: Int,
        temperature: Double,
        harnessProfileID: String,
        schemaVersion: UInt = GenerationRequest.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.harnessProfileID = harnessProfileID
    }
}

public struct GenerationChunk: Codable, Sendable, Hashable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public enum GenerationOutcome: String, Codable, Sendable, Hashable {
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    case refused = "REFUSED"
    case notConfigured = "NOT_CONFIGURED"
}

public struct GenerationResult: Codable, Sendable, Hashable {
    public static let currentSchemaVersion: UInt = 1

    public var schemaVersion: UInt
    public var text: String
    public var promptTokens: Int
    public var completionTokens: Int
    public var latencyMs: Double
    public var outcome: GenerationOutcome
    public var detail: String?

    public init(
        text: String,
        promptTokens: Int,
        completionTokens: Int,
        latencyMs: Double,
        outcome: GenerationOutcome,
        detail: String? = nil,
        schemaVersion: UInt = GenerationResult.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.text = text
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.latencyMs = latencyMs
        self.outcome = outcome
        self.detail = detail
    }
}
