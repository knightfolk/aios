import Foundation
import AIOSCore

/// Result of replaying a journal. `tornTail` is true when the file ends in a
/// truncated or corrupt frame — the replayable prefix is returned and the
/// damage is reported, never silently skipped.
public struct ReplayResult: Sendable {
    public var records: [EventRecord]
    public var tornTail: Bool
    public var unreadableBytesFromOffset: Int?

    public init(records: [EventRecord], tornTail: Bool, unreadableBytesFromOffset: Int? = nil) {
        self.records = records
        self.tornTail = tornTail
        self.unreadableBytesFromOffset = unreadableBytesFromOffset
    }
}

public enum JournalReader {
    private static let decoder = JSONDecoder()

    /// Reads a journal file sequentially. Stops at the first frame that is
    /// truncated, corrupt, or in an unsupported future format, and flags the
    /// tail as torn. Bytes after damage are never trusted.
    public static func readAllEvents(at url: URL) throws -> ReplayResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ReplayResult(records: [], tornTail: false)
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var records: [EventRecord] = []
        var offset = 0

        while offset < data.count {
            guard data.count - offset >= FrameCodec.headerLength else {
                return ReplayResult(records: records, tornTail: true, unreadableBytesFromOffset: offset)
            }

            let magic = read32(data, offset)
            guard magic == FrameCodec.magic else {
                return ReplayResult(records: records, tornTail: true, unreadableBytesFromOffset: offset)
            }

            let frameVersion = read32(data, offset + 4)
            guard frameVersion == FrameCodec.currentFrameVersion else {
                return ReplayResult(records: records, tornTail: true, unreadableBytesFromOffset: offset)
            }

            let payloadLength = Int(read32(data, offset + 8))
            let expectedCRC = read32(data, offset + 12)
            let payloadStart = offset + FrameCodec.headerLength

            guard data.count - payloadStart >= payloadLength else {
                return ReplayResult(records: records, tornTail: true, unreadableBytesFromOffset: offset)
            }

            let payload = data.subdata(in: payloadStart..<(payloadStart + payloadLength))
            guard CRC32.checksum(payload) == expectedCRC else {
                return ReplayResult(records: records, tornTail: true, unreadableBytesFromOffset: offset)
            }

            let record: EventRecord
            do {
                record = try decoder.decode(EventRecord.self, from: payload)
            } catch {
                // CRC passed but JSON is undecodable: treat as a damaged tail,
                // not as a skip-able frame. Never trust bytes after damage.
                return ReplayResult(records: records, tornTail: true, unreadableBytesFromOffset: offset)
            }
            records.append(record)
            offset = payloadStart + payloadLength
        }

        return ReplayResult(records: records, tornTail: false)
    }

    private static func read32(_ data: Data, _ offset: Int) -> UInt32 {
        let bytes = data.subdata(in: offset..<(offset + 4))
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
