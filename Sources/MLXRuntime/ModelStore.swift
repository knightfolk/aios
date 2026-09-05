import Foundation
import CryptoKit
import AIOSCore
import ModelRuntime

/// Hash helpers. Git blob SHA-1 matches `git hash-object` and the Hugging
/// Face tree API's `oid` for non-LFS files; SHA-256 matches LFS `oid`.
public enum Hashing {
    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(ofFile url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func gitBlobSHA1(of url: URL) throws -> String {
        let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var context = SHA1State()
        context.update(Data("blob \(size)\0".utf8))
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            context.update(chunk)
        }
        return context.finalizeHex()
    }
}

/// Minimal pure-Swift SHA-1 (CryptoKit does not provide it). Used only to
/// verify non-LFS model files against git blob oids.
struct SHA1State {
    private var h: (UInt32, UInt32, UInt32, UInt32, UInt32) = (0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0)
    private var buffer = Data()
    private var length: UInt64 = 0

    mutating func update(_ data: Data) {
        buffer.append(data)
        length &+= UInt64(data.count)
        let blocks = buffer.count / 64
        if blocks > 0 {
            for index in 0..<blocks {
                process(Array(buffer[index * 64..<(index * 64 + 64)]))
            }
            buffer.removeFirst(blocks * 64)
        }
    }

    mutating func finalizeHex() -> String {
        let bitLength = length &* 8
        var padding = Data([0x80])
        while (buffer.count + padding.count) % 64 != 56 {
            padding.append(0)
        }
        var trailer = Data()
        for shift in stride(from: 56, through: 0, by: -8) {
            trailer.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
        }
        update(padding)
        update(trailer)
        // After final update the buffer is exactly one processed block.
        let digest = [h.0, h.1, h.2, h.3, h.4]
        return digest.map { String(format: "%08x", $0) }.joined()
    }

    private mutating func process(_ block: [UInt8]) {
        var w = [UInt32](repeating: 0, count: 80)
        for index in 0..<16 {
            let base = index * 4
            w[index] = (UInt32(block[base]) << 24) | (UInt32(block[base + 1]) << 16)
                | (UInt32(block[base + 2]) << 8) | UInt32(block[base + 3])
        }
        for index in 16..<80 {
            let value = w[index - 3] ^ w[index - 8] ^ w[index - 14] ^ w[index - 16]
            w[index] = (value << 1) | (value >> 31)
        }

        var (a, b, c, d, e) = h
        for index in 0..<80 {
            let f: UInt32
            let k: UInt32
            switch index {
            case 0..<20: f = (b & c) | (~b & d); k = 0x5A827999
            case 20..<40: f = b ^ c ^ d; k = 0x6ED9EBA1
            case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC
            default: f = b ^ c ^ d; k = 0xCA62C1D6
            }
            let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[index]
            e = d
            d = c
            c = (b << 30) | (b >> 2)
            b = a
            a = temp
        }
        h = (h.0 &+ a, h.1 &+ b, h.2 &+ c, h.3 &+ d, h.4 &+ e)
    }
}

/// Downloads and verifies model files (docs 11: hashes and quantization
/// provenance). A model is resident only when every pinned file exists and
/// its hash matches; partial or tampered downloads never count.
public struct ModelStore: Sendable {
    public enum StoreError: Error, Equatable {
        case verificationFailed(filename: String)
        case downloadFailed(filename: String, detail: String)
    }

    public let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            self.root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("AIOS/models", isDirectory: true)
        }
    }

    public func directory(for manifest: ModelManifest) -> URL {
        root.appendingPathComponent(manifest.modelID, isDirectory: true)
    }

    public func isResident(_ manifest: ModelManifest) -> Bool {
        let dir = directory(for: manifest)
        for file in manifest.files {
            let url = dir.appendingPathComponent(file.filename)
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            if let expected = file.sha256, expected.count == 64 {
                guard (try? Hashing.sha256Hex(ofFile: url)) == expected else { return false }
            } else if let blob = file.gitBlobSHA1, blob.count == 40 {
                guard (try? Hashing.gitBlobSHA1(of: url)) == blob else { return false }
            } else {
                return false // unverifiable file can never be resident
            }
        }
        return true
    }

    /// Downloads missing or unverified files, then re-checks residency.
    /// Already-verified files are skipped, making re-fetches cheap and safe.
    public func fetch(
        _ manifest: ModelManifest,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let dir = directory(for: manifest)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let total = manifest.files.count
        var completed = 0
        for file in manifest.files {
            let target = dir.appendingPathComponent(file.filename)
            let alreadyGood = FileManager.default.fileExists(atPath: target.path) && Self.fileMatches(file, at: target)
            if !alreadyGood {
                let part = target.appendingPathExtension("part")
                try? FileManager.default.removeItem(at: part)
                do {
                    // Disk-backed download (URLSession temp file) — the right
                    // tool for multi-GB weight files.
                    let (tempURL, _) = try await URLSession.shared.download(
                        for: URLRequest(url: Self.fileURL(manifest: manifest, file: file))
                    )
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.moveItem(at: tempURL, to: target)
                } catch {
                    throw StoreError.downloadFailed(filename: file.filename, detail: "\(error)")
                }
                guard Self.fileMatches(file, at: target) else {
                    throw StoreError.verificationFailed(filename: file.filename)
                }
            }
            completed += 1
            progress(Double(completed) / Double(total))
        }
        guard isResident(manifest) else {
            throw StoreError.verificationFailed(filename: "<post-fetch>")
        }
    }

    static func fileMatches(_ file: ModelFile, at url: URL) -> Bool {
        if let expected = file.sha256, expected.count == 64 {
            return (try? Hashing.sha256Hex(ofFile: url)) == expected
        }
        if let blob = file.gitBlobSHA1, blob.count == 40 {
            return (try? Hashing.gitBlobSHA1(of: url)) == blob
        }
        return false
    }

    static func fileURL(manifest: ModelManifest, file: ModelFile) -> URL {
        if manifest.sourceURL.hasPrefix("http") {
            // Hugging Face style: <repo>/resolve/main/<file>
            let base = manifest.sourceURL.hasSuffix("/") ? String(manifest.sourceURL.dropLast()) : manifest.sourceURL
            return URL(string: "\(base)/resolve/main/\(file.filename)")!
        }
        return URL(fileURLWithPath: manifest.sourceURL).appendingPathComponent(file.filename)
    }
}
