import Foundation

public struct OutboundImage: WireRepresentable, Sendable, Equatable {
    public var path: String
    public var alt: String?

    public init(path: String, alt: String? = nil) {
        self.path = path
        self.alt = alt
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        path = try object.string("path")
        alt = try object.optionalString("alt")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("path", path)
        fields.addIfPresent("alt", alt)
        return fields.json
    }
}

public enum WidgetOptionStyle: String, Sendable, Equatable, Codable, CaseIterable {
    case `default`
    case primary
    case danger
}

public struct WidgetOption: WireRepresentable, Sendable, Equatable {
    public var label: String
    public var value: String?
    public var description: String?
    public var style: WidgetOptionStyle?

    public init(label: String, value: String? = nil, description: String? = nil, style: WidgetOptionStyle? = nil) {
        self.label = label
        self.value = value
        self.description = description
        self.style = style
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON, path: ["widget", "options"])
        label = try object.string("label")
        value = try object.optionalString("value")
        description = try object.optionalString("description")
        style = try object.optionalEnumeration("style", as: WidgetOptionStyle.self)
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("label", label)
        fields.addIfPresent("value", value)
        fields.addIfPresent("description", description)
        if let style { fields.add("style", style.rawValue) }
        return fields.json
    }
}

public struct WidgetPayload: WireRepresentable, Sendable, Equatable {
    public var prompt: String
    public var helpText: String?
    public var options: [WidgetOption]
    public var allowCustom: Bool?

    public init(prompt: String, options: [WidgetOption], helpText: String? = nil, allowCustom: Bool? = nil) {
        self.prompt = prompt
        self.options = options
        self.helpText = helpText
        self.allowCustom = allowCustom
    }

    public init(protocolJSON: JSONValue) throws {
        self = try parseWidgetPayload(try JSONObject(protocolJSON))
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("prompt", prompt)
        fields.addIfPresent("helpText", helpText)
        fields.add("options", .array(options.map(\.protocolJSON)))
        fields.addIfPresent("allowCustom", allowCustom)
        return fields.json
    }
}

public enum OutboundMessage: WireRepresentable, Sendable, Equatable {
    case text(content: String, images: [OutboundImage]?)
    case attachment(path: String, caption: String?)
    case widget(WidgetPayload)
    case legacyWidget(widget: String, props: JSONValue?)

    public init(protocolJSON: JSONValue) throws {
        self = try parseOutboundMessage(protocolJSON)
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        switch self {
        case .text(let content, let images):
            fields.add("type", "text")
            fields.add("content", content)
            if let images { fields.add("images", .array(images.map(\.protocolJSON))) }
        case .attachment(let path, let caption):
            fields.add("type", "attachment")
            fields.add("path", path)
            fields.addIfPresent("caption", caption)
        case .widget(let widget):
            fields.add("type", "widget")
            fields.add("widget", widget.protocolJSON)
        case .legacyWidget(let widget, let props):
            fields.add("type", "widget")
            fields.add("widget", widget)
            if let props { fields.add("props", props) }
        }
        return fields.json
    }
}

public func parseOutboundMessage(_ raw: JSONValue) throws -> OutboundMessage {
    let object = try JSONObject(raw)
    let normalized = normalizeOutbound(object)
    switch normalized.value("type")?.stringValue {
    case "text":
        return try parseTextOutbound(normalized)
    case "attachment":
        return try parseAttachmentOutbound(normalized)
    case "widget":
        return try parseWidgetOutbound(normalized)
    default:
        throw ProtocolParseException(["type"], "type must be text, attachment, or widget. Nothing was sent.")
    }
}

/// Legacy `text` payloads and string image paths are normalized before the union runs.
func normalizeOutbound(_ raw: JSONObject) -> JSONObject {
    guard raw.value("type")?.stringValue == "text" else { return raw }
    var pairs = raw.pairs
    if let legacy = raw.value("text"), case .string = legacy, !raw.contains("content") {
        pairs.append(("content", legacy))
    }
    if case .array(let images) = raw.value("images") {
        let normalized = images.map { image -> JSONValue in
            if case .string(let path) = image { return .object([("path", .string(path))]) }
            return image
        }
        pairs.removeAll { $0.0 == "images" }
        pairs.append(("images", .array(normalized)))
    }
    return JSONObject(pairs: pairs, path: raw.path)
}

