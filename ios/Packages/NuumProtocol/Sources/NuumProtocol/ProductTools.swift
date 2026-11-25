import Foundation

public enum DelegatedToolNames {
    public static let createTask = "CreateTask"
    public static let claimTask = "ClaimTask"
    public static let readTask = "ReadTask"
    public static let sendMessage = "SendMessage"
    public static let updateState = "update_state"
    public static let createAgent = "CreateAgent"
    public static let updateAgent = "UpdateAgent"
    public static let sendToAgent = "SendToAgent"
    public static let readAgentTranscript = "ReadAgentTranscript"
    public static let checkAgent = "CheckAgent"
    public static let stopAgent = "StopAgent"
    public static let postToWork = "PostToWork"
    public static let handoffTask = "HandoffTask"
    public static let readWorkTimeline = "ReadWorkTimeline"
    public static let runWorkCli = "RunWorkCLI"
    public static let delegateWork = "DelegateWork"
}

private let outboundFieldTypes: [(String, [String])] = [
    ("content", ["text"]),
    ("images", ["text"]),
    ("path", ["attachment"]),
    ("caption", ["attachment"]),
    ("widget", ["widget"]),
    ("props", ["widget"]),
]

/// Field misuse is reported before `OutboundMessage` parsing so a `path` on
/// `type:text` is not silently dropped. The sentences are returned to the model unchanged.
public func parseSendMessage(_ args: JSONValue) throws -> OutboundMessage {
    let object = try JSONObject(args)
    var issues: [ProtocolIssue] = []
    if let type = object.value("type")?.stringValue {
        for (field, allowed) in outboundFieldTypes where object.contains(field) && !allowed.contains(type) {
            let list = allowed.joined(separator: " or ")
            issues.append(ProtocolIssue(
                path: [field],
                message: "\(field) is only valid with type:\(list), not type:\(type) — it would be silently dropped. Nothing was sent. Re-send as separate SendMessage calls, one per type."
            ))
        }
        if type == "text", contentMissing(object), !object.contains("text") {
            issues.append(ProtocolIssue(path: ["content"], message: "content is required when type is text. Nothing was sent."))
        }
        if type == "attachment", pathMissing(object) {
            issues.append(ProtocolIssue(path: ["path"], message: "path is required when type is attachment. Nothing was sent."))
        }
        if type == "widget", !object.contains("widget") {
            issues.append(ProtocolIssue(
                path: ["widget"],
                message: "widget is required when type is widget: an object with prompt and options. Nothing was sent."
            ))
        }
    }
    if !issues.isEmpty { throw ProtocolParseException(issues) }
    return try parseOutboundMessage(normalizeOutbound(object).json)
}

private func contentMissing(_ args: JSONObject) -> Bool {
    guard let content = args.value("content") else { return true }
    if case .string(let value) = content { return value.isEmpty }
    return false
}

private func pathMissing(_ args: JSONObject) -> Bool {
    guard let path = args.value("path") else { return true }
    if case .string(let value) = path { return value.isEmpty }
    return false
}

public enum UpdateStateParams: WireRepresentable, Sendable, Equatable {
    case profile(action: String, name: String?, description: String?, tags: [String]?)
    case memory(action: String, fact: String, tier: String)

    public init(protocolJSON: JSONValue) throws {
        self = try parseUpdateState(protocolJSON)
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        switch self {
        case .profile(let action, let name, let description, let tags):
            fields.add("target", "profile")
            fields.add("action", action)
            fields.addIfPresent("name", name)
            fields.addIfPresent("description", description)
            if let tags { fields.add("tags", .array(tags.map(JSONValue.string))) }
        case .memory(let action, let fact, let tier):
            fields.add("target", "memory")
            fields.add("action", action)
            fields.add("fact", fact)
            fields.add("tier", tier)
        }
        return fields.json
    }
}

public func parseUpdateState(_ args: JSONValue) throws -> UpdateStateParams {
    let object = try JSONObject(args)
    let target = try object.optionalString("target")
    switch target {
    case "profile":
        let action = try object.optionalString("action")
        if action != "set" {
            throw ProtocolParseException(["action"], "Invalid enum value. Expected 'set', received '\(action ?? "null")'")
        }
        let tags = try object.optionalStringArray("tags").map { try normalizeAgentTags($0) }
        return .profile(
            action: "set",
            name: try object.optionalString("name"),
            description: try object.optionalString("description"),
            tags: tags
        )
    case "memory":
        guard let action = try object.optionalString("action") else {
            throw ProtocolParseException(["action"], "Required")
        }
        if action != "write" && action != "forget" {
            throw ProtocolParseException(["action"], "Invalid enum value. Expected 'write' | 'forget', received '\(action)'")
        }
        guard let fact = try object.optionalString("fact") else {
            throw ProtocolParseException(["fact"], "Required")
        }
        let tier: String
        if object.contains("tier") {
            guard let value = try object.optionalString("tier") else {
                throw ProtocolParseException(["tier"], "Expected a string")
            }
            tier = value
        } else {
            tier = "log"
        }
        if !["profile", "log", "note"].contains(tier) {
            throw ProtocolParseException(["tier"], "Invalid enum value. Expected 'profile' | 'log' | 'note', received '\(tier)'")
        }
        return .memory(action: action, fact: fact, tier: tier)
    case nil:
        throw ProtocolParseException(["target"], "Required")
    default:
        throw ProtocolParseException(["target"], "Invalid enum value. Expected 'profile' | 'memory', received '\(target ?? "")'")
    }
}

