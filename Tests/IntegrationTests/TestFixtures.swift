import Foundation
import Testing
@testable import AIOSCore
@testable import ExecutionFabric

// Shared IntegrationTests fixtures (extracted from VerticalSliceTests).

func packageExecutable(_ name: String) throws -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = packageRoot.appendingPathComponent(".build/debug/\(name)")
    #expect(FileManager.default.fileExists(atPath: url.path), "missing executable: \(url.path)")
    return url
}

/// Cursor-based event collector (shared pattern, IntegrationTests copy).
struct SessionEventCollector {
    private var cursor: Int

    init(session: WorkerSession) async {
        cursor = await session.eventHistory().count
    }

    mutating func drain(from session: WorkerSession) async -> [WorkerSession.Event] {
        let events = await session.eventHistory()
        guard cursor < events.count else { return [] }
        let new = Array(events[cursor...])
        cursor = events.count
        return Array(new)
    }
}
