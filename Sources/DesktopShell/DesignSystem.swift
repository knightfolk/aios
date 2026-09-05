import Foundation
import SwiftUI
import AIOSCore

// Step 3a: per-project layout persistence (docs 06 — the desktop restores
// its card scale and pinned cards when reopened).

public enum CardScale: String, Codable, Sendable, Equatable {
    case compact
    case comfortable
    case spacious

    var minimumCardWidth: CGFloat {
        switch self {
        case .compact: 200
        case .comfortable: 260
        case .spacious: 340
        }
    }
}

public struct ProjectLayout: Codable, Sendable, Equatable {
    public var cardScale: CardScale
    public var pinnedCardIDs: [String]
    public var showsTimelineRuler: Bool

    public static let `default` = ProjectLayout(cardScale: .comfortable, pinnedCardIDs: [], showsTimelineRuler: true)

    public init(cardScale: CardScale, pinnedCardIDs: [String], showsTimelineRuler: Bool) {
        self.cardScale = cardScale
        self.pinnedCardIDs = pinnedCardIDs
        self.showsTimelineRuler = showsTimelineRuler
    }
}

public struct ProjectLayoutStore {
    public let storageRoot: URL

    public init(storageRoot: URL) {
        self.storageRoot = storageRoot
    }

    private func url(for projectID: ProjectID) -> URL {
        storageRoot.appendingPathComponent(projectID.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("layout.json")
    }

    public func load(for projectID: ProjectID) throws -> ProjectLayout {
        guard let data = try? Data(contentsOf: url(for: projectID)) else { return .default }
        return (try? JSONDecoder().decode(ProjectLayout.self, from: data)) ?? .default
    }

    public func save(_ layout: ProjectLayout, for projectID: ProjectID) throws {
        let target = url(for: projectID)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(layout).write(to: target, options: .atomic)
    }
}

// Step 3b: the design language — typed semantic tokens, applied instead of
// ad hoc colors/fonts (docs 01: futuristic through capability and
// responsiveness, not fake HUD styling; past is visually unmistakable).

public enum DesignRole: String, Sendable, Equatable, CaseIterable {
    case surfaceLive
    case surfaceHistory
    case surfacePanel
    case accentVerified
    case attentionNeeded
    case laneBranch
    case textPrimary
    case textSecondary
}

public struct DesignToken: Sendable, Equatable {
    public var role: DesignRole
    public var color: Color

    public init(role: DesignRole, color: Color) {
        self.role = role
        self.color = color
    }
}

public enum AIOSDesign {
    public static let tokens: [DesignToken] = [
        .init(role: .surfaceLive, color: Color.accentColor.opacity(0.10)),
        .init(role: .surfaceHistory, color: Color.gray.opacity(0.18)),
        .init(role: .surfacePanel, color: Color.primary.opacity(0.05)),
        .init(role: .accentVerified, color: .green),
        .init(role: .attentionNeeded, color: .orange),
        .init(role: .laneBranch, color: .purple),
        .init(role: .textPrimary, color: .primary),
        .init(role: .textSecondary, color: .secondary),
    ]

    public static let spacingSteps: [CGFloat] = [4, 8, 12, 16, 24]

    public static func token(_ role: DesignRole) -> Color {
        tokens.first { $0.role == role }?.color ?? .accentColor
    }

    public struct FontSpec: Sendable, Equatable {
        public var role: String
        public var weight: Font.Weight
        public var size: CGFloat
    }

    public static func fontRole(_ name: String) -> FontSpec {
        switch name {
        case "cardTitle": FontSpec(role: "cardTitle", weight: .semibold, size: 13)
        case "headline": FontSpec(role: "headline", weight: .bold, size: 20)
        default: FontSpec(role: name, weight: .regular, size: 13)
        }
    }
}
