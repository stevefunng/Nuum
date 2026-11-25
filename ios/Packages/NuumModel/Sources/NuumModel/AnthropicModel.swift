import Foundation
import NuumContracts

/// Anthropic Messages API. System turns are lifted to the top-level `system` field.
/// The default `max_tokens` is 4096 when the request does not set one.
public struct AnthropicModel: ModelPort {
    public let baseURL: URL
    let client: ModelHTTPClient

    public init(
        client: ModelHTTPClient = .shared,
        baseURL: URL = anthropicBaseURL
    ) {
        self.client = client
        self.baseURL = baseURL
    }

    public func streamChat(_ request: NormalizedChatRequest) -> AsyncThrowingStream<NormalizedChunk, Error> {
        let state = AnthropicStreamState()
        guard let url = endpoint(baseURL, "/messages") else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NuumError(
                    code: KernelErrorCode.model,
                    message: "\(anthropicLabel) connection failed"
                ))
            }
        }
        let parts = HTTPRequestParts(
            url: url,
            headers: [
                ("Content-Type", "application/json"),
                ("x-api-key", request.apiKey),
                ("anthropic-version", anthropicVersion),
            ],
            body: ModelJSON.data(anthropicPayload(request))
        )
        return streamSSE(
            client: client,
            apiKey: request.apiKey,
            providerWire: ProviderId.anthropic.rawValue,
            label: anthropicLabel,
            parts: parts,
            onLine: { line in
                guard let data = sseData(line), !data.isEmpty, data != "[DONE]" else { return [] }
                return try state.consume(anthropicEvent(data))
            },
            onFinish: { [] }
        )
    }
}

private let defaultMaxTokens: Int64 = 4096

func anthropicPayload(_ request: NormalizedChatRequest) -> WireValue {
    let system = request.messages
        .filter { $0.role == .system }
        .map(\.content)
        .joined(separator: "\n\n")
    var fields: [(String, WireValue)] = [
        ("model", .string(request.model.model)),
        ("max_tokens", .int(request.maxOutputTokens.map(Int64.init) ?? defaultMaxTokens)),
        ("stream", .bool(true)),
    ]
    if !system.isEmpty {
        fields.append(("system", .string(system)))
    }
    let messages = anthropicMessages(request.messages.filter { $0.role != .system })
    fields.append(("messages", .array(messages)))
    fields.append(("tools", .array(request.tools.map { tool in
        .object([
            ("name", .string(tool.name)),
            ("description", .string(tool.description)),
            ("input_schema", ModelJSON.value(.object(tool.inputSchema))),
        ])
    })))
    return .object(fields)
}

func anthropicMessages(_ messages: [ChatMessage]) -> [WireValue] {
    messages.compactMap { message in
        switch message.role {
        case .user:
            return userMessage(message)
        case .assistant:
            return assistantMessage(message)
        case .tool:
            return .object([
                ("role", .string("user")),
                ("content", .array([
                    .object([
                        ("type", .string("tool_result")),
                        ("tool_use_id", message.toolCallId.map(WireValue.string) ?? .null),
                        ("content", .string(message.content)),
                    ]),
                ])),
            ])
        case .system:
            return nil
        }
    }
}

private func userMessage(_ message: ChatMessage) -> WireValue {
    let pictures = allowedImages(message.images)
    if pictures.isEmpty {
        return .object([
            ("role", .string("user")),
            ("content", .string(message.content)),
        ])
    }
    var blocks: [WireValue] = [
        .object([
            ("type", .string("text")),
            ("text", .string(message.content)),
        ])
    ]
    for image in pictures {
        blocks.append(.object([
            ("type", .string("image")),
            ("source", .object([
                ("type", .string("base64")),
                ("media_type", .string(image.mimeType)),
                ("data", .string(image.data)),
            ])),
        ]))
    }
    return .object([
        ("role", .string("user")),
        ("content", .array(blocks)),
    ])
}

private func assistantMessage(_ message: ChatMessage) -> WireValue {
    var blocks: [WireValue] = []
    if let thinking = message.thinking, !thinking.isEmpty {
        blocks.append(.object([
            ("type", .string("thinking")),
            ("thinking", .string(thinking)),
        ]))
    }
    if !message.content.isEmpty {
        blocks.append(.object([
            ("type", .string("text")),
            ("text", .string(message.content)),
        ]))
    }
    for call in message.toolCalls ?? [] {
        blocks.append(.object([
            ("type", .string("tool_use")),
            ("id", .string(call.id)),
            ("name", .string(call.name)),
            ("input", ModelJSON.value(.object(call.arguments))),
        ]))
    }
    let content: WireValue = blocks.isEmpty ? .string(message.content) : .array(blocks)
    return .object([
        ("role", .string("assistant")),
        ("content", content),
    ])
}

private final class AnthropicStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var toolID = ""
    private var toolName = ""
    private var toolArgs = ""

    func consume(_ event: WireValue) throws -> [NormalizedChunk] {
        guard let type = event.field("type")?.string else { return [] }
        switch type {
        case "content_block_delta":
            guard let delta = event.field("delta")?.objectFields else { return [] }
            switch delta.first(where: { $0.0 == "type" })?.1.string {
            case "thinking_delta":
                guard let thinking = delta.first(where: { $0.0 == "thinking" })?.1.string, !thinking.isEmpty else {
                    return []
                }
                return [.thinking(thinking)]
            case "text_delta":
                guard let text = delta.first(where: { $0.0 == "text" })?.1.string, !text.isEmpty else {
                    return []
                }
                return [.text(text)]
            case "input_json_delta":
                lock.lock()
                toolArgs += delta.first(where: { $0.0 == "partial_json" })?.1.string ?? ""
                lock.unlock()
                return []
            default:
                return []
            }
        case "content_block_start":
            guard let block = event.field("content_block")?.objectFields,
                  block.first(where: { $0.0 == "type" })?.1.string == "tool_use"
            else { return [] }
            let rawID = block.first(where: { $0.0 == "id" })?.1.string ?? ""
            let name = block.first(where: { $0.0 == "name" })?.1.string ?? ""
            lock.lock()
            toolID = rawID.isEmpty ? UUID().uuidString.lowercased() : rawID
            toolName = name
            toolArgs = ""
            lock.unlock()
            return []
        case "content_block_stop":
            lock.lock()
            let name = toolName
            let id = toolID
            let args = toolArgs
            if !name.isEmpty { toolName = "" }
            lock.unlock()
            guard !name.isEmpty else { return [] }
            return [.toolCall(id: id, name: name, arguments: try ModelJSON.argumentObject(args))]
        default:
            return []
        }
    }
}

private func anthropicEvent(_ data: String) throws -> WireValue {
    do {
        let value = try ModelJSON.parse(data)
        guard value.objectFields != nil else {
            throw NuumError(code: KernelErrorCode.model, message: "Anthropic returned a malformed stream event")
        }
        return value
    } catch let error as NuumError {
        throw error
    } catch {
        throw NuumError(code: KernelErrorCode.model, message: "Anthropic returned a malformed stream event")
    }
}
