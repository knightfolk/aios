import Testing
@testable import ModelRuntime

/// Compile placeholder until real hybrid tests land in this phase's tasks.
@Test func hybridTargetPlaceholder() {
    #expect(ModelRuntimeInfo.schemaVersion == 2)
}
