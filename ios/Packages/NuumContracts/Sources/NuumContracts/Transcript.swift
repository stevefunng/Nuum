public struct UserAttachment: Sendable, Equatable {
    public var name: String
    public var path: String
    public var mimeType: String
    public var size: Int
    public var text: String?

    public init(name: String, path: String, mimeType: String, size: Int, text: String? = nil) {
        self.name = name
        self.path = path
        self.mimeType = mimeType
        self.size = size
        self.text = text
    }
}

public struct WidgetOption: Sendable, Equatable {
    public var label: String
    public var value: String?
    public var description: String?
    public var style: String?

    public init(label: String, value: String? = nil, description: String? = nil, style: String? = nil) {
        self.label = label
        self.value = value
        self.description = description
        self.style = style
    }
}

public struct WidgetPayload: Sendable, Equatable {
    public var prompt: String
    public var options: [WidgetOption]
    public var helpText: String?
    public var allowCustom: Bool

    public init(prompt: String, options: [WidgetOption], helpText: String? = nil, allowCustom: Bool = false) {
        self.prompt = prompt
        self.options = options
        self.helpText = helpText
        self.allowCustom = allowCustom
    }
}

public struct OutboundImage: Sendable, Equatable {
    public var path: String
    public var alt: String?

    public init(path: String, alt: String? = nil) {
        self.path = path
        self.alt = alt
    }
}

public struct TextOutbound: Sendable, Equatable {
    public var content: String
    public var images: [OutboundImage]

    public init(content: String, images: [OutboundImage] = []) {
        self.content = content
        self.images = images
    }
}

public struct AttachmentOutbound: Sendable, Equatable {
    public var path: String
    public var caption: String?

    public init(path: String, caption: String? = nil) {
        self.path = path
        self.caption = caption
    }
}

public struct LegacyWidgetOutbound: Sendable, Equatable {
    public var widget: String
    public var props: [String: JSONValue]

    public init(widget: String, props: [String: JSONValue] = [:]) {
        self.widget = widget
        self.props = props
    }
}

public enum OutboundMessage: Sendable, Equatable {
    case text(TextOutbound)
    case attachment(AttachmentOutbound)
    case widget(WidgetPayload)
    case legacyWidget(LegacyWidgetOutbound)
}

public struct ThinkingPart: Sendable, Equatable {
    public var text: String
    public init(text: String) { self.text = text }
}

public struct TextPart: Sendable, Equatable {
    public var text: String
    public init(text: String) { self.text = text }
}

public struct ToolCallPart: Sendable, Equatable {
    public var id: String
    public var name: String
    public var arguments: [String: JSONValue]
    public var executionId: String?

    public init(id: String, name: String, arguments: [String: JSONValue], executionId: String? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.executionId = executionId
    }
}

public enum AssistantPart: Sendable, Equatable {
    case thinking(ThinkingPart)
    case text(TextPart)
    case toolCall(ToolCallPart)
}

public struct AgentWakeSource: Sendable, Equatable {
    public var fromId: String
    public var fromName: String
    public var priority: Bool

    public init(fromId: String, fromName: String, priority: Bool = false) {
        self.fromId = fromId
        self.fromName = fromName
        self.priority = priority
    }
}

public struct WorkWakeSource: Sendable, Equatable {
    public var workId: String
    public var workName: String
    public var bridgeId: String
    public var taskId: String?

    public init(workId: String, workName: String, bridgeId: String, taskId: String? = nil) {
        self.workId = workId
        self.workName = workName
        self.bridgeId = bridgeId
        self.taskId = taskId
    }
}

public struct RoutineWakeSource: Sendable, Equatable {
    public var routineId: String
    public var routineName: String

    public init(routineId: String, routineName: String) {
        self.routineId = routineId
        self.routineName = routineName
    }
}

public enum WakeSource: Sendable, Equatable {
    case agent(AgentWakeSource)
    case work(WorkWakeSource)
    case routine(RoutineWakeSource)
}

public struct UserTranscript: Sendable, Equatable {
    public var id: String
    public var seq: Int
    public var createdAt: Int64
    public var text: String
    public var attachments: [UserAttachment]
    public var widgetAnswerTo: String?

