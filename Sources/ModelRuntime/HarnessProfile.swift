import Foundation
import AIOSCore

/// Data-driven harness profile (docs 09). Bundled defaults ship with the
/// engine; JSON files under the override root (production:
/// `~/Library/Application Support/AIOS/harness/<id>/profile.json`) win, so
/// profiles update independently of engine releases.
public struct HarnessProfile: Codable, Sendable, Hashable {
    public static let currentSchemaVersion: UInt = 1

    public var schemaVersion: UInt
    public var profileID: String
    public var systemPrompt: String
    /// JSON template the model must fill for its WorkResult.
    public var outputContractJSON: String
    public var reasoningMode: String
    public var contextMaintenance: String
    public var preferredTopologies: [ExecutionTopology]
    public var retryRules: [String]
    public var failureSignatures: [String]
    public var evaluatorCompatibility: String

    public init(
        profileID: String,
        systemPrompt: String,
        outputContractJSON: String,
        reasoningMode: String,
        contextMaintenance: String,
        preferredTopologies: [ExecutionTopology],
        retryRules: [String],
        failureSignatures: [String],
        evaluatorCompatibility: String,
        schemaVersion: UInt = HarnessProfile.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.systemPrompt = systemPrompt
        self.outputContractJSON = outputContractJSON
        self.reasoningMode = reasoningMode
        self.contextMaintenance = contextMaintenance
        self.preferredTopologies = preferredTopologies
        self.retryRules = retryRules
        self.failureSignatures = failureSignatures
        self.evaluatorCompatibility = evaluatorCompatibility
    }
}

public struct HarnessProfileStore {
    public let overrideRoot: URL

    public init(overrideRoot: URL? = nil) {
        if let overrideRoot {
            self.overrideRoot = overrideRoot
        } else {
            self.overrideRoot = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
                .appendingPathComponent("AIOS/harness", isDirectory: true)
        }
    }

    public func load(profileID: String) throws -> HarnessProfile {
        let override = overrideRoot
            .appendingPathComponent(profileID, isDirectory: true)
            .appendingPathComponent("profile.json")
        if let data = try? Data(contentsOf: override),
           let profile = try? JSONDecoder().decode(HarnessProfile.self, from: data) {
            return profile
        }
        // SwiftPM may flatten copied resources; accept subdir or bundle root.
        let bundled = Bundle.module.url(
            forResource: profileID,
            withExtension: "json",
            subdirectory: "HarnessProfiles"
        ) ?? Bundle.module.url(forResource: profileID, withExtension: "json")
        guard let bundled else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSFilePathErrorKey: "harness profile \(profileID)",
            ])
        }
        return try JSONDecoder().decode(HarnessProfile.self, from: Data(contentsOf: bundled))
    }
}
