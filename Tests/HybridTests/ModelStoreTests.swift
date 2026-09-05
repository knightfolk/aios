import Foundation
import Testing
@testable import AIOSCore
@testable import ModelRuntime
@testable import MLXRuntime

private func makeRoot() -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-modelstore-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func hashHelpersMatchKnownVectors() throws {
    // git hash-object of an empty file (well-known blob oid)
    let empty = URL(fileURLWithPath: "/dev/null")
    let emptyBlob = try MLXRuntime.Hashing.gitBlobSHA1(of: empty)
    #expect(emptyBlob == "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391")
    #expect(MLXRuntime.Hashing.sha256Hex(of: Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
}

@Test func residencyRequiresAllFilesVerified() throws {
    let root = makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dir = root.appendingPathComponent("test-model", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: dir.appendingPathComponent("config.json"))

    let blob = try MLXRuntime.Hashing.gitBlobSHA1(of: dir.appendingPathComponent("config.json"))
    let manifest = ModelManifest(
        modelID: "test-model", family: "t", revision: "1", quantization: "4bit",
        sourceURL: "https://example.invalid/t",
        files: [ModelFile(filename: "config.json", gitBlobSHA1: blob)],
        license: "mit", modalities: ["text"], contextWindowTokens: 1024,
        estimatedMemoryGB: 0.1, supportedRuntimes: [.mlx],
        recommendedRoles: [], knownLimitations: [], requiresRemoteCode: false
    )
    let store = ModelStore(root: root)
    #expect(store.isResident(manifest))

    // Tamper: residency must break.
    try Data("{\"pwned\":1}".utf8).write(to: dir.appendingPathComponent("config.json"))
    #expect(!store.isResident(manifest))

    // Missing file: not resident.
    try FileManager.default.removeItem(at: dir.appendingPathComponent("config.json"))
    #expect(!store.isResident(manifest))
}

@Test func sha256PinnedWeightsGateResidency() throws {
    let root = makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dir = root.appendingPathComponent("w-model", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("weights-bytes".utf8).write(to: dir.appendingPathComponent("model.safetensors"))
    let digest = MLXRuntime.Hashing.sha256Hex(of: Data("weights-bytes".utf8))

    let good = ModelManifest(
        modelID: "w-model", family: "t", revision: "1", quantization: "4bit",
        sourceURL: "https://example.invalid/w",
        files: [ModelFile(filename: "model.safetensors", sha256: digest)],
        license: "mit", modalities: ["text"], contextWindowTokens: 1024,
        estimatedMemoryGB: 0.1, supportedRuntimes: [.mlx],
        recommendedRoles: [], knownLimitations: [], requiresRemoteCode: false
    )
    #expect(ModelStore(root: root).isResident(good))

    var tampered = good
    tampered.files = [ModelFile(filename: "model.safetensors", sha256: String(repeating: "0", count: 64))]
    #expect(!ModelStore(root: root).isResident(tampered))
}

@Test func fetchDownloadsVerifiesAndMarksResident() async throws {
    // Serve "weights" from a local file:// source; the fetch path (download,
    // rename, verify) is exercised offline.
    let sourceRoot = makeRoot()
    let destination = makeRoot()
    defer {
        try? FileManager.default.removeItem(at: sourceRoot)
        try? FileManager.default.removeItem(at: destination)
    }
    try Data("local-weights".utf8).write(to: sourceRoot.appendingPathComponent("model.safetensors"))
    try Data("{}".utf8).write(to: sourceRoot.appendingPathComponent("config.json"))

    let weightsDigest = MLXRuntime.Hashing.sha256Hex(of: Data("local-weights".utf8))
    let configBlob = try MLXRuntime.Hashing.gitBlobSHA1(of: sourceRoot.appendingPathComponent("config.json"))

    final class ProgressBox: @unchecked Sendable {
        var reports: [Double] = []
        private let lock = NSLock()
        func append(_ value: Double) {
            lock.lock(); reports.append(value); lock.unlock()
        }
    }
    let progress = ProgressBox()
    let manifest = ModelManifest(
        modelID: "fetched-model", family: "t", revision: "1", quantization: "4bit",
        sourceURL: sourceRoot.path,
        files: [
            ModelFile(filename: "model.safetensors", sha256: weightsDigest),
            ModelFile(filename: "config.json", gitBlobSHA1: configBlob),
        ],
        license: "mit", modalities: ["text"], contextWindowTokens: 1024,
        estimatedMemoryGB: 0.1, supportedRuntimes: [.mlx],
        recommendedRoles: [], knownLimitations: [], requiresRemoteCode: false
    )

    let store = ModelStore(root: destination)
    try await store.fetch(manifest) { progress.append($0) }
    #expect(store.isResident(manifest))
    #expect(progress.reports.last == 1.0)

    // Re-fetch is a no-op when already resident and verified.
    try await store.fetch(manifest) { _ in }
    #expect(store.isResident(manifest))
}