    public init(
        id: String,
        seq: Int,
        createdAt: Int64,
        text: String,
        attachments: [UserAttachment] = [],
        widgetAnswerTo: String? = nil
    ) {
        self.id = id
        self.seq = seq
        self.createdAt = createdAt
        self.text = text
        self.attachments = attachments
        self.widgetAnswerTo = widgetAnswerTo
    }
}

public struct WakeTranscript: Sendable, Equatable {
    public var id: String
    public var seq: Int
    public var createdAt: Int64
    public var source: WakeSource
    public var text: String
    public var hops: Int

    public init(id: String, seq: Int, createdAt: Int64, source: WakeSource, text: String, hops: Int = 0) {
        self.id = id
        self.seq = seq
        self.createdAt = createdAt
        self.source = source
        self.text = text
        self.hops = hops
    }
}

public struct AssistantTranscript: Sendable, Equatable {
    public var id: String
    public var seq: Int
    public var createdAt: Int64
    public var parts: [AssistantPart]

    public init(id: String, seq: Int, createdAt: Int64, parts: [AssistantPart]) {
        self.id = id
        self.seq = seq
        self.createdAt = createdAt
        self.parts = parts
    }
}

public struct ToolTranscript: Sendable, Equatable {
    public var id: String
    public var seq: Int
    public var createdAt: Int64
    public var toolCallId: String
    public var name: String
    public var content: String
    public var assistantId: String?
    public var ok: Bool?
    public var spillPath: String?

    public init(
        id: String,
        seq: Int,
        createdAt: Int64,
        toolCallId: String,
        name: String,
        content: String,
        assistantId: String? = nil,
        ok: Bool? = nil,
        spillPath: String? = nil
    ) {
        self.id = id
        self.seq = seq
        self.createdAt = createdAt
        self.toolCallId = toolCallId
        self.name = name
        self.content = content
        self.assistantId = assistantId
        self.ok = ok
        self.spillPath = spillPath
    }
}

public struct MessageTranscript: Sendable, Equatable {
    public var id: String
    public var seq: Int
    public var createdAt: Int64
    public var payload: OutboundMessage
    public var assistantId: String?
    public var toolCallId: String?

    public init(
        id: String,
        seq: Int,
        createdAt: Int64,
        payload: OutboundMessage,
        assistantId: String? = nil,
        toolCallId: String? = nil
    ) {
        self.id = id
        self.seq = seq
        self.createdAt = createdAt
        self.payload = payload
        self.assistantId = assistantId
        self.toolCallId = toolCallId
    }
}

public struct CompactTranscript: Sendable, Equatable {
    public var id: String
    public var seq: Int
    public var createdAt: Int64
    public var epoch: Int
    public var throughSeq: Int
    public var tailFromSeq: Int
    public var summary: String

    public init(
        id: String,
        seq: Int,
        createdAt: Int64,
        epoch: Int,
        throughSeq: Int,
        tailFromSeq: Int,
        summary: String
    ) {
        self.id = id
        self.seq = seq
        self.createdAt = createdAt
        self.epoch = epoch
        self.throughSeq = throughSeq
        self.tailFromSeq = tailFromSeq
        self.summary = summary
    }
}

public struct ProfileTranscript: Sendable, Equatable {
    public var id: String
    public var seq: Int
    public var createdAt: Int64
    public var name: String?
    public var description: String?
    public var tags: [String]?

    public init(
        id: String,
        seq: Int,
        createdAt: Int64,
        name: String? = nil,
        description: String? = nil,
        tags: [String]? = nil
    ) {
        self.id = id
        self.seq = seq
        self.createdAt = createdAt
        self.name = name
        self.description = description
        self.tags = tags
    }
}

public enum TranscriptEvent: Sendable, Equatable {
    case user(UserTranscript)
    case wake(WakeTranscript)
    case assistant(AssistantTranscript)
    case tool(ToolTranscript)
    case message(MessageTranscript)
    case compact(CompactTranscript)
    case profile(ProfileTranscript)

