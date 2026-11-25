import Foundation
import NuumContracts

/// OpenAI chat completions. DeepSeek uses the same shape with `label == deepSeekLabel`
/// and must not upload image bytes.
public struct OpenAIModel: ModelPort {
    public let baseURL: URL
    public let label: String
    let client: ModelHTTPClient

    public init(
        client: ModelHTTPClient = .shared,
        baseURL: URL = openAIBaseURL,
        label: String = openAILabel
    ) {
        self.client = client
        self.baseURL = baseURL
        self.label = label
    }

    public func streamChat(_ request: NormalizedChatRequest) -> AsyncThrowingStream<NormalizedChunk, Error> {
        let state = OpenAIStreamState()
        let label = self.label
        let parts: HTTPRequestParts
        if let url = endpoint(baseURL, "/chat/completions") {
            parts = HTTPRequestParts(
                url: url,
                headers: [
                    ("Content-Type", "application/json"),
                    ("Authorization", "Bearer \(request.apiKey)"),
                ],
                body: ModelJSON.data(openAIPayload(request, supportsImages: label != deepSeekLabel))
            )
        } else {
            return failedStream(label: label)
        }
        return streamSSE(
            client: client,
            apiKey: request.apiKey,
            providerWire: label == deepSeekLabel ? ProviderId.deepseek.rawValue : ProviderId.openai.rawValue,
            label: label,
            parts: parts,
            onLine: { line in
                guard let data = sseData(line) else { return [] }
                if data.isEmpty { return [] }
                if data == "[DONE]" {
                    state.done = true
                    return []
                }
                if state.done { return [] }
                let delta = try openAIDelta(data, label: label)
                guard let delta else { return [] }
                state.accumulate(delta)
                return textChunks(from: delta)
            },
            onFinish: {
                try state.toolChunks()
            }
        )
    }
}

/// Same sentence as `packages/kernel/src/model/openai.ts` and Android `IMAGE_OMITTED_SUFFIX`.
let imageOmittedSuffix = "\n[Image content omitted because this model provider does not accept image input.]"

func textChunks(from delta: WireValue) -> [NormalizedChunk] {
    guard let fields = delta.objectFields else { return [] }
    var chunks: [NormalizedChunk] = []
    if let reasoning = fields.string("reasoning_content"), !reasoning.isEmpty {
        chunks.append(.thinking(reasoning))
    }
    if let content = fields.string("content"), !content.isEmpty {
        chunks.append(.text(content))
    }
    return chunks
}

func openAIPayload(_ request: NormalizedChatRequest, supportsImages: Bool) -> WireValue {
    var fields: [(String, WireValue)] = [
        ("model", .string(request.model.model)),
        ("stream", .bool(true)),
    ]
    if let maxTokens = request.maxOutputTokens, maxTokens != 0 {
        fields.append(("max_tokens", .int(Int64(maxTokens))))
    }
    fields.append(("messages", .array(request.messages.map {
        openAIMessage($0, supportsImages: supportsImages)
    })))
    fields.append(("tools", .array(request.tools.map(openAITool))))
    return .object(fields)
}

func openAIMessage(_ message: ChatMessage, supportsImages: Bool) -> WireValue {
    if message.role == .tool {
        return .object([
            ("role", .string("tool")),
            ("tool_call_id", message.toolCallId.map(WireValue.string) ?? .null),
            ("content", .string(message.content)),
        ])
    }
    if message.role == .assistant {
        var fields: [(String, WireValue)] = [
            ("role", .string("assistant")),
            ("content", assistantContent(message)),
        ]
        if let thinking = message.thinking, !thinking.isEmpty {
            fields.append(("reasoning_content", .string(thinking)))
        }
        if let calls = message.toolCalls, !calls.isEmpty {
            fields.append(("tool_calls", .array(calls.map(openAIToolCall))))
        }
        return .object(fields)
    }
    let pictures = message.images ?? []
    let uploadable = allowedImages(message.images)
    if message.role == .user && !uploadable.isEmpty && supportsImages {
        var content: [WireValue] = [
            .object([
                ("type", .string("text")),
                ("text", .string(message.content)),
            ])
        ]
        for image in uploadable {
            content.append(.object([
                ("type", .string("image_url")),
                ("image_url", .object([
                    ("url", .string("data:\(image.mimeType);base64,\(image.data)")),
                ])),
            ]))
        }
        return .object([
            ("role", .string("user")),
            ("content", .array(content)),
        ])
    }
    let suffix = !pictures.isEmpty && !supportsImages ? imageOmittedSuffix : ""
    return .object([
        ("role", .string(message.role.rawValue)),
        ("content", .string(message.content + suffix)),
    ])
}

