import Foundation
import AIOSCore

// Model-neutral intelligence metadata (docs 09, 11). Pure types — no I/O.

// MARK: - Model manifests

public struct ModelFile: Codable, Sendable, Hashable {
    /// SHA-256 for LFS-backed files (the weights). Nil for plain git blobs.
    public var sha256: String?
    /// Git blob SHA-1 for non-LFS files (configs, tokenizer pieces).
    public var gitBlobSHA1: String?
    public var filename: String

    public init(filename: String, sha256: String? = nil, gitBlobSHA1: String? = nil) {
        self.filename = filename
        self.sha256 = sha256
        self.gitBlobSHA1 = gitBlobSHA1
    }

    /// A file must pin at least one hash to be verifiable.
    public var isVerifiable: Bool {
        (sha256?.count ?? 0) == 64 || (gitBlobSHA1?.count ?? 0) == 40
    }
}

public struct ModelManifest: Codable, Sendable, Hashable {
    public static let currentSchemaVersion: UInt = 1

    public var schemaVersion: UInt
    public var modelID: String
    public var family: String
    public var revision: String
    public var quantization: String
    public var sourceURL: String
    public var files: [ModelFile]
    public var license: String
    public var modalities: [String]
    public var contextWindowTokens: Int
    public var estimatedMemoryGB: Double
    public var supportedRuntimes: [RuntimeKind]
    public var recommendedRoles: [String]
    public var knownLimitations: [String]
    public var requiresRemoteCode: Bool
    public var evaluationRef: String?

    public init(
        modelID: String,
        family: String,
        revision: String,
        quantization: String,
        sourceURL: String,
        files: [ModelFile],
        license: String,
        modalities: [String],
        contextWindowTokens: Int,
        estimatedMemoryGB: Double,
        supportedRuntimes: [RuntimeKind],
        recommendedRoles: [String],
        knownLimitations: [String],
        requiresRemoteCode: Bool,
        evaluationRef: String? = nil,
        schemaVersion: UInt = ModelManifest.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.modelID = modelID
        self.family = family
        self.revision = revision
        self.quantization = quantization
        self.sourceURL = sourceURL
        self.files = files
        self.license = license
        self.modalities = modalities
        self.contextWindowTokens = contextWindowTokens
        self.estimatedMemoryGB = estimatedMemoryGB
        self.supportedRuntimes = supportedRuntimes
        self.recommendedRoles = recommendedRoles
        self.knownLimitations = knownLimitations
        self.requiresRemoteCode = requiresRemoteCode
        self.evaluationRef = evaluationRef
    }
}

public struct ModelRegistry: Codable, Sendable {
    public var models: [ModelManifest]

    public init(models: [ModelManifest]) {
        self.models = models
    }

    public static func loadDefault() throws -> ModelRegistry {
        guard let url = Bundle.module.url(forResource: "default-models", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(ModelRegistry.self, from: Data(contentsOf: url))
    }
}

// MARK: - Provider profiles

public enum ProviderProtocol: String, Codable, Sendable, Hashable {
    case openAICompatible = "OPENAI_COMPATIBLE"
}

public enum BillingMode: String, Codable, Sendable, Hashable {
    case subscription = "SUBSCRIPTION"
    case credits = "CREDITS"
    case payAsYouGo = "PAY_AS_YOU_GO"
}

public struct QuotaWindow: Codable, Sendable, Hashable {
    public var windowSeconds: TimeInterval
    public var tokenLimit: Int
    public var paidOverflowAllowed: Bool

    public init(windowSeconds: TimeInterval, tokenLimit: Int, paidOverflowAllowed: Bool) {
        self.windowSeconds = windowSeconds
        self.tokenLimit = tokenLimit
        self.paidOverflowAllowed = paidOverflowAllowed
    }
}

public struct ProviderModel: Codable, Sendable, Hashable {
    public var modelID: String
    public var modalities: [String]
    public var contextWindowTokens: Int

    public init(modelID: String, modalities: [String], contextWindowTokens: Int) {
        self.modelID = modelID
        self.modalities = modalities
        self.contextWindowTokens = contextWindowTokens
    }
}

public struct ProviderProfile: Codable, Sendable, Hashable {
    public static let currentSchemaVersion: UInt = 1

    public var schemaVersion: UInt
    public var providerID: String
    public var endpoint: String
    public var protocolKind: ProviderProtocol
    public var models: [ProviderModel]
    public var billingMode: BillingMode
    public var quotaWindows: [QuotaWindow]
    public var rateLimitRPM: Int
    public var privacyNotes: String
    public var lastVerifiedAt: Date

    public init(
        providerID: String,
        endpoint: String,
        protocolKind: ProviderProtocol,
        models: [ProviderModel],
        billingMode: BillingMode,
        quotaWindows: [QuotaWindow],
        rateLimitRPM: Int,
        privacyNotes: String,
        lastVerifiedAt: Date,
        schemaVersion: UInt = ProviderProfile.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.providerID = providerID
        self.endpoint = endpoint
        self.protocolKind = protocolKind
        self.models = models
        self.billingMode = billingMode
        self.quotaWindows = quotaWindows
        self.rateLimitRPM = rateLimitRPM
        self.privacyNotes = privacyNotes
        self.lastVerifiedAt = lastVerifiedAt
    }

    /// Tokens remaining in the tightest applicable quota window (0 when
    /// exhausted). Subscription allowance never silently becomes paid usage.
    public func tokensRemaining(usedTokensInWindow: Int) -> Int {
        let limits = quotaWindows.map(\.tokenLimit)
        guard let tightest = limits.min() else { return Int.max }
        return max(0, tightest - usedTokensInWindow)
    }

    public var allowsOverflow: Bool {
        quotaWindows.contains { $0.paidOverflowAllowed }
    }
}
