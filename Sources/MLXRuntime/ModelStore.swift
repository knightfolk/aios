import Foundation
import CryptoKit
import CommonCrypto
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

        var context = CC_SHA1_CTX()
        CC_SHA1_Init(&context)
        var header = Data("blob \(size)\0".utf8)
        _ = header.withUnsafeBytes { CC_SHA1_Update(&context, $0.baseAddress, CC_LONG($0.count)) }
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            _ = chunk.withUnsafeBytes { CC_SHA1_Update(&context, $0.baseAddress, CC_LONG($0.count)) }
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CC_SHA1_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
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

        // Persist the manifest alongside the weights so workers can report
        // provenance without re-reading the registry.
        let manifestCopy = directory(for: manifest).appendingPathComponent("aios-manifest.json")
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: manifestCopy, options: .atomic)
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