private func parseTextOutbound(_ raw: JSONObject) throws -> OutboundMessage {
    guard let content = raw.value("content")?.stringValue else {
        throw ProtocolParseException(["content"], "content is required when type is text. Nothing was sent.")
    }
    let images: [OutboundImage]?
    switch raw.value("images") {
    case nil, .null?:
        images = nil
    case .array(let values)?:
        images = try values.enumerated().map { index, image in
            guard case .object = image else {
                throw ProtocolParseException(["images", String(index)], "Expected an image object")
            }
            let object = try JSONObject(image, path: ["images", String(index)])
            guard let path = object.value("path")?.stringValue else {
                throw ProtocolParseException(["images", String(index), "path"], "path is required")
            }
            return OutboundImage(path: path, alt: try object.optionalString("alt"))
        }
    default:
        throw ProtocolParseException(["images"], "Expected an array")
    }
    return .text(content: content, images: images)
}

private func parseAttachmentOutbound(_ raw: JSONObject) throws -> OutboundMessage {
    guard let path = raw.value("path")?.stringValue else {
        throw ProtocolParseException(["path"], "path is required when type is attachment. Nothing was sent.")
    }
    return .attachment(path: path, caption: try raw.optionalString("caption"))
}

private func parseWidgetOutbound(_ raw: JSONObject) throws -> OutboundMessage {
    switch raw.value("widget") {
    case .string(let widget)?:
        let props: JSONValue?
        switch raw.value("props") {
        case nil, .null?:
            props = nil
        case .object?:
            props = raw.value("props")
        default:
            throw ProtocolParseException(["props"], "Expected an object")
        }
        return .legacyWidget(widget: widget, props: props)
    case .object?:
        return .widget(try parseWidgetPayload(try raw.object("widget")))
    default:
        throw ProtocolParseException(
            ["widget"],
            "widget is required when type is widget: an object with prompt and options. Nothing was sent."
        )
    }
}

private func parseWidgetPayload(_ raw: JSONObject) throws -> WidgetPayload {
    guard let prompt = raw.value("prompt")?.stringValue, !prompt.isEmpty else {
        throw ProtocolParseException(["widget", "prompt"], "String must contain at least 1 character(s)")
    }
    guard case .array(let optionsRaw) = raw.value("options") else {
        throw ProtocolParseException(["widget", "options"], "Required")
    }
    if optionsRaw.isEmpty || optionsRaw.count > 6 {
        throw ProtocolParseException(["widget", "options"], "Array must contain between 1 and 6 element(s)")
    }
    let options = try optionsRaw.enumerated().map { index, element in
        let object = try JSONObject(element, path: ["widget", "options", String(index)])
        guard let label = object.value("label")?.stringValue, !label.isEmpty else {
            throw ProtocolParseException(["widget", "options", String(index), "label"], "String must contain at least 1 character(s)")
        }
        let style = try object.optionalEnumeration("style", as: WidgetOptionStyle.self)
        return WidgetOption(
            label: label,
            value: try object.optionalString("value"),
            description: try object.optionalString("description"),
            style: style
        )
    }
    let allowCustom: Bool?
    switch raw.value("allowCustom") {
    case nil, .null?:
        allowCustom = nil
    case .bool(let value)?:
        allowCustom = value
    default:
        throw ProtocolParseException(["widget", "allowCustom"], "Expected a boolean")
    }
    return WidgetPayload(
        prompt: prompt,
        options: options,
        helpText: try raw.optionalString("helpText"),
        allowCustom: allowCustom
    )
}

public enum AssistantPart: WireRepresentable, Sendable, Equatable {
    case thinking(text: String)
    case text(text: String)
    case toolCall(id: String, executionId: String?, name: String, arguments: JSONValue)

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        switch try object.string("type") {
        case "thinking":
            self = .thinking(text: try object.string("text"))
        case "text":
            self = .text(text: try object.string("text"))
        case "tool_call":
            self = .toolCall(
                id: try object.string("id"),
                executionId: try object.optionalString("executionId"),
                name: try object.string("name"),
                arguments: try object.require("arguments")
            )
        default:
            throw ProtocolParseException(["type"], "Invalid enum value")
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        switch self {
        case .thinking(let text):
            fields.add("type", "thinking")
            fields.add("text", text)
        case .text(let text):
            fields.add("type", "text")
            fields.add("text", text)
        case .toolCall(let id, let executionId, let name, let arguments):
            fields.add("type", "tool_call")
            fields.add("id", id)
            fields.addIfPresent("executionId", executionId)
            fields.add("name", name)
            fields.add("arguments", arguments)
        }
        return fields.json
    }
}