private func assistantContent(_ message: ChatMessage) -> WireValue {
    if !message.content.isEmpty { return .string(message.content) }
    if let calls = message.toolCalls, !calls.isEmpty { return .null }
    return .string("")
}

private func openAIToolCall(_ call: ToolCall) -> WireValue {
    .object([
        ("id", .string(call.id)),
        ("type", .string("function")),
        ("function", .object([
            ("name", .string(call.name)),
            ("arguments", .string(ModelJSON.encode(.object(
                call.arguments.map { ($0.key, ModelJSON.value($0.value)) }
            )))),
        ])),
    ])
}

private func openAITool(_ tool: ToolDefinition) -> WireValue {
    .object([
        ("type", .string("function")),
        ("function", .object([
            ("name", .string(tool.name)),
            ("description", .string(tool.description)),
            ("parameters", ModelJSON.value(.object(tool.inputSchema))),
        ])),
    ])
}

private struct AccumulatedTool {
    var id = ""
    var name = ""
    var args = ""
}

private final class OpenAIStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var order: [Int] = []
    private var tools: [Int: AccumulatedTool] = [:]
    var done = false

    func accumulate(_ delta: WireValue) {
        guard let calls = delta.field("tool_calls")?.array else { return }
        lock.lock()
        defer { lock.unlock() }
        for element in calls {
            guard let fields = element.objectFields, let index = fields.value("index")?.int else { continue }
            if tools[index] == nil {
                order.append(index)
                tools[index] = AccumulatedTool()
            }
            if let id = fields.string("id"), !id.isEmpty {
                tools[index]?.id = id
            }
            guard let function = fields.value("function")?.objectFields else { continue }
            if let name = function.string("name"), !name.isEmpty {
                tools[index]?.name += name
            }
            if let arguments = function.string("arguments"), !arguments.isEmpty {
                tools[index]?.args += arguments
            }
        }
    }

    func toolChunks() throws -> [NormalizedChunk] {
        lock.lock()
        let calls = order.compactMap { tools[$0] }
        lock.unlock()
        var chunks: [NormalizedChunk] = []
        for call in calls {
            let id = call.id.isEmpty ? UUID().uuidString.lowercased() : call.id
            chunks.append(.toolCall(
                id: id,
                name: call.name,
                arguments: try ModelJSON.argumentObject(call.args)
            ))
        }
        return chunks
    }
}

private func openAIDelta(_ data: String, label: String) throws -> WireValue? {
    let root: WireValue
    do {
        root = try ModelJSON.parse(data)
    } catch {
        throw NuumError(code: KernelErrorCode.model, message: "\(label) returned a malformed stream event")
    }
    guard let choices = root.field("choices")?.array, let first = choices.first else { return nil }
    return first.field("delta")
}

private func failedStream(label: String) -> AsyncThrowingStream<NormalizedChunk, Error> {
    AsyncThrowingStream { continuation in
        continuation.finish(throwing: NuumError(
            code: KernelErrorCode.model,
            message: "\(label) connection failed"
        ))
    }
}

private extension Array where Element == (String, WireValue) {
    func string(_ name: String) -> String? {
        first { $0.0 == name }?.1.string
    }

    func value(_ name: String) -> WireValue? {
        first { $0.0 == name }?.1
    }
}
