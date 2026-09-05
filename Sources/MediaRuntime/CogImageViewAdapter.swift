import Foundation
import AIOSCore
import CloudRuntime
import ModelRuntime
import SecurityKernel

/// Real cloud image generation over the Z.ai OpenAI-compatible images API
/// (`cogview`), behind the existing MediaRenderer seam. Availability is
/// honest: if the provider or model is missing/unauthorized, the adapter
/// reports itself unavailable with the reason — the synthetic builtin stays
/// the fallback, and nothing is faked.
public struct CogImageViewAdapter: MediaRenderer {
    public enum AdapterError: Error, Equatable {
        case notConfigured(String)
    }

    private let session: URLSession
    private let endpoint: URL
    private let key: String?
    private let model: String
    public let unavailabilityReason: String?

    /// Key resolution is env/explicit-only by default: a cross-process
    /// Keychain read from an unsigned binary can hang on an authorization
    /// prompt. Hosts holding a trusted identity pass `useKeychain: true`.
    public init(session: URLSession = .shared, explicitKey: String? = nil, useKeychain: Bool = false) async throws {
        self.session = session
        let profile: ProviderProfile
        do {
            profile = try ProviderProfile.loadBundled(providerID: "zai")
        } catch {
            self.endpoint = URL(string: "https://api.z.ai/api/paas/v4/")!
            self.key = nil
            self.model = "cogview-4-250304" // verified against api.z.ai 2026-09-05; flash variants return unknown-model
            self.unavailabilityReason = "zai profile missing; cogview adapter offline"
            return
        }
        self.endpoint = URL(string: profile.endpoint)!
        let envKey = ProcessInfo.processInfo.environment["AIOS_ZAI_KEY"]
        var keychainKey: String?
        if useKeychain && envKey == nil && explicitKey == nil {
            keychainKey = CredentialBroker().providerKey("zai")
        }
        let resolved = explicitKey ?? envKey ?? keychainKey
        self.key = (resolved?.isEmpty == false) ? resolved : nil
        self.model = "cogview-4-250304" // verified against api.z.ai 2026-09-05; flash variants return unknown-model
        if key == nil {
            self.unavailabilityReason = "no zai key in env/explicit input; cogview unavailable (pass useKeychain: true from a trusted host)"
        } else {
            self.unavailabilityReason = nil
        }
    }

    public func isAvailable() async -> Bool {
        unavailabilityReason == nil
    }

    public func render(_ job: MediaJob) async throws -> RenderedMedia {
        guard let key else {
            throw AdapterError.notConfigured(unavailabilityReason ?? "no key")
        }
        struct Request: Codable {
            var model: String
            var prompt: String
            var size: String
        }
        struct Response: Codable {
            struct Datum: Codable {
                var url: String?
                var b64_json: String?
            }
            var data: [Datum]
            var error: ErrorMessage?

            struct ErrorMessage: Codable {
                var message: String?
            }
        }

        var request = URLRequest(url: endpoint.appendingPathComponent("images/generations"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            Request(model: model, prompt: job.prompt, size: "1024x1024")
        )

        let (data, response) = try await session.synchronousData(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AdapterError.notConfigured("cogview HTTP \(http.statusCode): \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        if let message = decoded.error?.message {
            throw AdapterError.notConfigured("cogview error: \(message)")
        }
        if let b64 = decoded.data.first?.b64_json, let bytes = Data(base64Encoded: b64) {
            return RenderedMedia(data: bytes, mimeType: "image/png", provenance: "cogview:\(model) cloud render")
        }
        if let urlString = decoded.data.first?.url, let url = URL(string: urlString) {
            let (bytes, _) = try await session.synchronousData(for: URLRequest(url: url))
            return RenderedMedia(data: bytes, mimeType: "image/png", provenance: "cogview:\(model) cloud render (fetched)")
        }
        throw AdapterError.notConfigured("cogview returned no image data")
    }
}

extension URLSession {
    func synchronousData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await self.data(for: request)
    }
}