public struct CreateAgentParams: WireRepresentable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var firstMessage: String?

    public init(name: String, description: String, firstMessage: String? = nil) {
        self.name = name
        self.description = description
        self.firstMessage = firstMessage
    }

    public init(protocolJSON: JSONValue) throws { self = try parseCreateAgent(protocolJSON) }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("name", name)
        fields.add("description", description)
        fields.addIfPresent("first_message", firstMessage)
        return fields.json
    }
}

public func parseCreateAgent(_ args: JSONValue) throws -> CreateAgentParams {
    let object = try JSONObject(args)
    guard let name = try object.optionalString("name") else { throw ProtocolParseException(["name"], "Required") }
    guard let description = try object.optionalString("description") else { throw ProtocolParseException(["description"], "Required") }
    return CreateAgentParams(name: name, description: description, firstMessage: try object.optionalString("first_message"))
}

public struct UpdateAgentParams: WireRepresentable, Sendable, Equatable {
    public var agentId: String
    public var name: String?
    public var description: String?
    public var tags: [String]?

    public init(agentId: String, name: String? = nil, description: String? = nil, tags: [String]? = nil) {
        self.agentId = agentId
        self.name = name
        self.description = description
        self.tags = tags
    }

    public init(protocolJSON: JSONValue) throws { self = try parseUpdateAgent(protocolJSON) }
    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("agent_id", agentId)
        fields.addIfPresent("name", name)
        fields.addIfPresent("description", description)
        if let tags { fields.add("tags", .array(tags.map(JSONValue.string))) }
        return fields.json
    }
}

public func parseUpdateAgent(_ args: JSONValue) throws -> UpdateAgentParams {
    let object = try JSONObject(args)
    guard let agentId = try object.optionalString("agent_id") else { throw ProtocolParseException(["agent_id"], "Required") }
    return UpdateAgentParams(
        agentId: agentId,
        name: try object.optionalString("name"),
        description: try object.optionalString("description"),
        tags: try object.optionalStringArray("tags").map { try normalizeAgentTags($0) }
    )
}

public struct SendToAgentParams: WireRepresentable, Sendable, Equatable {
    public var agentId: String
    public var message: String
    public var priority: Bool?

    public init(agentId: String, message: String, priority: Bool? = nil) {
        self.agentId = agentId
        self.message = message
        self.priority = priority
    }

    public init(protocolJSON: JSONValue) throws { self = try parseSendToAgent(protocolJSON) }
    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("agent_id", agentId)
        fields.add("message", message)
        fields.addIfPresent("priority", priority)
        return fields.json
    }
}

public func parseSendToAgent(_ args: JSONValue) throws -> SendToAgentParams {
    let object = try JSONObject(args)
    guard let agentId = try object.optionalString("agent_id") else { throw ProtocolParseException(["agent_id"], "Required") }
    guard let message = try object.optionalString("message") else { throw ProtocolParseException(["message"], "Required") }
    return SendToAgentParams(agentId: agentId, message: message, priority: try object.optionalBool("priority"))
}

public struct ReadAgentTranscriptParams: WireRepresentable, Sendable, Equatable {
    public var agentId: String
    public var limit: Int?

    public init(agentId: String, limit: Int? = nil) {
        self.agentId = agentId
        self.limit = limit
    }

    public init(protocolJSON: JSONValue) throws { self = try parseReadAgentTranscript(protocolJSON) }
    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("agent_id", agentId)
        fields.addIfPresent("limit", limit)
        return fields.json
    }
}

public func parseReadAgentTranscript(_ args: JSONValue) throws -> ReadAgentTranscriptParams {
    let object = try JSONObject(args)
    let limit = try object.optionalInt("limit")
    if let limit, limit <= 0 || limit > 200 {
        throw ProtocolParseException(["limit"], "Number must be greater than 0 and at most 200")
    }
    guard let agentId = try object.optionalString("agent_id") else { throw ProtocolParseException(["agent_id"], "Required") }
    return ReadAgentTranscriptParams(agentId: agentId, limit: limit)
}