public enum RoomInputMode: String, Sendable, Equatable, Codable, CaseIterable {
    case background
    case continuation
}

public struct RoomInput: WireRepresentable, Sendable, Equatable {
    public var membershipRevision: Int
    public var fromSeq: Int
    public var throughSeq: Int
    public var messageIds: [String]
    public var epoch: Int?
    public var mode: RoomInputMode?

    public init(membershipRevision: Int, fromSeq: Int, throughSeq: Int, messageIds: [String], epoch: Int? = nil, mode: RoomInputMode? = nil) {
        self.membershipRevision = membershipRevision
        self.fromSeq = fromSeq
        self.throughSeq = throughSeq
        self.messageIds = messageIds
        self.epoch = epoch
        self.mode = mode
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        membershipRevision = try object.int("membershipRevision")
        fromSeq = try object.int("fromSeq")
        throughSeq = try object.int("throughSeq")
        messageIds = try object.stringArray("messageIds")
        epoch = try object.optionalInt("epoch")
        mode = try object.optionalEnumeration("mode", as: RoomInputMode.self)
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("membershipRevision", membershipRevision)
        fields.add("fromSeq", fromSeq)
        fields.add("throughSeq", throughSeq)
        fields.add("messageIds", .array(messageIds.map(JSONValue.string)))
        fields.addIfPresent("epoch", epoch)
        if let mode { fields.add("mode", mode.rawValue) }
        return fields.json
    }
}

public enum WakeSource: WireRepresentable, Sendable, Equatable {
    case agent(fromId: String, fromName: String, priority: Bool?)
    case work(workId: String, workName: String, bridgeId: String, taskId: String?, roomInput: RoomInput?)
    /// Not produced in this version. Placeholder for a later scheduled wake.
    case routine(routineId: String, routineName: String)

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        switch try object.string("kind") {
        case "agent":
            self = .agent(
                fromId: try object.string("fromId"),
                fromName: try object.string("fromName"),
                priority: try object.optionalBool("priority")
            )
        case "work":
            self = .work(
                workId: try object.string("workId"),
                workName: try object.string("workName"),
                bridgeId: try object.string("bridgeId"),
                taskId: try object.optionalString("taskId"),
                roomInput: try object.optionalObject("roomInput").map { try RoomInput(protocolJSON: $0.json) }
            )
        case "routine":
            self = .routine(routineId: try object.string("routineId"), routineName: try object.string("routineName"))
        default:
            throw ProtocolParseException(["kind"], "Invalid enum value")
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        switch self {
        case .agent(let fromId, let fromName, let priority):
            fields.add("kind", "agent")
            fields.add("fromId", fromId)
            fields.add("fromName", fromName)
            fields.addIfPresent("priority", priority)
        case .work(let workId, let workName, let bridgeId, let taskId, let roomInput):
            fields.add("kind", "work")
            fields.add("workId", workId)
            fields.add("workName", workName)
            fields.add("bridgeId", bridgeId)
            fields.addIfPresent("taskId", taskId)
            if let roomInput { fields.add("roomInput", roomInput.protocolJSON) }
        case .routine(let routineId, let routineName):
            fields.add("kind", "routine")
            fields.add("routineId", routineId)
            fields.add("routineName", routineName)
        }
        return fields.json
    }
}

public struct ProfilePatch: WireRepresentable, Sendable, Equatable {
    public var name: String?
    public var description: String?
    public var tags: [String]?

    public init(name: String? = nil, description: String? = nil, tags: [String]? = nil) {
        self.name = name
        self.description = description
        self.tags = tags
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        name = try object.optionalString("name")
        description = try object.optionalString("description")
        tags = try object.optionalStringArray("tags")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.addIfPresent("name", name)
        fields.addIfPresent("description", description)
        if let tags { fields.add("tags", .array(tags.map(JSONValue.string))) }
        return fields.json
    }
}

public struct CompactRoomInput: WireRepresentable, Sendable, Equatable {
    public var workId: String
    public var membershipRevision: Int
    public var throughSeq: Int

