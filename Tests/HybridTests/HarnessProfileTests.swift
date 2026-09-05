import Foundation
import Testing
@testable import AIOSCore
@testable import ModelRuntime

@Test func bundledHarnessProfileLoads() throws {
    let store = HarnessProfileStore(overrideRoot: URL(fileURLWithPath: "/nonexistent/aios-overrides"))
    let profile = try store.load(profileID: "default-v1")
    #expect(profile.profileID == "default-v1")
    #expect(!profile.systemPrompt.isEmpty)
    #expect(profile.preferredTopologies.contains(.singleAgent))
}

@Test func overrideDirectoryWinsOverBundled() throws {
    let overrideRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-harness-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: overrideRoot) }
    let overrideDir = overrideRoot.appendingPathComponent("default-v1", isDirectory: true)
    let custom = HarnessProfile(
        profileID: "default-v1",
        systemPrompt: "OVERRIDE: be extremely terse",
        outputContractJSON: "{}",
        reasoningMode: "none",
        contextMaintenance: "none",
        preferredTopologies: [.direct],
        retryRules: ["max 1"],
        failureSignatures: [],
        evaluatorCompatibility: "json"
    )
    try FileManager.default.createDirectory(at: overrideDir, withIntermediateDirectories: true)
    try JSONEncoder().encode(custom).write(to: overrideDir.appendingPathComponent("profile.json"))

    let store = HarnessProfileStore(overrideRoot: overrideRoot)
    let loaded = try store.load(profileID: "default-v1")
    #expect(loaded.systemPrompt.hasPrefix("OVERRIDE"))
    #expect(loaded.preferredTopologies == [.direct])
}

@Test func missingOverrideFallsBackToBundled() throws {
    let overrideRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-harness-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: overrideRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: overrideRoot) }

    let store = HarnessProfileStore(overrideRoot: overrideRoot)
    let loaded = try store.load(profileID: "default-v1")
    #expect(!loaded.systemPrompt.isEmpty)
    #expect(!loaded.systemPrompt.hasPrefix("OVERRIDE"))
}