public struct CheckAgentParams: WireRepresentable, Sendable, Equatable {
    public var agentId: String
    public init(agentId: String) { self.agentId = agentId }
    public init(protocolJSON: JSONValue) throws { self = try parseCheckAgent(protocolJSON) }
    public var protocolJSON: JSONValue { var fields = JSONFieldList(); fields.add("agent_id", agentId); return fields.json }
}

public func parseCheckAgent(_ args: JSONValue) throws -> CheckAgentParams {
    let object = try JSONObject(args)
    guard let agentId = try object.optionalString("agent_id") else { throw ProtocolParseException(["agent_id"], "Required") }
    return CheckAgentParams(agentId: agentId)
}

public struct StopAgentParams: WireRepresentable, Sendable, Equatable {
    public var agentId: String
    public init(agentId: String) { self.agentId = agentId }
    public init(protocolJSON: JSONValue) throws { self = try parseStopAgent(protocolJSON) }
    public var protocolJSON: JSONValue { var fields = JSONFieldList(); fields.add("agent_id", agentId); return fields.json }
}

public func parseStopAgent(_ args: JSONValue) throws -> StopAgentParams {
    let object = try JSONObject(args)
    guard let agentId = try object.optionalString("agent_id") else { throw ProtocolParseException(["agent_id"], "Required") }
    return StopAgentParams(agentId: agentId)
}

public struct CreateTaskParams: WireRepresentable, Sendable, Equatable {
    public var title: String
    public var description: String
    public var acceptanceCriteria: [String]
    public var assigneeIds: [String]

    public init(title: String, description: String = "", acceptanceCriteria: [String] = [], assigneeIds: [String] = []) {
        self.title = title
        self.description = description
        self.acceptanceCriteria = acceptanceCriteria
        self.assigneeIds = assigneeIds
    }

    public init(protocolJSON: JSONValue) throws { self = try parseCreateTask(protocolJSON) }
    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("title", title)
        fields.add("description", description)
        fields.add("acceptanceCriteria", .array(acceptanceCriteria.map(JSONValue.string)))
        fields.add("assigneeIds", .array(assigneeIds.map(JSONValue.string)))
        return fields.json
    }
}

public func parseCreateTask(_ args: JSONValue) throws -> CreateTaskParams {
    let object = try JSONObject(args)
    guard let title = try object.optionalString("title")?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        throw ProtocolParseException(["title"], "Required")
    }
    if title.isEmpty { throw ProtocolParseException(["title"], "String must contain at least 1 character(s)") }
    return CreateTaskParams(
        title: title,
        description: try object.optionalString("description") ?? "",
        acceptanceCriteria: try object.optionalStringArray("acceptanceCriteria") ?? [],
        assigneeIds: try object.optionalStringArray("assigneeIds") ?? []
    )
}

public struct ClaimTaskParams: WireRepresentable, Sendable, Equatable {
    public var taskId: String
    public var expectedRevision: Int
    public init(taskId: String, expectedRevision: Int) {
        self.taskId = taskId
        self.expectedRevision = expectedRevision
    }
    public init(protocolJSON: JSONValue) throws { self = try parseClaimTask(protocolJSON) }
    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("taskId", taskId)
        fields.add("expectedRevision", expectedRevision)
        return fields.json
    }
}

public func parseClaimTask(_ args: JSONValue) throws -> ClaimTaskParams {
    let object = try JSONObject(args)
    guard let taskId = try object.optionalString("taskId"), !taskId.isEmpty else {
        throw ProtocolParseException(["taskId"], "Required")
    }
    guard let revision = try object.optionalInt("expectedRevision") else {
        throw ProtocolParseException(["expectedRevision"], "Required")
    }
    if revision <= 0 { throw ProtocolParseException(["expectedRevision"], "Number must be greater than 0") }
    return ClaimTaskParams(taskId: taskId, expectedRevision: revision)
}

public struct ReadTaskParams: WireRepresentable, Sendable, Equatable {
    public var taskId: String?
    public init(taskId: String? = nil) { self.taskId = taskId }
    public init(protocolJSON: JSONValue) throws { self = try parseReadTask(protocolJSON) }
    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.addIfPresent("taskId", taskId)
        return fields.json
    }
}

public func parseReadTask(_ args: JSONValue) throws -> ReadTaskParams {
    ReadTaskParams(taskId: try JSONObject(args).optionalString("taskId"))
}

public struct PostToWorkParams: WireRepresentable, Sendable, Equatable {
    public var message: String
    public init(message: String) { self.message = message }
    public init(protocolJSON: JSONValue) throws { self = try parsePostToWork(protocolJSON) }
    public var protocolJSON: JSONValue { var fields = JSONFieldList(); fields.add("message", message); return fields.json }
}

