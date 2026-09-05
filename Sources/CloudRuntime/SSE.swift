import Foundation

public struct SSEEvent: Equatable, Sendable {
    public var data: String

    public init(data: String) {
        self.data = data
    }
}

/// Incremental server-sent-events parser: feed arbitrary byte chunks, get
/// complete `data:` events. Comment lines and CRLF are handled.
public struct SSEParser {
    private var buffer = String()

    public init() {}

    public mutating func append(_ data: Data) -> [SSEEvent] {
        buffer.append(String(decoding: data, as: UTF8.self))
        var events: [SSEEvent] = []
        while let range = buffer.range(of: "\n\n") ?? buffer.range(of: "\r\n\r\n") {
            let block = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            let dataLines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix(":") }
                .compactMap { line -> String? in
                    guard line.hasPrefix("data:") else { return nil }
                    let payload = line.dropFirst("data:".count)
                    return payload.first == " " ? String(payload.dropFirst()) : String(payload)
                }
            guard !dataLines.isEmpty else { continue }
            events.append(SSEEvent(data: dataLines.joined(separator: "\n")))
        }
        return events
    }
}
