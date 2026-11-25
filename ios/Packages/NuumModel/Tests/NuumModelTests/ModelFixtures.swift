import Foundation
import NuumContracts
@testable import NuumModel

let openAIKey = "sk-test-openai-key"
let anthropicKey = "sk-ant-test-key"
let deepSeekKey = "sk-test-deepseek-key"
let imagePayload = "NUUM_IMAGE_PAYLOAD_9f3c"

func testClient(debugLog: (@Sendable (String) -> Void)? = nil) -> ModelHTTPClient {
    .make(debugLog: debugLog, requestTimeout: 30, resourceTimeout: 30)
}

func chatMessage(
    _ role: MessageRole,
    _ content: String,
    id: String? = nil,
    images: [ModelImage]? = nil,
    thinking: String? = nil,
    toolCalls: [ToolCall]? = nil,
    toolCallId: String? = nil
) -> ChatMessage {
    ChatMessage(
        id: id ?? "m-\(role.rawValue)",
        role: role,
        content: content,
        seq: 1,
        createdAt: 0,
        images: images,
        thinking: thinking,
        toolCalls: toolCalls,
        toolCallId: toolCallId
    )
}

func readTool() -> ToolDefinition {
    ToolDefinition(
        name: "read",
        description: "Read a file",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string")]),
            ]),
        ],
        mutating: false,
        action: .readFile
    )
}

func chatRequest(
    provider: ProviderId,
    model: String,
    apiKey: String,
    messages: [ChatMessage]? = nil,
    maxOutputTokens: Int? = nil
) -> NormalizedChatRequest {
    NormalizedChatRequest(
        model: ModelRef(provider: provider, model: model),
        messages: messages ?? [chatMessage(.user, "hello")],
        tools: [readTool()],
        apiKey: apiKey,
        maxOutputTokens: maxOutputTokens
    )
}

func pngImage() -> ModelImage {
    ModelImage(mimeType: "image/png", data: imagePayload)
}

func collect(_ stream: AsyncThrowingStream<NormalizedChunk, Error>) async throws -> [NormalizedChunk] {
    var chunks: [NormalizedChunk] = []
    for try await chunk in stream {
        chunks.append(chunk)
    }
    return chunks
}

func jsonObject(_ text: String) throws -> [String: Any] {
    let data = Data(text.utf8)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = object as? [String: Any] else {
        throw FixtureError("not an object")
    }
    return dictionary
}

private struct FixtureError: Error {
    var message: String
    init(_ message: String) { self.message = message }
}

final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ line: String) {
        lock.lock()
        text += line
        text += "\n"
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}