public func parsePostToWork(_ args: JSONValue) throws -> PostToWorkParams {
    let object = try JSONObject(args)
    guard let message = try object.optionalString("message"), !message.isEmpty else {
        throw ProtocolParseException(["message"], "Required")
    }
    return PostToWorkParams(message: message)
}

public struct HandoffDeliverable: WireRepresentable, Sendable, Equatable {
    public var name: String
    public var uri: String
    public var mimeType: String?

    public init(name: String, uri: String, mimeType: String? = nil) {
        self.name = name
        self.uri = uri
        self.mimeType = mimeType
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        name = try object.string("name")
        uri = try object.string("uri")
        mimeType = try object.optionalString("mime_type")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("name", name)
        fields.add("uri", uri)
        fields.addIfPresent("mime_type", mimeType)
        return fields.json
    }
}

public struct HandoffTaskParams: WireRepresentable, Sendable, Equatable {
    public var summary: String
    public var status: String
    public var blockerReason: String?
    public var deliverables: [HandoffDeliverable]

    public init(summary: String, status: String, blockerReason: String? = nil, deliverables: [HandoffDeliverable] = []) {
        self.summary = summary
        self.status = status
        self.blockerReason = blockerReason
        self.deliverables = deliverables
    }

    public init(protocolJSON: JSONValue) throws { self = try parseHandoffTask(protocolJSON) }
    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("summary", summary)
        fields.add("status", status)
        fields.addIfPresent("blocker_reason", blockerReason)
        fields.add("deliverables", .array(deliverables.map(\.protocolJSON)))
        return fields.json
    }
}

public func parseHandoffTask(_ args: JSONValue) throws -> HandoffTaskParams {
    let object = try JSONObject(args)
    guard let summary = try object.optionalString("summary"), !summary.isEmpty else {
        throw ProtocolParseException(["summary"], "Required")
    }
    guard let status = try object.optionalString("status") else { throw ProtocolParseException(["status"], "Required") }
    if !["review", "blocked", "done"].contains(status) {
        throw ProtocolParseException(["status"], "Invalid enum value. Expected 'review' | 'blocked' | 'done', received '\(status)'")
    }
    let blocker = try object.optionalString("blocker_reason")
    if let blocker, blocker.isEmpty {
        throw ProtocolParseException(["blocker_reason"], "String must contain at least 1 character(s)")
    }
    return HandoffTaskParams(summary: summary, status: status, blockerReason: blocker, deliverables: try parseDeliverables(object))
}

public struct WorkCardAction: WireRepresentable, Sendable, Equatable {
    public var status: String
    public var blockerReason: String?
    public var expectedRevision: Int?
    public var deliverables: [HandoffDeliverable]

    public init(status: String, blockerReason: String? = nil, expectedRevision: Int? = nil, deliverables: [HandoffDeliverable] = []) {
        self.status = status
        self.blockerReason = blockerReason
        self.expectedRevision = expectedRevision
        self.deliverables = deliverables
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        status = try object.string("status")
        blockerReason = try object.optionalString("blocker_reason")
        expectedRevision = try object.optionalInt("expectedRevision")
        deliverables = try parseDeliverables(object)
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("status", status)
        fields.addIfPresent("blocker_reason", blockerReason)
        fields.addIfPresent("expectedRevision", expectedRevision)
        fields.add("deliverables", .array(deliverables.map(\.protocolJSON)))
        return fields.json
    }
}

public struct WorkSendMessageParams: WireRepresentable, Sendable, Equatable {
    public var type: String
    public var content: String
    public var cardAction: WorkCardAction?

    public init(type: String, content: String, cardAction: WorkCardAction? = nil) {
        self.type = type
        self.content = content
        self.cardAction = cardAction
    }

    public init(protocolJSON: JSONValue) throws { self = try parseWorkSendMessage(protocolJSON) }
    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("type", type)
        fields.add("content", content)
        if let cardAction { fields.add("cardAction", cardAction.protocolJSON) }
        return fields.json
    }
}

