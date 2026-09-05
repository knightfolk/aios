import Foundation
import Testing
@testable import AIOSCore
@testable import EventJournal
@testable import ModelRuntime
@testable import Supervisor

private func profile(limit: Int = 100_000, overflow: Bool = false) -> ProviderProfile {
    ProviderProfile(
        providerID: "zai",
        endpoint: "https://api.example/v4/",
        protocolKind: .openAICompatible,
        models: [],
        billingMode: .payAsYouGo,
        quotaWindows: [QuotaWindow(windowSeconds: 3600, tokenLimit: limit, paidOverflowAllowed: overflow)],
        rateLimitRPM: 60,
        privacyNotes: "test",
        lastVerifiedAt: Date()
    )
}

@Test func usageUnderQuotaProceeds() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-quota-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let supervisor = Supervisor(journal: journal)

    let directive = await supervisor.checkUsage(provider: profile(), projectedTokens: 10_000, usedTokensInWindow: 80_000, allowPaid: false)
    #expect(directive == .proceed)
}

@Test func usageOverQuotaWithoutOverflowIsRefusedAndJournaled() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-quota-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let supervisor = Supervisor(journal: journal)

    let directive = await supervisor.checkUsage(provider: profile(), projectedTokens: 30_000, usedTokensInWindow: 90_000, allowPaid: false)
    guard case .refuseSpend(let reason) = directive else {
        Issue.record("expected quota refusal, got \(directive)")
        return
    }
    #expect(reason.contains("quota"))

    let replay = try JournalReader.readAllEvents(at: journal.journalFileURL)
    let escalations = replay.records.filter { record in
        if case .decisionRequested(let p) = record.event { return p.subject.contains("quota") } else { return false }
    }
    #expect(escalations.count == 1)
}

@Test func overflowRequiresExplicitAuthorization() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aios-quota-\(UUID().uuidString)", isDirectory: true)
    let journal = try JournalStore(projectID: ProjectID(), rootDirectory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let supervisor = Supervisor(journal: journal)

    // Provider allows overflow structurally, but the caller has not
    // authorized paid usage: still refused.
    let unauthorized = await supervisor.checkUsage(provider: profile(overflow: true), projectedTokens: 30_000, usedTokensInWindow: 90_000, allowPaid: false)
    guard case .refuseSpend = unauthorized else {
        Issue.record("overflow must require explicit paid authorization, got \(unauthorized)")
        return
    }

    let authorized = await supervisor.checkUsage(provider: profile(overflow: true), projectedTokens: 30_000, usedTokensInWindow: 90_000, allowPaid: true)
    #expect(authorized == .proceed)
}
