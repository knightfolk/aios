import Foundation
import AIOSCore

/// Pure-Swift CRC-32 (IEEE 802.3, reflected, poly 0xEDB88320). Matches zlib's
/// `crc32` output; implemented locally to avoid a C shim target.
enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 == 1) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

/// Frame layout: magic ‖ frameVersion ‖ payloadLength ‖ crc32 ‖ payload,
/// all integers big-endian UInt32.
enum FrameCodec {
    static let magic: UInt32 = 0x41494F53 // "AIOS"
    static let headerLength = 16
    static let currentFrameVersion: UInt32 = 1

    enum FrameError: Error, Equatable {
        case badMagic(UInt32)
        case unsupportedFrameVersion(UInt32)
        case truncated(atOffset: Int)
        case crcMismatch(expected: UInt32, actual: UInt32)
    }

    static func encode(_ payload: Data) -> Data {
        var frame = Data(capacity: headerLength + payload.count)
        func append32(_ value: UInt32) {
            withUnsafeBytes(of: value.bigEndian) { frame.append(contentsOf: $0) }
        }
        append32(magic)
        append32(currentFrameVersion)
        append32(UInt32(payload.count))
        append32(CRC32.checksum(payload))
        frame.append(payload)
        return frame
    }
}

/// Append-only journal writer. An actor so concurrent appends serialize and
/// the sequence stays strictly monotonic. The store never rewrites or removes
/// written bytes; recovery from a torn tail is the reader's job.
public actor JournalStore {
    /// Count of failed append attempts since open; zero in healthy
    /// operation. Surfaced so UI/Health can report degraded journaling.
    public private(set) var appendFailureCount: Int = 0

    /// Test seam: increment the failure counter without a real I/O error.
    public func noteAppendFailure() {
        appendFailureCount += 1
    }

    /// Production default root: `~/Library/Application Support/AIOS/projects`.
    /// Tests inject their own root directory.
    public static func defaultRootDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("AIOS/projects", isDirectory: true)
    }

    public nonisolated let projectID: ProjectID
    public nonisolated let rootDirectory: URL
    public nonisolated let journalFileURL: URL
    public private(set) var nextSequence: UInt64

    private var fileHandle: FileHandle?
    private let encoder = JSONEncoder()
    private let fsyncEachAppend: Bool

    public init(projectID: ProjectID, rootDirectory: URL, fsyncEachAppend: Bool = false) throws {
        self.projectID = projectID
        self.rootDirectory = rootDirectory
        self.fsyncEachAppend = fsyncEachAppend
        let fileURL = rootDirectory
            .appendingPathComponent(projectID.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("journal", isDirectory: true)
            .appendingPathComponent("events.journal")
        self.journalFileURL = fileURL

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let existing = try JournalReader.readAllEvents(at: fileURL)
            nextSequence = (existing.records.map(\.sequence).max() ?? 0) + 1
        } else {
            nextSequence = 1
        }
    }

    /// Appends one event and returns the durable record. The sequence is
    /// assigned atomically with the write under actor isolation.
    @discardableResult
    public func append(_ event: EngineEvent) throws -> EventRecord {
        do {
            return try appendNow(event)
        } catch {
            appendFailureCount += 1
            throw error
        }
    }

    private func appendNow(_ event: EngineEvent) throws -> EventRecord {
        let record = EventRecord(
            sequence: nextSequence,
            recordedAt: Date(),
            projectID: projectID,
            event: event
        )
        nextSequence += 1

        let payload = try encoder.encode(record)
        let frame = FrameCodec.encode(payload)

        let handle = try obtainFileHandle()
        try handle.write(contentsOf: frame)
        if fsyncEachAppend {
            try handle.synchronize()
        }
        return record
    }

    private func obtainFileHandle() throws -> FileHandle {
        if let handle = fileHandle { return handle }
        if !FileManager.default.fileExists(atPath: journalFileURL.path) {
            FileManager.default.createFile(atPath: journalFileURL.path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: journalFileURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSFilePathErrorKey: journalFileURL.path,
            ])
        }
        try handle.seekToEnd()
        fileHandle = handle
        return handle
    }

    deinit {
        try? fileHandle?.close()
    }
}
