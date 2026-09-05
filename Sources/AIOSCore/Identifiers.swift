import Foundation

/// Typed, UUID-backed identifiers. Typed wrappers prevent cross-wiring IDs
/// (e.g. passing a `TaskID` where an `AttemptID` is required) while keeping a
/// uniform single-value JSON representation on the wire.
public protocol TypedIdentifier: Hashable, Codable, Sendable, CustomStringConvertible {
    var rawValue: UUID { get }
    init(rawValue: UUID)
}

extension TypedIdentifier {
    /// Generates a fresh identifier.
    public init() { self.init(rawValue: UUID()) }

    public var description: String { "\(Self.self)(\(rawValue.uuidString))" }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try UUID(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }
}

public struct ProjectID: TypedIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct GoalRevisionID: TypedIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct PlanRevisionID: TypedIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct TaskID: TypedIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct AttemptID: TypedIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct ActionID: TypedIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct ArtifactID: TypedIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct EvidenceID: TypedIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct WorkPackageID: TypedIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct ExpertID: TypedIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}