    public init(workId: String, membershipRevision: Int, throughSeq: Int) {
        self.workId = workId
        self.membershipRevision = membershipRevision
        self.throughSeq = throughSeq
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        workId = try object.string("workId")
        membershipRevision = try object.int("membershipRevision")
        throughSeq = try object.int("throughSeq")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("workId", workId)
        fields.add("membershipRevision", membershipRevision)
        fields.add("throughSeq", throughSeq)
        return fields.json
    }
}

public enum TranscriptEvent: WireRepresentable, Sendable, Equatable {
    case user(id: String, seq: Int, createdAt: Int64, text: String, attachments: [UserAttachment]?, widgetAnswerTo: String?)
    case wake(id: String, seq: Int, createdAt: Int64, source: WakeSource, text: String, hops: Int)
    case assistant(id: String, seq: Int, createdAt: Int64, parts: [AssistantPart])
    case tool(id: String, seq: Int, createdAt: Int64, assistantId: String?, toolCallId: String, executionId: String?, permissionTaskKey: String?, name: String, content: String, ok: Bool?, spillPath: String?)
    case message(id: String, seq: Int, createdAt: Int64, assistantId: String?, toolCallId: String?, payload: OutboundMessage)
    case compact(id: String, seq: Int, createdAt: Int64, epoch: Int, throughSeq: Int, tailFromSeq: Int, summary: String, activeRequest: String?, roomInputs: [CompactRoomInput]?)
    case profile(id: String, seq: Int, createdAt: Int64, patch: ProfilePatch)

    public var id: String {
        switch self {
        case .user(let id, _, _, _, _, _),
             .wake(let id, _, _, _, _, _),
             .assistant(let id, _, _, _),
             .tool(let id, _, _, _, _, _, _, _, _, _, _),
             .message(let id, _, _, _, _, _),
             .compact(let id, _, _, _, _, _, _, _, _),
             .profile(let id, _, _, _):
            id
        }
    }

    public var seq: Int {
        switch self {
        case .user(_, let seq, _, _, _, _),
             .wake(_, let seq, _, _, _, _),
             .assistant(_, let seq, _, _),
             .tool(_, let seq, _, _, _, _, _, _, _, _, _),
             .message(_, let seq, _, _, _, _),
             .compact(_, let seq, _, _, _, _, _, _, _),
             .profile(_, let seq, _, _):
            seq
        }
    }

