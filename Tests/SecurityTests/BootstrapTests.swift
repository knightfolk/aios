import Testing
@testable import AIOSCore

/// Bootstrap sanity check only — replaced by real tests as plan tasks land.
@Test func bootstrapSkeletonBuilds() {
    #expect(AIOSCoreInfo.schemaVersion == 1)
}
