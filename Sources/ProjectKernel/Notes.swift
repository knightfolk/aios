import Foundation
import AIOSCore
import EventJournal

// Desk Notes and Project Inbox (docs 01/06): lightweight capture surfaces.
// Stored OUTSIDE the journal — they are scratch, not engine state, and they
// are never instructions until explicitly promoted; promotion is the only
// journaled step.

public struct NoteRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var createdAt: Date

    public init(id: String, text: String, createdAt: Date) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

public struct InboxItemRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var createdAt: Date
    public var discarded: Bool

    public init(id: String, text: String, createdAt: Date, discarded: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.discarded = discarded
    }
}

public actor NotesStore {
    private let journal: JournalStore
    private let fileURL: URL

    public init(journal: JournalStore, storageRoot: URL) {
        self.journal = journal
        self.fileURL = storageRoot
            .appendingPathComponent(journal.projectID.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("notes.json")
    }

    @discardableResult
    public func create(text: String) throws -> NoteRecord {
        var notes = (try? load()) ?? []
        let note = NoteRecord(id: "note-\(UUID().uuidString.prefix(8))", text: text, createdAt: Date())
        notes.append(note)
        try persist(notes)
        return note
    }

    public func load() throws -> [NoteRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([NoteRecord].self, from: data)) ?? []
    }

    /// Notes are not instructions until promoted — this is the explicit,
    /// journaled promotion step.
    public func promote(noteID: String, target: String, summary: String) async throws {
        try await journal.append(.notePromoted(.init(noteID: noteID, target: target, summary: summary)))
    }

    private func persist(_ notes: [NoteRecord]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(notes).write(to: fileURL, options: .atomic)
    }
}

public actor InboxStore {
    private let journal: JournalStore
    private let fileURL: URL

    public init(journal: JournalStore, storageRoot: URL) {
        self.journal = journal
        self.fileURL = storageRoot
            .appendingPathComponent(journal.projectID.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("inbox.json")
    }

    @discardableResult
    public func create(text: String) throws -> InboxItemRecord {
        var items = (try? load()) ?? []
        let item = InboxItemRecord(id: "inb-\(UUID().uuidString.prefix(8))", text: text, createdAt: Date())
        items.append(item)
        try persist(items)
        return item
    }

    public func load() throws -> [InboxItemRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([InboxItemRecord].self, from: data)) ?? []
    }

    /// Promote to GOAL | TASK | TIMELINE_PIN, or DISCARDED (kept, marked).
    public func promote(itemID: String, target: String, summary: String) async throws {
        var items = try load()
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            if target == "DISCARDED" {
                items[index].discarded = true
                try persist(items)
            }
        }
        try await journal.append(.inboxItemPromoted(.init(itemID: itemID, target: target, summary: summary)))
    }

    private func persist(_ items: [InboxItemRecord]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
    }
}
