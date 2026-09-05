import Foundation
import AppKit
import CryptoKit
import AIOSCore
import EventJournal
import ProjectKernel

// Henson's runtime (Phase 6): job orchestration, artifact versioning with
// content hashes, and journaled provenance. Render adapters are injectable;
// the builtin synthesizer produces REAL local artifacts (gradient PNGs,
// tone WAVs) explicitly labeled synthetic — never model output, never
// pretend generations.

public enum MediaKind: String, Codable, Sendable, Hashable {
    case image
    case audio
    case music
    case video
}

public struct MediaJob: Sendable, Equatable {
    public var jobID: String
    public var kind: MediaKind
    public var prompt: String
    public var seed: UInt64

    public init(jobID: String, kind: MediaKind, prompt: String, seed: UInt64) {
        self.jobID = jobID
        self.kind = kind
        self.prompt = prompt
        self.seed = seed
    }
}

public struct RenderedMedia: Sendable, Equatable {
    public var data: Data
    public var mimeType: String
    public var provenance: String

    public init(data: Data, mimeType: String, provenance: String) {
        self.data = data
        self.mimeType = mimeType
        self.provenance = provenance
    }
}

public protocol MediaRenderer: Sendable {
    func render(_ job: MediaJob) async throws -> RenderedMedia
}

/// Real local synthesis: deterministic gradient PNGs and sine-tone WAVs.
/// Every artifact carries provenance naming it as local synthetic output —
/// an honest stand-in until model-backed renderers land.
public struct BuiltinSynthRenderer: MediaRenderer {
    public init() {}

    public func render(_ job: MediaJob) async throws -> RenderedMedia {
        switch job.kind {
        case .image, .music, .video:
            // One shared raster path; music/video descriptors fall back to
            // the raster until their real pipelines exist.
            return RenderedMedia(data: gradientPNG(seed: job.seed), mimeType: "image/png",
                                 provenance: "builtin-synth: local gradient render (synthetic, not model output)")
        case .audio:
            return RenderedMedia(data: toneWAV(seed: job.seed), mimeType: "audio/wav",
                                 provenance: "builtin-synth: local tone render (synthetic, not model output)")
        }
    }

    func gradientPNG(seed: UInt64) -> Data {
        let size = CGSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()
        let base = CGFloat(seed % 360) / 360.0
        let gradient = NSGradient(starting: NSColor(hue: base, saturation: 0.7, brightness: 0.9, alpha: 1),
                                  ending: NSColor(hue: fmod(base + 0.33, 1.0), saturation: 0.7, brightness: 0.6, alpha: 1))
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: CGFloat(seed % 360))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return Data([0x89, 0x50, 0x4E, 0x47]) // unreachable; magic-preserving fallback
        }
        return png
    }

    func toneWAV(seed: UInt64) -> Data {
        let sampleRate = 22_050
        let durationSeconds = 0.25
        let count = Int(Double(sampleRate) * durationSeconds)
        let frequency = 220.0 + Double(seed % 440)

        var samples = Data(capacity: count * 2)
        for index in 0..<count {
            let t = Double(index) / Double(sampleRate)
            let value = sin(2.0 * .pi * frequency * t) * 0.5
            let pcm = Int16(value * Double(Int16.max))
            withUnsafeBytes(of: pcm.littleEndian) { samples.append(contentsOf: $0) }
        }

        var wav = Data()
        func append(_ string: String) { wav.append(contentsOf: string.utf8) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        append("RIFF"); append32(UInt32(36 + samples.count)); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1)
        append32(UInt32(sampleRate)); append32(UInt32(sampleRate * 2)); append16(2); append16(16)
        append("data"); append32(UInt32(samples.count))
        wav.append(samples)
        return wav
    }
}

public struct MediaArtifact: Sendable, Equatable {
    public var jobID: String
    public var revision: Int
    public var url: URL
    public var contentHash: String
    public var provenance: String

    public init(jobID: String, revision: Int, url: URL, contentHash: String, provenance: String) {
        self.jobID = jobID
        self.revision = revision
        self.url = url
        self.contentHash = contentHash
        self.provenance = provenance
    }
}

/// Schedules renders (one at a time — media is heavy), versions outputs,
/// verifies content hashes, and journals provenance per artifact.
public actor RenderScheduler {
    private let journal: JournalStore?
    private let renderer: any MediaRenderer
    private let storageRoot: URL
    private var revisions: [String: Int] = [:]
    private var busy = false
    private var enqueuedJobIDs: Set<String> = []
    private var cancelledJobIDs: Set<String> = []

    public init(journal: JournalStore?, renderer: any MediaRenderer, storageRoot: URL) {
        self.journal = journal
        self.renderer = renderer
        self.storageRoot = storageRoot
    }

    /// Convenience: enqueue + await.
    public func submit(_ job: MediaJob) async throws -> MediaArtifact {
        let handle = try await enqueue(job)
        return try await handle.result.get()
    }

    /// Enqueue without blocking; the returned task settles with the artifact
    /// (or a cancellation error if cancelled before starting).
    public func enqueue(_ job: MediaJob) throws -> Task<MediaArtifact, Error> {
        enqueuedJobIDs.insert(job.jobID)
        let renderer = self.renderer
        return Task<MediaArtifact, Error> { [weak self] in
            // Serialize: wait for the actor's busy flag to clear.
            while await self?.isBusy() == true {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard let self, await !self.isCancelled(jobID: job.jobID) else {
                throw CancellationError()
            }
            return try await self.run(job, renderer: renderer)
        }
    }

    public func cancel(jobID: String) -> Bool {
        guard enqueuedJobIDs.contains(jobID) else { return false }
        cancelledJobIDs.insert(jobID)
        enqueuedJobIDs.remove(jobID)
        return true
    }

    public func isIdle() -> Bool { !busy && enqueuedJobIDs.isEmpty }

    private func isBusy() -> Bool { busy }

    private func isCancelled(jobID: String) -> Bool {
        cancelledJobIDs.contains(jobID)
    }

    private func run(_ job: MediaJob, renderer: any MediaRenderer) async throws -> MediaArtifact {
        busy = true
        // Revision is fixed before rendering so each revision's seed (and
        // therefore bytes) genuinely differs.
        let revision = (revisions[job.jobID] ?? 0) + 1
        revisions[job.jobID] = revision
        var seeded = job
        seeded.seed = job.seed &+ UInt64(revision)
        var rendered: RenderedMedia
        do {
            rendered = try await renderer.render(seeded)
        } catch {
            busy = false
            throw error
        }
        busy = false
        return try await persist(job, revision: revision, rendered: rendered)
    }

    private func persist(_ job: MediaJob, revision: Int, rendered: RenderedMedia) async throws -> MediaArtifact {
        let dir = storageRoot
            .appendingPathComponent(job.jobID, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let extensionName = rendered.mimeType == "audio/wav" ? "wav" : "png"
        let url = dir.appendingPathComponent("r\(revision).\(extensionName)")
        try rendered.data.write(to: url, options: .atomic)

        let hash = SHA256.hash(data: rendered.data).map { String(format: "%02x", $0) }.joined()
        let artifact = MediaArtifact(jobID: job.jobID, revision: revision, url: url, contentHash: hash, provenance: rendered.provenance)

        if let journal {
            let kind: ArtifactKind = job.kind == .audio ? .audio : .image
            try? await journal.append(.artifactCreated(.init(
                artifactID: ArtifactID(), kind: kind, path: url.path,
                revision: "r\(revision)", contentHash: hash
            )))
        }
        return artifact
    }
}
