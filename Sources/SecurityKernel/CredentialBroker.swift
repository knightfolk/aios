import Foundation
import Security

/// Credential storage boundary (docs 08): secrets live in the Keychain (or
/// an injected store for tests) — never in source, model context, journal,
/// logs, or worker environments.
public protocol SecretStore: Sendable {
    func set(_ secret: String, service: String) throws
    func get(service: String) throws -> String?
    func delete(service: String) throws
}

/// Keychain-backed store for production. Generic passwords, this app only.
public struct KeychainStore: SecretStore {
    public init() {}

    private let account = "aios"

    public func set(_ secret: String, service: String) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public func get(service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

/// Test double; also used by the offline suites.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: String] = [:]

    public init() {}

    public func set(_ secret: String, service: String) throws {
        lock.lock(); defer { lock.unlock() }
        secrets[service] = secret
    }

    public func get(service: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return secrets[service]
    }

    public func delete(service: String) throws {
        lock.lock(); defer { lock.unlock() }
        secrets.removeValue(forKey: service)
    }
}

public final class CredentialBroker: @unchecked Sendable {
    private let store: any SecretStore

    public init(store: any SecretStore = KeychainStore()) {
        self.store = store
    }

    public func setProviderKey(_ key: String, provider: String) throws {
        try store.set(key, service: Self.service(for: provider))
    }

    public func providerKey(_ provider: String) -> String? {
        try? store.get(service: Self.service(for: provider))
    }

    public func hasProviderKey(_ provider: String) -> Bool {
        providerKey(provider) != nil
    }

    public func removeProviderKey(_ provider: String) throws {
        try store.delete(service: Self.service(for: provider))
    }

    static func service(for provider: String) -> String {
        "aios.provider.\(provider)"
    }
}