    public var createdAt: Int64 {
        switch self {
        case .user(_, _, let createdAt, _, _, _),
             .wake(_, _, let createdAt, _, _, _),
             .assistant(_, _, let createdAt, _),
             .tool(_, _, let createdAt, _, _, _, _, _, _, _, _),
             .message(_, _, let createdAt, _, _, _),
             .compact(_, _, let createdAt, _, _, _, _, _, _),
             .profile(_, _, let createdAt, _):
            createdAt
        }
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        let id = try object.string("id")
        let seq = try object.int("seq")
        let createdAt = try object.int64("createdAt")
        switch try object.string("type") {
        case "user":
            self = .user(
                id: id,
                seq: seq,
                createdAt: createdAt,
                text: try object.string("text"),
                attachments: try object.optionalArray("attachments")?.map { try UserAttachment(protocolJSON: $0) },
                widgetAnswerTo: try object.optionalString("widgetAnswerTo")
            )
        case "wake":
            self = .wake(
                id: id,
                seq: seq,
                createdAt: createdAt,
                source: try WakeSource(protocolJSON: object.require("source")),
                text: try object.string("text"),
                hops: try object.optionalInt("hops") ?? 0
            )
        case "assistant":
            self = .assistant(
                id: id,
                seq: seq,
                createdAt: createdAt,
                parts: try object.array("parts").map { try AssistantPart(protocolJSON: $0) }
            )
        case "tool":
            self = .tool(
                id: id,
                seq: seq,
                createdAt: createdAt,
                assistantId: try object.optionalString("assistantId"),
                toolCallId: try object.string("toolCallId"),
                executionId: try object.optionalString("executionId"),
                permissionTaskKey: try object.optionalString("permissionTaskKey"),
                name: try object.string("name"),
                content: try object.string("content"),
                ok: try object.optionalBool("ok"),
                spillPath: try object.optionalString("spillPath")
            )
        case "message":
            self = .message(
                id: id,
                seq: seq,
                createdAt: createdAt,
                assistantId: try object.optionalString("assistantId"),
                toolCallId: try object.optionalString("toolCallId"),
                payload: try OutboundMessage(protocolJSON: object.require("payload"))
            )
        case "compact":
            self = .compact(
                id: id,
                seq: seq,
                createdAt: createdAt,
                epoch: try object.int("epoch"),
                throughSeq: try object.int("throughSeq"),
                tailFromSeq: try object.int("tailFromSeq"),
                summary: try object.string("summary"),
                activeRequest: try object.optionalString("activeRequest"),
                roomInputs: try object.optionalArray("roomInputs")?.map { try CompactRoomInput(protocolJSON: $0) }
            )
        case "profile":
            self = .profile(id: id, seq: seq, createdAt: createdAt, patch: try ProfilePatch(protocolJSON: object.require("patch")))
        default:
            throw ProtocolParseException(["type"], "Invalid enum value")
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("id", id)
        fields.add("seq", seq)
        fields.add("createdAt", createdAt)
        switch self {
        case .user(_, _, _, let text, let attachments, let widgetAnswerTo):
            fields.add("type", "user")
            fields.add("text", text)
            if let attachments { fields.add("attachments", .array(attachments.map(\.protocolJSON))) }
            fields.addIfPresent("widgetAnswerTo", widgetAnswerTo)
        case .wake(_, _, _, let source, let text, let hops):
            fields.add("type", "wake")
            fields.add("source", source.protocolJSON)
            fields.add("text", text)
            fields.add("hops", hops)
        case .assistant(_, _, _, let parts):
            fields.add("type", "assistant")
            fields.add("parts", .array(parts.map(\.protocolJSON)))
        case .tool(_, _, _, let assistantId, let toolCallId, let executionId, let permissionTaskKey, let name, let content, let ok, let spillPath):
            fields.add("type", "tool")
            fields.addIfPresent("assistantId", assistantId)
            fields.add("toolCallId", toolCallId)
            fields.addIfPresent("executionId", executionId)
            fields.addIfPresent("permissionTaskKey", permissionTaskKey)
            fields.add("name", name)
            fields.add("content", content)
            fields.addIfPresent("ok", ok)
            fields.addIfPresent("spillPath", spillPath)
        case .message(_, _, _, let assistantId, let toolCallId, let payload):
            fields.add("type", "message")
            fields.addIfPresent("assistantId", assistantId)
            fields.addIfPresent("toolCallId", toolCallId)
            fields.add("payload", payload.protocolJSON)
        case .compact(_, _, _, let epoch, let throughSeq, let tailFromSeq, let summary, let activeRequest, let roomInputs):
            fields.add("type", "compact")
            fields.add("epoch", epoch)
            fields.add("throughSeq", throughSeq)
            fields.add("tailFromSeq", tailFromSeq)
            fields.add("summary", summary)
            fields.addIfPresent("activeRequest", activeRequest)
            if let roomInputs { fields.add("roomInputs", .array(roomInputs.map(\.protocolJSON))) }
        case .profile(_, _, _, let patch):
            fields.add("type", "profile")
            fields.add("patch", patch.protocolJSON)
        }
        return fields.json
    }
}

public struct LiveAssistant: WireRepresentable, Sendable, Equatable {
    public var messageId: String
    public var parts: [AssistantPart]

    public init(messageId: String, parts: [AssistantPart]) {
        self.messageId = messageId
        self.parts = parts
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        messageId = try object.string("messageId")
        parts = try object.array("parts").map { try AssistantPart(protocolJSON: $0) }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("messageId", messageId)
        fields.add("parts", .array(parts.map(\.protocolJSON)))
        return fields.json
    }
}

public enum ToolRunStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case pending
    case ok
    case error
}

public struct ToolView: WireRepresentable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var arguments: JSONValue
    public var output: String?
    public var status: ToolRunStatus

    public init(id: String, name: String, arguments: JSONValue, status: ToolRunStatus, output: String? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.status = status
        self.output = output
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        id = try object.string("id")
        name = try object.string("name")
        arguments = try object.require("arguments")
        output = try object.optionalString("output")
        status = try object.enumeration("status", as: ToolRunStatus.self)
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("id", id)
        fields.add("name", name)
        fields.add("arguments", arguments)
        fields.addIfPresent("output", output)
        fields.add("status", status.rawValue)
        return fields.json
    }
}

public enum PeerDirection: String, Sendable, Equatable, Codable, CaseIterable {
    case inbound
    case outbound
}

public enum NoticeKind: String, Sendable, Equatable, Codable, CaseIterable {
    case wake
    case profile
    case compact
}