public func parseWorkSendMessage(_ args: JSONValue) throws -> WorkSendMessageParams {
    let object = try JSONObject(args)
    try rejectUnknown(object, ["type", "content", "cardAction"])
    if try object.optionalString("type") != "text" {
        throw ProtocolParseException(["type"], "Invalid literal value, expected \"text\"")
    }
    guard let content = try object.optionalString("content")?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        throw ProtocolParseException(["content"], "Required")
    }
    if content.isEmpty { throw ProtocolParseException(["content"], "String must contain at least 1 character(s)") }
    let card: WorkCardAction?
    if let raw = object.value("cardAction") {
        let cardObject = try JSONObject(raw, path: ["cardAction"])
        try rejectUnknown(cardObject, ["status", "blocker_reason", "expectedRevision", "deliverables"], prefix: "cardAction")
        guard let status = try cardObject.optionalString("status") else {
            throw ProtocolParseException(["cardAction", "status"], "Required")
        }
        if status != "review" && status != "blocked" {
            throw ProtocolParseException(["cardAction", "status"], "Invalid enum value. Expected 'review' | 'blocked', received '\(status)'")
        }
        let blocker = try cardObject.optionalString("blocker_reason")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let blocker, blocker.isEmpty {
            throw ProtocolParseException(["cardAction", "blocker_reason"], "String must contain at least 1 character(s)")
        }
        let revision = try cardObject.optionalInt("expectedRevision")
        if let revision, revision <= 0 {
            throw ProtocolParseException(["cardAction", "expectedRevision"], "Number must be greater than 0")
        }
        card = WorkCardAction(status: status, blockerReason: blocker, expectedRevision: revision, deliverables: try parseDeliverables(cardObject, path: "cardAction.deliverables"))
    } else {
        card = nil
    }
    return WorkSendMessageParams(type: "text", content: content, cardAction: card)
}

public struct ReadWorkTimelineParams: WireRepresentable, Sendable, Equatable {
    public var beforeSeq: Int?
    public var afterSeq: Int?
    public var limit: Int

    public init(beforeSeq: Int? = nil, afterSeq: Int? = nil, limit: Int = 30) {
        self.beforeSeq = beforeSeq
        self.afterSeq = afterSeq
        self.limit = limit
    }

    public init(protocolJSON: JSONValue) throws { self = try parseReadWorkTimeline(protocolJSON) }
    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.addIfPresent("beforeSeq", beforeSeq)
        fields.addIfPresent("afterSeq", afterSeq)
        fields.add("limit", limit)
        return fields.json
    }
}

public func parseReadWorkTimeline(_ args: JSONValue) throws -> ReadWorkTimelineParams {
    let object = try JSONObject(args)
    let before = try object.optionalInt("beforeSeq")
    if let before, before <= 0 { throw ProtocolParseException(["beforeSeq"], "Number must be greater than 0") }
    let after = try object.optionalInt("afterSeq")
    if let after, after < 0 { throw ProtocolParseException(["afterSeq"], "Number must be greater than or equal to 0") }
    let limit: Int
    if object.contains("limit") {
        guard let value = try object.optionalInt("limit") else { throw ProtocolParseException(["limit"], "Expected an integer") }
        limit = value
    } else {
        limit = 30
    }
    if limit <= 0 || limit > 100 { throw ProtocolParseException(["limit"], "Number must be greater than 0 and at most 100") }
    return ReadWorkTimelineParams(beforeSeq: before, afterSeq: after, limit: limit)
}

public struct RunWorkCliParams: WireRepresentable, Sendable, Equatable {
    public var capabilityId: String
    public var args: [String]
    public init(capabilityId: String, args: [String] = []) {
        self.capabilityId = capabilityId
        self.args = args
    }
    public init(protocolJSON: JSONValue) throws { self = try parseRunWorkCli(protocolJSON) }
    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("capability_id", capabilityId)
        fields.add("args", .array(args.map(JSONValue.string)))
        return fields.json
    }
}

public func parseRunWorkCli(_ args: JSONValue) throws -> RunWorkCliParams {
    let object = try JSONObject(args)
    guard let id = try object.optionalString("capability_id"), !id.isEmpty else {
        throw ProtocolParseException(["capability_id"], "Required")
    }
    return RunWorkCliParams(capabilityId: id, args: try object.optionalStringArray("args") ?? [])
}

public struct DelegateWorkParams: WireRepresentable, Sendable, Equatable {
    public var agentId: String
    public var instruction: String
    public var taskId: String?

    public init(agentId: String, instruction: String, taskId: String? = nil) {
        self.agentId = agentId
        self.instruction = instruction
        self.taskId = taskId
    }

    public init(protocolJSON: JSONValue) throws { self = try parseDelegateWork(protocolJSON) }
    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("agent_id", agentId)
        fields.add("instruction", instruction)
        fields.addIfPresent("task_id", taskId)
        return fields.json
    }
}

public func parseDelegateWork(_ args: JSONValue) throws -> DelegateWorkParams {
    let object = try JSONObject(args)
    guard let agentId = try object.optionalString("agent_id"), !agentId.isEmpty else {
        throw ProtocolParseException(["agent_id"], "Required")
    }
    guard let instruction = try object.optionalString("instruction"), !instruction.isEmpty else {
        throw ProtocolParseException(["instruction"], "Required")
    }
    let taskId = try object.optionalString("task_id")
    if let taskId, taskId.isEmpty {
        throw ProtocolParseException(["task_id"], "String must contain at least 1 character(s)")
    }
    return DelegateWorkParams(agentId: agentId, instruction: instruction, taskId: taskId)
}

