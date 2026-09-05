import Foundation
import Testing
@testable import AIOSCore
@testable import ModelRuntime
@testable import CloudRuntime

// URLProtocol stub: recorded fixtures, zero real network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data, [String: String]))?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (status, data, headers) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        handler = nil
        requestCount = 0
    }
}

private func stubbedClient(key: String? = "test-key") -> ZaiClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return ZaiClient(
        profile: testProfile(),
        key: key,
        session: URLSession(configuration: config)
    )
}

private func testProfile() -> ProviderProfile {
    ProviderProfile(
        providerID: "zai",
        endpoint: "https://api.z.ai/api/paas/v4/",
        protocolKind: .openAICompatible,
        models: [ProviderModel(modelID: "glm-4.6", modalities: ["text"], contextWindowTokens: 128_000)],
        billingMode: .payAsYouGo,
        quotaWindows: [],
        rateLimitRPM: 60,
        privacyNotes: "fixture",
        lastVerifiedAt: Date()
    )
}

private func sseBody(_ events: [String]) -> Data {
    Data(events.map { "data: \($0)\n\n" }.joined().utf8)
}

@Suite(.serialized)
struct ZaiClientFixtureTests {

@Test func requestBuildsOpenAICompatibleWireFormat() throws {
    let client = stubbedClient()
    let request = GenerationRequest(
        messages: [ChatMessage(role: .user, content: "hello")],
        maxTokens: 32, temperature: 0, harnessProfileID: "default-v1"
    )
    let urlRequest = try client.makeURLRequest(request, model: "glm-4.6")
    #expect(urlRequest.url?.absoluteString == "https://api.z.ai/api/paas/v4/chat/completions")
    #expect(urlRequest.httpMethod == "POST")
    #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    let body = try #require(urlRequest.httpBody ?? urlRequest.httpBodyStream.map { stream -> Data in
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    })
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(json?["model"] as? String == "glm-4.6")
    #expect((json?["messages"] as? [[String: Any]])?.first?["content"] as? String == "hello")
    #expect(json?["stream"] as? Bool == true)
}

@Test func sseParserHandlesEventsAndDone() {
    var parser = SSEParser()
    var events: [SSEEvent] = []
    let body = sseBody(["{\"delta\":\"hel\"}", "{\"delta\":\"lo\"}", "[DONE]"])
    // Deliver in awkward chunk boundaries to exercise buffering.
    for byte in body {
        events.append(contentsOf: parser.append(Data([byte])))
    }
    let datas = events.map(\.data)
    #expect(datas.count == 3)
    #expect(datas[2] == "[DONE]")
}

@Test func completeAggregatesChunksAndExtractsUsage() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.handler = { _ in
        (200, sseBody([
            "{\"choices\":[{\"delta\":{\"content\":\"You \"}}]}",
            "{\"choices\":[{\"delta\":{\"content\":\"are kind\"}}]}",
            "{\"choices\":[{\"delta\":{}}],\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":5}}",
            "[DONE]",
        ]), ["Content-Type": "text/event-stream"])
    }
    let client = stubbedClient()
    let result = try await client.complete(GenerationRequest(
        messages: [ChatMessage(role: .user, content: "compliment me")],
        maxTokens: 64, temperature: 0, harnessProfileID: "default-v1"
    ))
    #expect(result.outcome == .succeeded)
    #expect(result.text == "You are kind")
    #expect(result.promptTokens == 7)
    #expect(result.completionTokens == 5)
    #expect(StubURLProtocol.requestCount == 1)
}

@Test func httpErrorSurfacesAsFailedResult() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.handler = { _ in
        (401, Data("{\"error\":{\"message\":\"invalid key\"}}".utf8), ["Content-Type": "application/json"])
    }
    let client = stubbedClient()
    let result = try await client.complete(GenerationRequest(
        messages: [ChatMessage(role: .user, content: "x")],
        maxTokens: 8, temperature: 0, harnessProfileID: "default-v1"
    ))
    #expect(result.outcome == .failed)
    #expect(result.detail?.contains("401") == true)
}

@Test func missingKeyIsNotConfiguredWithZeroRequests() async throws {
    StubURLProtocol.reset()
    let client = stubbedClient(key: nil)
    let result = try await client.complete(GenerationRequest(
        messages: [ChatMessage(role: .user, content: "x")],
        maxTokens: 8, temperature: 0, harnessProfileID: "default-v1"
    ))
    #expect(result.outcome == .notConfigured)
    #expect(StubURLProtocol.requestCount == 0)
}

@Test func localOnlyRefusesBeforeAnyConnection() async throws {
    StubURLProtocol.reset()
    let client = stubbedClient()
    let result = try await client.complete(
        GenerationRequest(messages: [ChatMessage(role: .user, content: "x")],
                          maxTokens: 8, temperature: 0, harnessProfileID: "default-v1"),
        localOnly: true
    )
    #expect(result.outcome == .refused)
    #expect(result.detail?.contains("Local Only") == true)
    #expect(StubURLProtocol.requestCount == 0)
}

@Test func bundledZaiProfileLoads() throws {
    let profile = try ProviderProfile.loadBundled(providerID: "zai")
    #expect(profile.providerID == "zai")
    #expect(profile.protocolKind == .openAICompatible)
    #expect(profile.endpoint.hasPrefix("https://"))
    #expect(!profile.models.isEmpty)
}
}