    public var type: String {
        switch self {
        case .user: "user"
        case .wake: "wake"
        case .assistant: "assistant"
        case .tool: "tool"
        case .message: "message"
        case .compact: "compact"
        case .profile: "profile"
        }
    }

    public var id: String {
        switch self {
        case .user(let event): event.id
        case .wake(let event): event.id
        case .assistant(let event): event.id
        case .tool(let event): event.id
        case .message(let event): event.id
        case .compact(let event): event.id
        case .profile(let event): event.id
        }
    }

    public var seq: Int {
        switch self {
        case .user(let event): event.seq
        case .wake(let event): event.seq
        case .assistant(let event): event.seq
        case .tool(let event): event.seq
        case .message(let event): event.seq
        case .compact(let event): event.seq
        case .profile(let event): event.seq
        }
    }

    public var createdAt: Int64 {
        switch self {
        case .user(let event): event.createdAt
        case .wake(let event): event.createdAt
        case .assistant(let event): event.createdAt
        case .tool(let event): event.createdAt
        case .message(let event): event.createdAt
        case .compact(let event): event.createdAt
        case .profile(let event): event.createdAt
        }
    }
}

public struct TranscriptQuery: Sendable, Equatable {
    public var id: String
    public var beforeSeq: Int?
    public var limit: Int?

    public init(id: String, beforeSeq: Int? = nil, limit: Int? = nil) {
        self.id = id
        self.beforeSeq = beforeSeq
        self.limit = limit
    }
}

public struct TranscriptPage: Sendable, Equatable {
    public var id: String
    public var entries: [TranscriptEvent]
    public var nextBeforeSeq: Int?

    public init(id: String, entries: [TranscriptEvent], nextBeforeSeq: Int? = nil) {
        self.id = id
        self.entries = entries
        self.nextBeforeSeq = nextBeforeSeq
    }
}

public struct LiveAssistant: Sendable, Equatable {
    public var messageId: String
    public var parts: [AssistantPart]

    public init(messageId: String, parts: [AssistantPart]) {
        self.messageId = messageId
        self.parts = parts
    }
}

public struct ToolView: Sendable, Equatable {
    public var id: String
    public var name: String
    public var arguments: [String: JSONValue]
    public var output: String?
    public var status: String

    public init(id: String, name: String, arguments: [String: JSONValue], output: String? = nil, status: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.output = output
        self.status = status
    }
}

public struct UserBlock: Sendable, Equatable {
    public var id: String
    public var text: String
    public var attachments: [UserAttachment]
    public var widgetAnswerTo: String?

    public init(id: String, text: String, attachments: [UserAttachment] = [], widgetAnswerTo: String? = nil) {
        self.id = id
        self.text = text
        self.attachments = attachments
        self.widgetAnswerTo = widgetAnswerTo
    }
}

public struct AssistantBlock: Sendable, Equatable {
    public var id: String
    public var thinking: String
    public var tools: [ToolView]
    public var live: Bool

    public init(id: String, thinking: String, tools: [ToolView], live: Bool = false) {
        self.id = id
        self.thinking = thinking
        self.tools = tools
        self.live = live
    }
}

public struct MessageBlock: Sendable, Equatable {
    public var id: String
    public var payload: OutboundMessage

    public init(id: String, payload: OutboundMessage) {
        self.id = id
        self.payload = payload
    }
}

public struct PeerBlock: Sendable, Equatable {
    public var id: String
    public var direction: String
    public var agentId: String
    public var agentName: String
    public var text: String
    public var priority: Bool

    public init(id: String, direction: String, agentId: String, agentName: String, text: String, priority: Bool) {
        self.id = id
        self.direction = direction
        self.agentId = agentId
        self.agentName = agentName
        self.text = text
        self.priority = priority
    }
}

public struct NoticeBlock: Sendable, Equatable {
    public var id: String
    public var kind: String
    public var text: String

    public init(id: String, kind: String, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

public enum ViewBlock: Sendable, Equatable {
    case user(UserBlock)
    case assistant(AssistantBlock)
    case message(MessageBlock)
    case peer(PeerBlock)
    case notice(NoticeBlock)
}