private func parseDeliverables(_ args: JSONObject, path: String = "deliverables") throws -> [HandoffDeliverable] {
    let key = path.split(separator: ".").last.map(String.init) ?? path
    guard let raw = args.value(key), !raw.isNull else { return [] }
    guard case .array(let values) = raw else { throw ProtocolParseException(path, "Expected an array") }
    return try values.enumerated().map { index, element in
        let object = try JSONObject(element, path: path.split(separator: ".").map(String.init) + [String(index)])
        guard let name = try object.optionalString("name"), !name.isEmpty else {
            throw ProtocolParseException("\(path).\(index).name", "Required")
        }
        guard let uri = try object.optionalString("uri"), !uri.isEmpty else {
            throw ProtocolParseException("\(path).\(index).uri", "Required")
        }
        return HandoffDeliverable(name: name, uri: uri, mimeType: try object.optionalString("mime_type"))
    }
}

private func rejectUnknown(_ args: JSONObject, _ allowed: Set<String>, prefix: String = "") throws {
    if let unknown = args.pairs.map(\.0).first(where: { !allowed.contains($0) }) {
        let path = [prefix, unknown].filter { !$0.isEmpty }
        throw ProtocolParseException(path, "Unrecognized key")
    }
}

private func schemaObject(_ pairs: (String, JSONValue)...) -> JSONValue { .object(pairs) }
private func schemaString(_ value: String) -> JSONValue { .string(value) }
private func schemaStrings(_ values: String...) -> JSONValue { .array(values.map(JSONValue.string)) }

private var agentIDSchema: JSONValue {
    schemaObject(
        ("type", schemaString("string")),
        ("description", schemaString("The agent's id, as listed in your teammate directory."))
    )
}