public enum ViewBlock: WireRepresentable, Sendable, Equatable {
    case user(id: String, text: String, attachments: [UserAttachment]?, widgetAnswerTo: String?)
    case assistant(id: String, thinking: String, tools: [ToolView], live: Bool?)
    case message(id: String, payload: OutboundMessage)
    case peer(id: String, direction: PeerDirection, agentId: String, agentName: String, text: String, priority: Bool)
    case notice(id: String, kind: NoticeKind, text: String)

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        switch try object.string("type") {
        case "user":
            self = .user(
                id: try object.string("id"),
                text: try object.string("text"),
                attachments: try object.optionalArray("attachments")?.map { try UserAttachment(protocolJSON: $0) },
                widgetAnswerTo: try object.optionalString("widgetAnswerTo")
            )
        case "assistant":
            self = .assistant(
                id: try object.string("id"),
                thinking: try object.string("thinking"),
                tools: try object.array("tools").map { try ToolView(protocolJSON: $0) },
                live: try object.optionalBool("live")
            )
        case "message":
            self = .message(id: try object.string("id"), payload: try OutboundMessage(protocolJSON: object.require("payload")))
        case "peer":
            self = .peer(
                id: try object.string("id"),
                direction: try object.enumeration("direction", as: PeerDirection.self),
                agentId: try object.string("agentId"),
                agentName: try object.string("agentName"),
                text: try object.string("text"),
                priority: try object.bool("priority")
            )
        case "notice":
            self = .notice(
                id: try object.string("id"),
                kind: try object.enumeration("kind", as: NoticeKind.self),
                text: try object.string("text")
            )
        default:
            throw ProtocolParseException(["type"], "Invalid enum value")
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        switch self {
        case .user(let id, let text, let attachments, let widgetAnswerTo):
            fields.add("type", "user")
            fields.add("id", id)
            fields.add("text", text)
            if let attachments { fields.add("attachments", .array(attachments.map(\.protocolJSON))) }
            fields.addIfPresent("widgetAnswerTo", widgetAnswerTo)
        case .assistant(let id, let thinking, let tools, let live):
            fields.add("type", "assistant")
            fields.add("id", id)
            fields.add("thinking", thinking)
            fields.add("tools", .array(tools.map(\.protocolJSON)))
            fields.addIfPresent("live", live)
        case .message(let id, let payload):
            fields.add("type", "message")
            fields.add("id", id)
            fields.add("payload", payload.protocolJSON)
        case .peer(let id, let direction, let agentId, let agentName, let text, let priority):
            fields.add("type", "peer")
            fields.add("id", id)
            fields.add("direction", direction.rawValue)
            fields.add("agentId", agentId)
            fields.add("agentName", agentName)
            fields.add("text", text)
            fields.add("priority", priority)
        case .notice(let id, let kind, let text):
            fields.add("type", "notice")
            fields.add("id", id)
            fields.add("kind", kind.rawValue)
            fields.add("text", text)
        }
        return fields.json
    }
}

public struct AgentProjection: Sendable, Equatable {
    public var blocks: [ViewBlock]
    public init(blocks: [ViewBlock]) { self.blocks = blocks }
}

public func maxTranscriptSeq(_ events: [TranscriptEvent]) -> Int {
    events.reduce(0) { max($0, $1.seq) }
}

public func eventFromChatMessage(_ message: ChatMessage) -> TranscriptEvent? {
    switch message.role {
    case .system:
        return nil
    case .user:
        return .user(id: message.id, seq: message.seq, createdAt: message.createdAt, text: message.content, attachments: nil, widgetAnswerTo: nil)
    case .tool:
        return .tool(
            id: message.id,
            seq: message.seq,
            createdAt: message.createdAt,
            assistantId: nil,
            toolCallId: message.toolCallId ?? "",
            executionId: nil,
            permissionTaskKey: nil,
            name: message.name ?? "",
            content: message.content,
            ok: nil,
            spillPath: nil
        )
    case .assistant:
        var parts: [AssistantPart] = []
        if let thinking = message.thinking, !thinking.isEmpty { parts.append(.thinking(text: thinking)) }
        if !message.content.isEmpty { parts.append(.text(text: message.content)) }
        for call in message.toolCalls ?? [] {
            parts.append(.toolCall(id: call.id, executionId: nil, name: call.name, arguments: call.arguments))
        }
        return .assistant(id: message.id, seq: message.seq, createdAt: message.createdAt, parts: parts)
    }
}

