import Foundation
import AIOSCore

// OS layer (per spec): per-project desktop session state and the pure card
// ordering model that drag-and-drop drives. Everything persists outside the
// journal — it is UI state, not engine state.

/// The working state of one project desktop, restored on switch.
public struct DesktopSession: Codable, Sendable, Equatable {
    public var selectedExpert: String?
    public var expandedPanels: [String]
    public var lastScrubSequence: UInt64?
    /// Card IDs in user arrangement; drives the grid with the ordering model.
    public var cardOrder: [String]

    public static let `default` = DesktopSession(
        selectedExpert: nil,
        expandedPanels: [],
        lastScrubSequence: nil,
        cardOrder: []
    )

    public init(selectedExpert: String?, expandedPanels: [String], lastScrubSequence: UInt64?, cardOrder: [String]) {
        self.selectedExpert = selectedExpert
        self.expandedPanels = expandedPanels
        self.lastScrubSequence = lastScrubSequence
        self.cardOrder = cardOrder
    }
}

public struct DesktopSessionStore {
    public let storageRoot: URL

    public init(storageRoot: URL) {
        self.storageRoot = storageRoot
    }

    private func url(for projectID: ProjectID) -> URL {
        storageRoot.appendingPathComponent(projectID.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("session.json")
    }

    public func load(for projectID: ProjectID) throws -> DesktopSession {
        guard let data = try? Data(contentsOf: url(for: projectID)) else { return .default }
        return (try? JSONDecoder().decode(DesktopSession.self, from: data)) ?? .default
    }

    public func save(_ session: DesktopSession, for projectID: ProjectID) throws {
        let target = url(for: projectID)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: target, options: .atomic)
    }
}

/// Pure ordering model for the card grid: pinned cards first, then the
/// user's order, then unseen cards in default order. Reordering is a pure
/// function so drag-and-drop logic is fully testable.
public struct CardOrdering: Codable, Sendable, Equatable {
    public var order: [String]
    public var pinned: [String]

    public init(order: [String] = [], pinned: [String] = []) {
        self.order = order
        self.pinned = pinned
    }

    public static func sorted(available: [String], ordering: CardOrdering) -> [String] {
        let availableSet = Set(available)
        let pinnedFirst = ordering.pinned.filter { availableSet.contains($0) }
        var seen = Set(pinnedFirst)
        var result = pinnedFirst
        for id in ordering.order where availableSet.contains(id) && !seen.contains(id) {
            result.append(id)
            seen.insert(id)
        }
        for id in available where !seen.contains(id) {
            result.append(id)
            seen.insert(id)
        }
        return result
    }

    public static func move(_ id: String, toAfter anchor: String, in list: [String]) -> [String] {
        guard id != anchor,
              let fromIndex = list.firstIndex(of: id),
              let anchorIndex = list.firstIndex(of: anchor) else {
            return list
        }
        var copy = list
        copy.remove(at: fromIndex)
        let insertIndex = copy.firstIndex(of: anchor).map { $0 + 1 } ?? copy.count
        copy.insert(id, at: insertIndex)
        return copy
    }
}