public let delegatedToolDefinitions: [ToolDefinition] = [
    ToolDefinition(
        name: DelegatedToolNames.createTask,
        description: "Create a ready card in this NunuBar. You become its permanent owner. Include acceptance criteria and optional workers; DelegateWork starts their independent card sessions.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("title")),
            ("properties", schemaObject(
                ("title", schemaObject(("type", schemaString("string")))),
                ("description", schemaObject(("type", schemaString("string")))),
                ("acceptanceCriteria", schemaObject(("type", schemaString("array")), ("items", schemaObject(("type", schemaString("string")))))),
                ("assigneeIds", schemaObject(("type", schemaString("array")), ("items", schemaObject(("type", schemaString("string"))))))
            ))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.claimTask,
        description: "Atomically join or start a ready card as a worker, without changing its creator-owner. Blocked cards require human confirmation. ReadTask supplies expectedRevision.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("taskId", "expectedRevision")),
            ("properties", schemaObject(
                ("taskId", schemaObject(("type", schemaString("string")))),
                ("expectedRevision", schemaObject(("type", schemaString("integer"))))
            ))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.readTask,
        description: "Read a task's current state and revision, or list this NunuBar's tasks when taskId is omitted.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("properties", schemaObject(("taskId", schemaObject(("type", schemaString("string"))))))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.sendMessage,
        description: "Say something to the user in their chat with you. This is your only voice: the user only ever sees the content of SendMessage calls, and plain text you write is an invisible scratchpad — so a reply counts only once it is inside SendMessage, including short casual ones like \"Got it\". Ending a turn where someone is waiting on you without SendMessage means they see silence. Post updates as you work, not just at the end: a real result, decision, or blocker is worth a message; routine mechanics and retries are not. Results count as delivered only inside SendMessage — an opening acknowledgement never discharges a result you owe (ack != delivery), so the last thing you do on a turn that produced one is SendMessage it. Use {\"type\":\"text\",\"content\":\"...\"} for normal messages; when a reply has two or three beats, send them as a short run of separate SendMessage calls, like quick texts, rather than one welded paragraph. Attach images to the text they belong with via images (they render inside the same bubble); use type:attachment only when the file IS the whole message. Use {\"type\":\"widget\",\"widget\":{...}} to ask a question with selectable options — sparingly: by default decide and proceed, reserving widgets for consequential or destructive go/no-go calls, true ambiguity you cannot resolve yourself, or something only the user knows. Every option must be a real, verified choice; a user's selection arrives as their next message. Sending a widget ends your turn — make it your last action.",
        inputSchema: sendMessageSchema(),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.updateState,
        description: "Change your own persistent state. target=profile rewrites your own name, tags or description; target=memory records or forgets a durable fact. Fields you do not pass are left alone.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("target", "action")),
            ("properties", schemaObject(
                ("target", schemaObject(("type", schemaString("string")), ("enum", schemaStrings("profile", "memory")))),
                ("action", schemaObject(("type", schemaString("string")), ("enum", schemaStrings("set", "write", "forget")))),
                ("name", schemaObject(("type", schemaString("string")), ("description", schemaString("For target=profile.")))),
                ("description", schemaObject(("type", schemaString("string")), ("description", schemaString("For target=profile.")))),
                ("tags", schemaObject(("type", schemaString("array")), ("items", schemaObject(("type", schemaString("string")))), ("description", schemaString("For target=profile: replaces all tags; pass [] to clear.")))),
                ("fact", schemaObject(("type", schemaString("string")), ("description", schemaString("For target=memory: one self-contained fact.")))),
                ("tier", schemaObject(("type", schemaString("string")), ("enum", schemaStrings("profile", "log", "note")), ("description", schemaString("For target=memory: profile for standing facts, log for dated ones."))))
            ))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.createAgent,
        description: "Create a new teammate agent with its own chat, persona, and memory. It appears in the user's sidebar immediately. You have no tool to delete an agent, so only create one when it is genuinely useful and long-lived — for a one-off task, just do the task yourself.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("name", "description")),
            ("properties", schemaObject(
                ("name", schemaObject(("type", schemaString("string")), ("description", schemaString("Short, human, and distinct from existing teammates.")))),
                ("description", schemaObject(("type", schemaString("string")), ("description", schemaString("What this teammate is for.")))),
                ("first_message", schemaObject(("type", schemaString("string")), ("description", schemaString("Optional first instruction to wake it with."))))
            ))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.updateAgent,
        description: "Rename another agent or rewrite its description. Fields you do not pass are left alone.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("agent_id")),
            ("properties", schemaObject(
                ("agent_id", agentIDSchema),
                ("name", schemaObject(("type", schemaString("string")))),
                ("description", schemaObject(("type", schemaString("string")))),
                ("tags", schemaObject(("type", schemaString("array")), ("items", schemaObject(("type", schemaString("string"))))))
            ))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.sendToAgent,
        description: "Send a message to another agent. Delivery is asynchronous and fire-and-forget, like texting: it returns immediately, and a later reply from that teammate wakes you here — never wait or poll for one in this turn. Write the message self-contained (they cannot see your chat) and lead with the point. Waking a teammate is a real side effect: message an agent only when it serves the user's goal, never relay the user's private or unfiltered words verbatim (paraphrase the actionable point instead), and messaging several agents about the same effort is a fan-out you only make when the user explicitly asked for it. Use priority to interrupt what the recipient is currently doing — for STOP / supersede / time-critical instructions, not for ordinary replies.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("agent_id", "message")),
            ("properties", schemaObject(
                ("agent_id", agentIDSchema),
                ("message", schemaObject(("type", schemaString("string")), ("description", schemaString("Self-contained: the other agent cannot see your chat.")))),
                ("priority", schemaObject(("type", schemaString("boolean")), ("description", schemaString("Interrupt its current work instead of queueing. For STOP / supersede / time-critical instructions only."))))
            ))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.readAgentTranscript,
        description: "Read the tail of another agent's chat, to see what it has been up to or what it answered. Read-only.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("agent_id")),
            ("properties", schemaObject(
                ("agent_id", agentIDSchema),
                ("limit", schemaObject(("type", schemaString("number")), ("description", schemaString("How many entries, newest last."))))
            ))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.checkAgent,
        description: "Check what another agent is doing right now, without messaging or waking it. Returns whether it is running or idle, which run it is in (your user's private chat or a Work), its recent tool activity, and the path to its transcript you can read for the full play-by-play. Read-only. Use it when a teammate you are working with seems stuck, slow, or you need its current state before deciding next steps; to actually reach it, use SendToAgent.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("agent_id")),
            ("properties", schemaObject(("agent_id", agentIDSchema))),
            ("description", schemaString("Pass the agent's id from your teammate directory — not a name."))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.stopAgent,
        description: "Stop what another agent is currently doing. Anything queued for it is dropped too.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("agent_id")),
            ("properties", schemaObject(("agent_id", agentIDSchema)))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.postToWork,
        description: "Post a progress update to the current Work shared room.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("message")),
            ("properties", schemaObject(("message", schemaObject(("type", schemaString("string"))))))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.handoffTask,
        description: "Hand the current Work task back for review, report it blocked, or—when you are the coordinator—mark a reviewed task done. This also posts the summary in the shared room.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("summary", "status")),
            ("properties", schemaObject(
                ("summary", schemaObject(("type", schemaString("string")))),
                ("status", schemaObject(("type", schemaString("string")), ("enum", schemaStrings("review", "blocked", "done")))),
                ("blocker_reason", schemaObject(("type", schemaString("string")))),
                ("deliverables", schemaObject(
                    ("type", schemaString("array")),
                    ("items", schemaObject(
                        ("type", schemaString("object")),
                        ("required", schemaStrings("name", "uri")),
                        ("properties", schemaObject(
                            ("name", schemaObject(("type", schemaString("string")))),
                            ("uri", schemaObject(("type", schemaString("string")))),
                            ("mime_type", schemaObject(("type", schemaString("string"))))
                        ))
                    ))
                ))
            ))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.readWorkTimeline,
        description: "Read the latest entries from the current Work timeline.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("properties", schemaObject(
                ("limit", schemaObject(("type", schemaString("number")))),
                ("beforeSeq", schemaObject(("type", schemaString("integer")))),
                ("afterSeq", schemaObject(("type", schemaString("integer"))))
            ))
        ),
        mutating: false
    ),
    ToolDefinition(
        name: DelegatedToolNames.runWorkCli,
        description: "Run a CLI capability explicitly installed in the current Work. No shell expansion is performed.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("capability_id")),
            ("properties", schemaObject(
                ("capability_id", schemaObject(("type", schemaString("string")))),
                ("args", schemaObject(("type", schemaString("array")), ("items", schemaObject(("type", schemaString("string"))))))
            ))
        ),
        mutating: true
    ),
    ToolDefinition(
        name: DelegatedToolNames.delegateWork,
        description: "Dispatch a room member as a worker. Specify task_id (defaults to the current card); room-only discussion must use @ in SendMessage. Workers use independent card sessions: the creator stays owner and worker results return there. Blocked cards require human confirmation before further dispatch.",
        inputSchema: schemaObject(
            ("type", schemaString("object")),
            ("required", schemaStrings("agent_id", "instruction")),
            ("properties", schemaObject(
                ("agent_id", agentIDSchema),
                ("instruction", schemaObject(("type", schemaString("string")))),
                ("task_id", schemaObject(("type", schemaString("string"))))
            ))
        ),
        mutating: false
    ),
]

