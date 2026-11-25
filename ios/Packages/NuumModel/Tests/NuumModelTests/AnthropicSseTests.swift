import Foundation
import NuumContracts
import Testing
@testable import NuumModel

@Test func thinkingDeltaAndInputJsonDelta() async throws {
    let server = FakeHTTPServer()
    try server.start()
    defer { server.stop() }
    server.enqueue(.sse(
        #"{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"plan"}}"#,
        #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"hello"}}"#,
        #"{"type":"content_block_start","content_block":{"type":"tool_use","id":"toolu_1","name":"read"}}"#,
        #"{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}"#,
        #"{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"\"notes.md\"}"}}"#,
        #"{"type":"content_block_stop"}"#
    ))
    let port = providerModel(
        .anthropic,
        client: testClient(),
        anthropicURL: server.baseURL
    )
    let chunks = try await collect(port.streamChat(chatRequest(
        provider: .anthropic,
        model: "claude-sonnet-4-20250514",
        apiKey: anthropicKey,
        messages: [
            chatMessage(.system, "You are Nuum", id: "s1"),
            chatMessage(.system, "Be brief", id: "s2"),
            chatMessage(.user, "look", images: [pngImage()]),
        ]
    )))

    #expect(chunks.count == 3)
    #expect(chunks[0] == .thinking("plan"))
    #expect(chunks[1] == .text("hello"))
    #expect(chunks[2] == .toolCall(id: "toolu_1", name: "read", arguments: ["path": .string("notes.md")]))

    let recorded = try #require(await server.takeRequest())
    #expect(recorded.path == "/v1/messages")
    #expect(recorded.header("x-api-key") == anthropicKey)
    #expect(recorded.header("anthropic-version") == anthropicVersion)
    #expect(recorded.header("Authorization") == nil)
    let root = try jsonObject(recorded.body)
    #expect(root["system"] as? String == "You are Nuum\n\nBe brief")
    #expect((root["max_tokens"] as? NSNumber)?.intValue == 4096)
    let messages = try #require(root["messages"] as? [Any])
    #expect(messages.count == 1)
    let user = try #require(messages[0] as? [String: Any])
    #expect(user["role"] as? String == "user")
    #expect(recorded.body.contains(imagePayload))
    #expect(recorded.body.contains("base64"))
    #expect(!recorded.body.contains("\"role\":\"system\""))
    let tools = try #require(root["tools"] as? [Any])
    let schema = try #require((tools[0] as? [String: Any])?["input_schema"] as? [String: Any])
    #expect(schema["type"] as? String == "object")
}