public func parseTranscriptLine(_ raw: JSONValue) throws -> TranscriptEvent? {
    let object = try JSONObject(raw)
    if object.contains("type"), !object.contains("role") {
        return try TranscriptEvent(protocolJSON: raw)
    }
    return eventFromChatMessage(try ChatMessage(protocolJSON: raw))
}

/// A bad line is skipped. One corrupt JSONL row must not wipe the transcript.
public func tryParseTranscriptLine(_ line: String) -> TranscriptEvent? {
    guard let value = try? ProtocolJSON.parse(line) else { return nil }
    return try? parseTranscriptLine(value)
}

public func appendAssistantDelta(_ parts: [AssistantPart], kind: String, delta: String) -> [AssistantPart] {
    var next = parts
    if kind == "text", case .text(let text) = next.last {
        next[next.count - 1] = .text(text: text + delta)
        return next
    }
    if kind == "thinking", case .thinking(let text) = next.last {
        next[next.count - 1] = .thinking(text: text + delta)
        return next
    }
    next.append(kind == "thinking" ? .thinking(text: delta) : .text(text: delta))
    return next
}

public func appendAssistantToolCall(_ parts: [AssistantPart], _ call: AssistantPart) -> [AssistantPart] {
    parts + [call]
}

private struct ToolResult: Equatable {
    var content: String
    var ok: Bool?
}

public func projectAgent(_ events: [TranscriptEvent], live: LiveAssistant? = nil) -> AgentProjection {
    var blocks: [ViewBlock] = []
    var results: [String: ToolResult] = [:]
    var knownCalls: Set<String> = []
    for event in events {
        if case .assistant(let id, _, _, let parts) = event {
            for part in parts {
                if case .toolCall(let callID, _, _, _) = part {
                    knownCalls.insert(callID)
                    knownCalls.insert("\(id)\u{0000}\(callID)")
                }
            }
        }
        if case .tool(_, _, _, let assistantId, let toolCallId, _, _, _, let content, let ok, _) = event {
            let result = ToolResult(content: content, ok: ok)
            if results[toolCallId] == nil { results[toolCallId] = result }
            if let assistantId { results["\(assistantId)\u{0000}\(toolCallId)"] = result }
        }
    }
    for event in events {
        switch event {
        case .user(let id, _, _, let text, let attachments, let widgetAnswerTo):
            blocks.append(.user(
                id: id,
                text: text,
                attachments: attachments.flatMap { $0.isEmpty ? nil : $0 },
                widgetAnswerTo: widgetAnswerTo.flatMap { $0.isEmpty ? nil : $0 }
            ))
        case .wake(let id, _, _, let source, let text, _):
            if case .agent(let fromId, let fromName, let priority) = source {
                blocks.append(.peer(
                    id: id,
                    direction: .inbound,
                    agentId: fromId,
                    agentName: fromName,
                    text: text,
                    priority: priority == true
                ))
            } else {
                let notice: String
                if case .work(_, let workName, _, _, _) = source {
                    notice = "Participated in room: \(workName)"
                } else {
                    notice = describeWake(event)
                }
                blocks.append(.notice(id: id, kind: .wake, text: notice))
            }
        case .message(let id, _, _, _, _, let payload):
            blocks.append(.message(id: id, payload: payload))
        case .compact(let id, _, _, _, _, _, _, _, _):
            blocks.append(.notice(
                id: id,
                kind: .compact,
                text: "Earlier messages were summarized to fit the context window. The originals are still on disk."
            ))
        case .profile(let id, _, _, let patch):
            blocks.append(.notice(id: id, kind: .profile, text: describeProfilePatch(patch)))
        case .assistant(let id, _, _, let parts):
            var causal: [String: ToolResult] = [:]
            for part in parts {
                guard case .toolCall(let callID, _, _, _) = part else { continue }
                if let result = results["\(id)\u{0000}\(callID)"] ?? results[callID] {
                    causal[callID] = result
                }
            }
            let block = assistantBlock(id, parts, causal, live: false)
            if case .assistant(_, let thinking, let tools, _) = block, !thinking.isEmpty || !tools.isEmpty {
                blocks.append(block)
            }
            blocks.append(contentsOf: outboundPeerBlocks(parts, causal))
        case .tool(let id, _, _, let assistantId, let toolCallId, _, _, let name, let content, let ok, _):
            let scoped = "\(assistantId ?? "")\u{0000}\(toolCallId)"
            if knownCalls.contains(scoped) || knownCalls.contains(toolCallId) { continue }
            blocks.append(.assistant(
                id: id,
                thinking: "",
                tools: [ToolView(
                    id: toolCallId,
                    name: name,
                    arguments: .object([]),
                    status: ok == false ? .error : .ok,
                    output: content
                )],
                live: nil
            ))
        }
    }
    if let live, !blocks.contains(where: { block in
        if case .assistant(let id, _, _, _) = block { return id == live.messageId }
        return false
    }) {
        let block = assistantBlock(live.messageId, live.parts, [:], live: true)
        if case .assistant(_, let thinking, let tools, _) = block, !thinking.isEmpty || !tools.isEmpty {
            blocks.append(block)
        }
        blocks.append(contentsOf: outboundPeerBlocks(live.parts, [:]))
    }
    return AgentProjection(blocks: blocks)
}