private func sendMessageSchema() -> JSONValue {
    schemaObject(
        ("type", schemaString("object")),
        ("required", schemaStrings("type")),
        ("properties", schemaObject(
            ("type", schemaObject(("type", schemaString("string")), ("enum", schemaStrings("text", "attachment", "widget")))),
            ("content", schemaObject(("type", schemaString("string")), ("description", schemaString("Required when type=text: the message to show the user.")))),
            ("images", schemaObject(
                ("type", schemaString("array")),
                ("description", schemaString("Optional, only with type=text: images that belong with this message; they render inside the same bubble below the text.")),
                ("items", schemaObject(
                    ("type", schemaString("object")),
                    ("required", schemaStrings("path")),
                    ("properties", schemaObject(
                        ("path", schemaObject(("type", schemaString("string")), ("description", schemaString("Absolute local path to the image file.")))),
                        ("alt", schemaObject(("type", schemaString("string")), ("description", schemaString("Short description shown on hover and as fullscreen caption."))))
                    ))
                ))
            )),
            ("path", schemaObject(("type", schemaString("string")), ("description", schemaString("Required when type=attachment: absolute path to the file.")))),
            ("caption", schemaObject(("type", schemaString("string")), ("description", schemaString("For type=attachment: one line about it.")))),
            ("widget", schemaObject(
                ("type", schemaString("object")),
                ("description", schemaString("Required when type=widget: a question with selectable options. The chosen option's value is sent back to you as the user's reply.")),
                ("required", schemaStrings("prompt", "options")),
                ("properties", schemaObject(
                    ("prompt", schemaObject(("type", schemaString("string")), ("description", schemaString("The question, phrased as a natural conversational sentence — never a menu instruction.")))),
                    ("helpText", schemaObject(("type", schemaString("string")), ("description", schemaString("Optional short help shown under the question.")))),
                    ("options", schemaObject(
                        ("type", schemaString("array")),
                        ("minItems", .int(1)),
                        ("maxItems", .int(6)),
                        ("items", schemaObject(
                            ("type", schemaString("object")),
                            ("required", schemaStrings("label")),
                            ("properties", schemaObject(
                                ("label", schemaObject(("type", schemaString("string")), ("description", schemaString("Short option label shown on the card.")))),
                                ("value", schemaObject(("type", schemaString("string")), ("description", schemaString("Text sent back when picked; defaults to the label. Write it like a reply the user would actually send.")))),
                                ("description", schemaObject(("type", schemaString("string")), ("description", schemaString("Optional one-line explanation under the label.")))),
                                ("style", schemaObject(("type", schemaString("string")), ("enum", schemaStrings("default", "primary", "danger")), ("description", schemaString("danger marks a destructive choice; primary marks the recommended one."))))
                            ))
                        ))
                    )),
                    ("allowCustom", schemaObject(("type", schemaString("boolean")), ("description", schemaString("Let the user type a free-text answer instead of picking an option."))))
                ))
            ))
        ))
    )
}
