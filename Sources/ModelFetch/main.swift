import Foundation
import ModelRuntime
import MLXRuntime

// ModelFetch — manual, one-time setup tool: downloads a curated model and
// verifies every file hash before marking it resident.

struct Options {
    var query: String?
    init(arguments: [String]) {
        query = arguments.first(where: { !$0.hasPrefix("-") })
    }
}

let options = Options(arguments: Array(CommandLine.arguments.dropFirst()))
guard let query = options.query else {
    try? FileHandle.standardError.write(contentsOf: Data("usage: ModelFetch <modelID | huggingface-id>\n".utf8))
    exit(2)
}

let registry: ModelRegistry
do {
    registry = try ModelRegistry.loadDefault()
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("ModelFetch: cannot load default registry: \(error)\n".utf8))
    exit(2)
}

guard let manifest = registry.models.first(where: { $0.modelID == query || $0.sourceURL.hasSuffix(query) }) else {
    let known = registry.models.map(\.modelID).joined(separator: ", ")
    try? FileHandle.standardError.write(contentsOf: Data("ModelFetch: unknown model '\(query)'. Known: \(known)\n".utf8))
    exit(2)
}

let store = ModelStore()
print("Fetching \(manifest.modelID) (\(manifest.quantization), ~\(String(format: "%.1f", manifest.estimatedMemoryGB)) GB) into \(store.root.path)")

if store.isResident(manifest) {
    print("Already resident and verified.")
    exit(0)
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        try await store.fetch(manifest) { fraction in
            print(String(format: "  progress: %.0f%%", fraction * 100))
        }
        print("Verified: \(store.isResident(manifest) ? "resident" : "FAILED")")
        semaphore.signal()
    } catch {
        try? FileHandle.standardError.write(contentsOf: Data("ModelFetch failed: \(error)\n".utf8))
        semaphore.signal()
    }
}
let result = semaphore.wait(timeout: .now() + 3600)
exit(result == .success && store.isResident(manifest) ? 0 : 1)