private func assistantBlock(_ id: String, _ parts: [AssistantPart], _ results: [String: ToolResult], live: Bool) -> ViewBlock {
    let tools = parts.compactMap { part -> ToolView? in
        guard case .toolCall(let callID, _, let name, let arguments) = part else { return nil }
        if name == "SendMessage" { return nil }
        let result = results[callID]
        if name == "SendToAgent", result != nil, result?.ok != false { return nil }
        let status: ToolRunStatus
        if result == nil {
            status = .pending
        } else if result?.ok == false {
            status = .error
        } else {
            status = .ok
        }
        return ToolView(id: callID, name: name, arguments: arguments, status: status, output: result?.content)
    }
    let thinking = parts.compactMap { part -> String? in
        if case .thinking(let text) = part { return text }
        return nil
    }.joined()
    return .assistant(id: id, thinking: thinking, tools: tools, live: live ? true : nil)
}

private func outboundPeerBlocks(_ parts: [AssistantPart], _ results: [String: ToolResult]) -> [ViewBlock] {
    parts.compactMap { part in
        guard case .toolCall(let callID, _, let name, let arguments) = part, name == "SendToAgent" else { return nil }
        guard let agentId = stringArgument(arguments, "agent_id"), let text = stringArgument(arguments, "message") else { return nil }
        guard let result = results[callID], result.ok != false else { return nil }
        return .peer(
            id: callID,
            direction: .outbound,
            agentId: agentId,
            agentName: agentNameFromDelivery(result.content) ?? agentId,
            text: text,
            priority: arguments.objectPairs?.contains { $0.0 == "priority" && $0.1 == .bool(true) } == true
        )
    }
}

private func stringArgument(_ arguments: JSONValue, _ key: String) -> String? {
    guard let pairs = arguments.objectPairs, let value = pairs.last(where: { $0.0 == key })?.1.stringValue, !value.isEmpty else {
        return nil
    }
    return value
}

private func agentNameFromDelivery(_ content: String?) -> String? {
    guard let content, !content.isEmpty else { return nil }
    let deliveryName = try? NSRegularExpression(pattern: #"^(?:Sent|Delivered) to (.+?)(?: as priority|,|\.|$)"#)
    let range = NSRange(content.startIndex..., in: content)
    guard let match = deliveryName?.firstMatch(in: content, range: range), match.numberOfRanges > 1,
          let nameRange = Range(match.range(at: 1), in: content) else { return nil }
    let name = content[nameRange].trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}

public func describeWake(_ event: TranscriptEvent) -> String {
    guard case .wake(_, _, _, let source, let text, _) = event else { return "" }
    switch source {
    case .agent(_, let fromName, let priority):
        let marker = priority == true ? " (priority)" : ""
        return "From \(fromName)\(marker): \(text)"
    case .work(_, let workName, _, let taskId, _):
        let task = taskId.map { " task \($0)" } ?? ""
        return "From Work \(workName)\(task): \(text)"
    case .routine(_, let routineName):
        return "Routine \(routineName): \(text)"
    }
}

private func describeProfilePatch(_ patch: ProfilePatch) -> String {
    var parts: [String] = []
    if let name = patch.name { parts.append("name to \"\(name)\"") }
    if patch.description != nil { parts.append("its description") }
    if patch.tags != nil { parts.append("its tags") }
    if parts.isEmpty { return "This agent changed its profile." }
    return "This agent changed \(parts.joined(separator: " and "))."
}
