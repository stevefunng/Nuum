import Foundation
import NuumContracts
import Testing
@testable import NuumModel

@Test func stitchesOpenAIToolCallDeltasAndSendsImages() async throws {
    let server = FakeHTTPServer()
    try server.start()
    defer { server.stop() }
    server.enqueue(.sse(
        #"{"choices":[{"delta":{"content":"On it"}}]}"#,
        #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_read","function":{"name":"re"}}]}}]}"#,
        #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"ad","arguments":"{\"path\":"}}]}}]}"#,
        #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"notes.txt\",\"force\":true}"}}]}}]}"#,
        #"{"choices":[{"delta":{"tool_calls":[{"index":1,"id":"call_list","function":{"name":"list","arguments":"{}"}}]}}]}"#,
        "[DONE]"
    ))
    let port = providerModel(
        .openai,
        client: testClient(),
        openAIURL: server.baseURL
    )
    let chunks = try await collect(port.streamChat(chatRequest(
        provider: .openai,
        model: "gpt-4o",
        apiKey: openAIKey,
        messages: [
            chatMessage(.user, "look", images: [pngImage()]),
            chatMessage(
                .assistant,
                "",
                id: "a1",
                thinking: "plan",
                toolCalls: [ToolCall(id: "call_old", name: "read", arguments: ["path": .string("old.txt")])]
            ),
        ],
        maxOutputTokens: 128
    )))

    #expect(chunks.count == 3)
    #expect(chunks[0] == .text("On it"))
    #expect(chunks[1] == .toolCall(
        id: "call_read",
        name: "read",
        arguments: ["path": .string("notes.txt"), "force": .bool(true)]
    ))
    #expect(chunks[2] == .toolCall(id: "call_list", name: "list", arguments: [:]))

    let recorded = try #require(await server.takeRequest())
    #expect(recorded.path == "/v1/chat/completions")
    #expect(recorded.header("Authorization") == "Bearer \(openAIKey)")
    #expect(recorded.body.contains("data:image/png;base64,\(imagePayload)"))
    let root = try jsonObject(recorded.body)
    #expect(root["model"] as? String == "gpt-4o")
    #expect((root["max_tokens"] as? NSNumber)?.intValue == 128)
    let messages = try #require(root["messages"] as? [Any])
    let assistant = try #require(messages[1] as? [String: Any])
    #expect(assistant["content"] is NSNull)
    #expect(assistant["reasoning_content"] as? String == "plan")
    let replay = try #require(assistant["tool_calls"] as? [Any])
    let function = try #require((replay[0] as? [String: Any])?["function"] as? [String: Any])
    #expect((function["arguments"] as? String)?.contains("old.txt") == true)
}

@Test func reasoningContentBecomesThinkingBeforeText() async throws {
    let server = FakeHTTPServer()
    try server.start()
    defer { server.stop() }
    server.enqueue(.sse(
        #"{"choices":[{"delta":{"reasoning_content":"plan","content":"hello"}}]}"#,
        "[DONE]"
    ))
    let model = OpenAIModel(client: testClient(), baseURL: server.baseURL, label: openAILabel)
    let chunks = try await collect(model.streamChat(chatRequest(
        provider: .openai,
        model: "gpt-4o",
        apiKey: openAIKey
    )))
    #expect(chunks == [.thinking("plan"), .text("hello")])
}

@Test func deepSeekOmitsImages() async throws {
    let server = FakeHTTPServer()
    try server.start()
    defer { server.stop() }
    server.enqueue(.sse(
        #"{"choices":[{"delta":{"reasoning_content":"skip the picture"}}]}"#,
        "[DONE]"
    ))
    let port = providerModel(
        .deepseek,
        client: testClient(),
        deepSeekURL: server.baseURL
    )
    let chunks = try await collect(port.streamChat(chatRequest(
        provider: .deepseek,
        model: "deepseek-chat",
        apiKey: deepSeekKey,
        messages: [chatMessage(.user, "look", images: [pngImage()])]
    )))
    #expect(chunks == [.thinking("skip the picture")])

    let recorded = try #require(await server.takeRequest())
    #expect(recorded.header("Authorization") == "Bearer \(deepSeekKey)")
    #expect(recorded.path == "/v1/chat/completions")
    #expect(!recorded.body.contains(imagePayload))
    #expect(!recorded.body.contains("image_url"))
    #expect(!recorded.body.contains("base64"))
    #expect(recorded.body.contains("does not accept image input"))
    #expect(recorded.body.contains("look"))
}

@Test func disallowedImageMIMEIsNotUploaded() async throws {
    let server = FakeHTTPServer()
    try server.start()
    defer { server.stop() }
    server.enqueue(.sse(
        #"{"choices":[{"delta":{"content":"ok"}}]}"#,
        "[DONE]"
    ))
    let model = OpenAIModel(client: testClient(), baseURL: server.baseURL, label: openAILabel)
    _ = try await collect(model.streamChat(chatRequest(
        provider: .openai,
        model: "gpt-4o",
        apiKey: openAIKey,
        messages: [
            chatMessage(.user, "look", images: [ModelImage(mimeType: "image/svg+xml", data: imagePayload)]),
        ]
    )))
    let recorded = try #require(await server.takeRequest())
    #expect(!recorded.body.contains(imagePayload))
    #expect(!recorded.body.contains("image_url"))
    #expect(recorded.body.contains("look"))
}
