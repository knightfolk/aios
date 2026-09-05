import Foundation
import AIOSCore
import ModelRuntime

public enum ZaiError: Error, Equatable {
    case httpStatus(Int, String)
    case transport(String)
    case malformedResponse(String)
}

/// One Z.ai (OpenAI-compatible) cloud runtime connection. The key arrives
/// from the CredentialBroker; nothing here logs or journals it. Local Only is
/// enforced before any connection is opened.
public final class ZaiClient: @unchecked Sendable {
    public enum StreamEvent: Sendable {
        case chunk(GenerationChunk)
        case done(GenerationResult)
    }

    private let profile: ProviderProfile
    private let key: String?
    private let session: URLSession

    public init(profile: ProviderProfile, key: String?, session: URLSession = .shared) {
        self.profile = profile
        self.key = key
        self.session = session
    }

    public var defaultModel: String {
        profile.models.first?.modelID ?? "glm-4.6"
    }

    // MARK: - Request building (visible for fixture tests)

    public func makeURLRequest(_ request: GenerationRequest, model: String) throws -> URLRequest {
        guard let url = URL(string: profile.endpoint) else {
            throw ZaiError.malformedResponse("bad endpoint \(profile.endpoint)")
        }
        var urlRequest = URLRequest(url: url.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key ?? "")", forHTTPHeaderField: "Authorization")

        struct WireBody: Codable {
            struct WireChatMessage: Codable {
                var role: String
                var content: String
            }
            var model: String
            var messages: [WireChatMessage]
            var stream: Bool
            var max_tokens: Int
            var temperature: Double
        }
        let body = WireBody(
            model: model,
            messages: request.messages.map {
                WireBody.WireChatMessage(role: $0.role.rawValue, content: $0.content)
            },
            stream: true,
            max_tokens: request.maxTokens,
            temperature: request.temperature
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    // MARK: - Completion

    /// Streams an OpenAI-compatible chat completion over SSE, then emits the
    /// aggregated `.done` result with usage extracted from the final chunk.
    public func chat(_ request: GenerationRequest, localOnly: Bool = false)
        -> AsyncThrowingStream<StreamEvent, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await self.run(request: request, model: defaultModel, localOnly: localOnly) { chunk in
                        continuation.yield(.chunk(chunk))
                    }
                    continuation.yield(.done(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Convenience: aggregate a completion into a single result, mapping all
    /// error classes onto typed outcomes (never throwing at the caller).
    public func complete(_ request: GenerationRequest, localOnly: Bool = false) async -> GenerationResult {
        var text = ""
        do {
            for try await event in chat(request, localOnly: localOnly) {
                switch event {
                case .chunk(let chunk):
                    text += chunk.text
                case .done(let result):
                    var final = result
                    final.text = text
                    return final
                }
            }
        } catch let error as ZaiError {
            return GenerationResult(
                text: "", promptTokens: 0, completionTokens: 0, latencyMs: 0,
                outcome: .failed, detail: Self.describe(error)
            )
        } catch {
            return GenerationResult(
                text: "", promptTokens: 0, completionTokens: 0, latencyMs: 0,
                outcome: .failed, detail: "\(error)"
            )
        }
        return GenerationResult(
            text: text, promptTokens: 0, completionTokens: 0, latencyMs: 0,
            outcome: .failed, detail: "stream ended without a result envelope"
        )
    }

    // MARK: - Internals

    private func run(
        request: GenerationRequest,
        model: String,
        localOnly: Bool,
        onChunk: @Sendable (GenerationChunk) -> Void
    ) async throws -> GenerationResult {
        let started = Date()

        if localOnly {
            return GenerationResult(
                text: "", promptTokens: 0, completionTokens: 0, latencyMs: 0,
                outcome: .refused, detail: "Local Only blocks cloud inference before any connection"
            )
        }
        guard let key, !key.isEmpty else {
            return GenerationResult(
                text: "", promptTokens: 0, completionTokens: 0, latencyMs: 0,
                outcome: .notConfigured, detail: "no provider key stored"
            )
        }

        let urlRequest = try makeURLRequest(request, model: model)
        let (bytes, response) = try await session.bytes(for: urlRequest)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await byte in bytes {
                body.append(Character(UnicodeScalar(byte)))
                if body.count > 4096 { break }
            }
            throw ZaiError.httpStatus(http.statusCode, body)
        }

        var parser = SSEParser()
        var text = ""
        var promptTokens = 0
        var completionTokens = 0
        var sawDone = false

        for try await byte in bytes {
            let events = parser.append(Data([byte]))
            for event in events {
                if event.data == "[DONE]" {
                    sawDone = true
                    continue
                }
                guard let payload = event.data.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                    continue
                }
                if let choices = json["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any],
                   let content = delta["content"] as? String, !content.isEmpty {
                    text += content
                    onChunk(GenerationChunk(text: content))
                }
                if let usage = json["usage"] as? [String: Any] {
                    promptTokens = usage["prompt_tokens"] as? Int ?? promptTokens
                    completionTokens = usage["completion_tokens"] as? Int ?? completionTokens
                }
            }
        }

        let latency = Date().timeIntervalSince(started) * 1000
        return GenerationResult(
            text: text,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            latencyMs: latency,
            outcome: .succeeded,
            detail: sawDone ? nil : "stream ended without [DONE]"
        )
    }

    static func describe(_ error: ZaiError) -> String {
        switch error {
        case .httpStatus(let status, let body):
            let clipped = body.prefix(200)
            return "HTTP \(status): \(clipped)"
        case .transport(let detail):
            return "transport: \(detail)"
        case .malformedResponse(let detail):
            return "malformed: \(detail)"
        }
    }
}

extension ProviderProfile {
    /// Loads a bundled provider profile (e.g. `zai-profile.json`).
    public static func loadBundled(providerID: String) throws -> ProviderProfile {
        let url = Bundle.module.url(forResource: "\(providerID)-profile", withExtension: "json")
            ?? Bundle.module.url(forResource: "zai-profile", withExtension: "json")
        guard let url else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(providerID)-profile"])
        }
        return try JSONDecoder().decode(ProviderProfile.self, from: Data(contentsOf: url))
    }
}
