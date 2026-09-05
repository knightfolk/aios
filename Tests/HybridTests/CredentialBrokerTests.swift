import Foundation
import Testing
@testable import SecurityKernel

@Test func credentialBrokerRoundTripsInMemoryStore() throws {
    let broker = CredentialBroker(store: InMemorySecretStore())
    #expect(broker.providerKey("zai") == nil)

    try broker.setProviderKey("test-key-value", provider: "zai")
    #expect(broker.providerKey("zai") == "test-key-value")

    try broker.removeProviderKey("zai")
    #expect(broker.providerKey("zai") == nil)
}

@Test func serviceNamingIsStable() throws {
    let store = InMemorySecretStore()
    let broker = CredentialBroker(store: store)
    try broker.setProviderKey("v", provider: "zai")
    #expect(try store.get(service: "aios.provider.zai") == "v")
    #expect(try store.get(service: "aios.provider.openai") == nil)
}

@Test func brokerNeverEchoesSecretsInDescriptions() throws {
    let broker = CredentialBroker(store: InMemorySecretStore())
    try broker.setProviderKey("super-secret-value", provider: "zai")
    let described = String(describing: broker)
    #expect(!described.contains("super-secret-value"))
    #expect(broker.hasProviderKey("zai"))
}
