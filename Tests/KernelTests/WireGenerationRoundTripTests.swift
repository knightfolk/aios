import Foundation
import Testing
@testable import AIOSCore
@testable import ModelRuntime
@testable import ExecutionFabric

@Test func generationMessagesRoundTripThroughWire() throws {
    let request = WireMessage.generationRequest(GenerationRequest(
        messages: [ChatMessage(role: .user, content: "summarize the goal")],
        maxTokens: 128,
        temperature: 0,
        harnessProfileID: "default-v1"
    ))
    let chunk = WireMessage.generationChunk(GenerationChunk(text: "The goal is"))
    let done = WireMessage.generationDone(GenerationResult(
        text: "The goal is to fix the parser.",
        promptTokens: 12, completionTokens: 8, latencyMs: 42.5,
        outcome: .succeeded
    ))

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for message in [request, chunk, done] {
        let decoded = try decoder.decode(WireMessage.self, from: encoder.encode(message))
        #expect(decoded == message)
    }
}
