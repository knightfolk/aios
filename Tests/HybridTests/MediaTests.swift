import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ProjectKernel
@testable import MediaRuntime

@Test func synthRendererProducesRealImageAndAudioBytes() async throws {
    let renderer = BuiltinSynthRenderer()
    let image = try await renderer.render(.init(jobID: "j1", kind: .image, prompt: "gradient", seed: 7))
    #expect(image.data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) // PNG magic
    #expect(image.data.count > 500)
    #expect(image.provenance.contains("synthetic"))

    let audio = try await renderer.render(.init(jobID: "j2", kind: .audio, prompt: "tone", seed: 7))
    #expect(audio.data.prefix(4) == Data("RIFF".utf8)) // WAV magic
    #expect(audio.data.count > 44)
}

@Test func renderSchedulerVersionsArtifactsAndRecordsProvenance() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-media-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let scheduler = RenderScheduler(journal: journal, renderer: BuiltinSynthRenderer(), storageRoot: root)
    let job = MediaJob(jobID: "job-1", kind: .image, prompt: "blue gradient", seed: 1)

    let first = try await scheduler.submit(job)
    #expect(first.revision == 1)
    #expect(FileManager.default.fileExists(atPath: first.url.path))
    #expect(first.contentHash.count == 64)

    let second = try await scheduler.submit(job)
    #expect(second.revision == 2)
    #expect(second.url != first.url)

    // Artifact provenance is journaled: two artifactCreated events.
    let state = try Projection.replayAll(journal)
    #expect(state.artifacts.values.filter { $0.kind == .image }.count == 2)
    let hashes = state.artifacts.values.map(\.contentHash)
    #expect(Set(hashes).count == 2) // seeds differ per revision
}

@Test func schedulerRespectsConcurrencyAndCancelsQueuedJobs() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-media-q-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let slow = SlowCountingRenderer()
    let scheduler = RenderScheduler(journal: nil, renderer: slow, storageRoot: root)

    // Enqueue without awaiting: 'a' parks inside the gated renderer.
    let running = try await scheduler.enqueue(MediaJob(jobID: "a", kind: .image, prompt: "p", seed: 1))
    let queued = try await scheduler.enqueue(MediaJob(jobID: "b", kind: .image, prompt: "p", seed: 2))
    try await Task.sleep(for: .milliseconds(100))
    #expect(await slow.startedJobs == ["a"]) // one-at-a-time rendering

    let cancelled = await scheduler.cancel(jobID: "b")
    #expect(cancelled)
    await slow.finishAll()

    let artifactA = try await running.result.get()
    #expect(artifactA.jobID == "a")
    do {
        _ = try await queued.result.get()
        Issue.record("cancelled job must not produce an artifact")
    } catch {
        // expected: cancelled before starting
    }
    #expect(await slow.startedJobs == ["a"])
}

// MARK: - Doubles

/// Slow, release-gated renderer. Locking is confined to synchronous
/// accessors; the async render spins on Task.sleep (no locks in async).
final class SlowCountingRenderer: MediaRenderer, @unchecked Sendable {
    private final class Box: @unchecked Sendable {
        var started: [String] = []
        var released = false
        let lock = NSLock()

        func sync<T>(_ body: () -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body()
        }
    }

    private let box = Box()

    var startedJobs: [String] {
        box.sync { box.started }
    }

    func render(_ job: MediaJob) async throws -> RenderedMedia {
        box.sync { box.started.append(job.jobID) }
        while !box.sync({ box.released }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        return RenderedMedia(data: Data("x".utf8), mimeType: "application/octet-stream", provenance: "slow-test")
    }

    func finishAll() {
        box.sync { box.released = true }
    }
}
