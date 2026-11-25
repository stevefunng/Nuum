import Foundation

public struct NormalizedChatRequest: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var model: ModelRef
    public var messages: [ChatMessage]
    public var tools: [ToolDefinition]
    public var apiKey: String
    public var maxOutputTokens: Int?

    public init(
        model: ModelRef,
        messages: [ChatMessage],
        tools: [ToolDefinition],
        apiKey: String,
        maxOutputTokens: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.apiKey = apiKey
        self.maxOutputTokens = maxOutputTokens
    }

    public var description: String {
        "NormalizedChatRequest(model: \(model.provider.rawValue)/\(model.model), messages: \(messages.count), tools: \(tools.count), apiKey: <redacted>)"
    }

    public var debugDescription: String { description }
}

public enum NormalizedChunk: Sendable, Equatable {
    case text(String)
    case thinking(String)
    case toolCall(id: String, name: String, arguments: [String: JSONValue])
}

public struct ToolRoots: Sendable, Equatable {
    public var home: String
    public var project: String?
    public var scratch: String
    public var terminals: String
    public var denied: [String]
    public var readOnly: [String]

    public init(
        home: String,
        project: String?,
        scratch: String,
        terminals: String,
        denied: [String],
        readOnly: [String] = []
    ) {
        self.home = home
        self.project = project
        self.scratch = scratch
        self.terminals = terminals
        self.denied = denied
        self.readOnly = readOnly
    }
}

public struct TurnStartParams: Sendable, Equatable {
    public var runId: String
    public var messages: [ChatMessage]
    public var model: ModelRef
    public var roots: ToolRoots
    public var toolPermission: ToolPermission
    public var localToolNames: [String]
    public var secrets: Secrets
    public var contextWindow: Int?
    public var approvals: [ToolApproval]
    public var refused: [ToolApproval]
    public var delegatedTools: [ToolDefinition]
    public var voiceToolNames: [String]

    public init(
        runId: String,
        messages: [ChatMessage],
        model: ModelRef,
        roots: ToolRoots,
        toolPermission: ToolPermission,
        localToolNames: [String],
        secrets: Secrets,
        contextWindow: Int? = nil,
        approvals: [ToolApproval] = [],
        refused: [ToolApproval] = [],
        delegatedTools: [ToolDefinition] = [],
        voiceToolNames: [String] = ["SendMessage"]
    ) {
        self.runId = runId
        self.messages = messages
        self.model = model
        self.roots = roots
        self.toolPermission = toolPermission
        self.localToolNames = localToolNames
        self.secrets = secrets
        self.contextWindow = contextWindow
        self.approvals = approvals
        self.refused = refused
        self.delegatedTools = delegatedTools
        self.voiceToolNames = voiceToolNames
    }
}

public struct TurnToolDecision: Sendable, Equatable {
    public var runId: String
    public var toolCallId: String
    public var resolution: ToolResolution

    public init(runId: String, toolCallId: String, resolution: ToolResolution) {
        self.runId = runId
        self.toolCallId = toolCallId
        self.resolution = resolution
    }
}

public struct TurnToolResult: Sendable, Equatable {
    public var runId: String
    public var toolCallId: String
    public var ok: Bool
    public var output: String
    public var endTurn: Bool

    public init(runId: String, toolCallId: String, ok: Bool, output: String, endTurn: Bool = false) {
        self.runId = runId
        self.toolCallId = toolCallId
        self.ok = ok
        self.output = output
        self.endTurn = endTurn
    }
}

public struct TurnContextResult: Sendable, Equatable {
    public var runId: String
    public var requestId: String
    public var messages: [ChatMessage]?
    public var error: String?

    public init(runId: String, requestId: String, messages: [ChatMessage]? = nil, error: String? = nil) {
        self.runId = runId
        self.requestId = requestId
        self.messages = messages
        self.error = error
    }
}

public struct SummarizeRunParams: Sendable, Equatable {
    public var runId: String
    public var systemPrompt: String
    public var messages: [ChatMessage]
    public var model: ModelRef
    public var secrets: Secrets
    public var timeoutMs: Int64?
    public var maxOutputTokens: Int?

    public init(
        runId: String,
        systemPrompt: String,
        messages: [ChatMessage],
        model: ModelRef,
        secrets: Secrets,
        timeoutMs: Int64? = nil,
        maxOutputTokens: Int? = nil
    ) {
        self.runId = runId
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.model = model
        self.secrets = secrets
        self.timeoutMs = timeoutMs
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct SummarizeRunResult: Sendable, Equatable {
    public var text: String
    public init(text: String) { self.text = text }
}

public enum KernelEvents {
    public static let context = "turn.context"
    public static let delta = "turn.delta"
    public static let toolPending = "turn.tool.pending"
    public static let toolStarted = "turn.tool.started"
    public static let toolDelegate = "turn.tool.delegate"
    public static let toolCompleted = "turn.tool.completed"
    public static let error = "turn.error"
    public static let ended = "turn.ended"

    public static let all: Set<String> = [
        context, delta, toolPending, toolStarted, toolDelegate, toolCompleted, error, ended,
    ]
}

public struct KernelContextEvent: Sendable, Equatable {
    public var runId: String
    public var requestId: String
    public var usedTokens: Int

    public init(runId: String, requestId: String, usedTokens: Int) {
        self.runId = runId
        self.requestId = requestId
        self.usedTokens = usedTokens
    }
}

public struct KernelDeltaEvent: Sendable, Equatable {
    public var runId: String
    public var messageId: String
    public var delta: String
    public var part: MessagePart

    public init(runId: String, messageId: String, delta: String, part: MessagePart = .text) {
        self.runId = runId
        self.messageId = messageId
        self.delta = delta
        self.part = part
    }
}

public struct KernelToolPendingEvent: Sendable, Equatable {
    public var runId: String
    public var toolCallId: String
    public var toolName: String
    public var arguments: [String: JSONValue]
    public var mutating: Bool
    public var action: LocalToolAction
    public var target: String
    public var justification: String?
    public var allowAlways: Bool?
    public var details: String?

    public init(
        runId: String,
        toolCallId: String,
        toolName: String,
        arguments: [String: JSONValue],
        mutating: Bool,
        action: LocalToolAction,
        target: String,
        justification: String? = nil,
        allowAlways: Bool? = nil,
        details: String? = nil
    ) {
        self.runId = runId
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.arguments = arguments
        self.mutating = mutating
        self.action = action
        self.target = target
        self.justification = justification
        self.allowAlways = allowAlways
        self.details = details
    }
}

public struct KernelToolStartedEvent: Sendable, Equatable {
    public var runId: String
    public var toolCallId: String
    public var toolName: String
    public var arguments: [String: JSONValue]

    public init(runId: String, toolCallId: String, toolName: String, arguments: [String: JSONValue]) {
        self.runId = runId
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.arguments = arguments
    }
}

public struct KernelToolDelegateEvent: Sendable, Equatable {
    public var runId: String
    public var toolCallId: String
    public var toolName: String
    public var arguments: [String: JSONValue]

    public init(runId: String, toolCallId: String, toolName: String, arguments: [String: JSONValue]) {
        self.runId = runId
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.arguments = arguments
    }
}

public struct KernelToolCompletedEvent: Sendable, Equatable {
    public var runId: String
    public var toolCallId: String
    public var toolName: String
    public var ok: Bool
    public var output: String

    public init(runId: String, toolCallId: String, toolName: String, ok: Bool, output: String) {
        self.runId = runId
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.ok = ok
        self.output = output
    }
}

public struct KernelErrorEvent: Sendable, Equatable {
    public var runId: String
    public var code: Int
    public var message: String

    public init(runId: String, code: Int, message: String) {
        self.runId = runId
        self.code = code
        self.message = message
    }
}

public struct KernelEndedEvent: Sendable, Equatable {
    public var runId: String
    public var status: RunEndStatus

    public init(runId: String, status: RunEndStatus) {
        self.runId = runId
        self.status = status
    }
}

public enum KernelEvent: Sendable, Equatable {
    case context(KernelContextEvent)
    case delta(KernelDeltaEvent)
    case toolPending(KernelToolPendingEvent)
    case toolStarted(KernelToolStartedEvent)
    case toolDelegate(KernelToolDelegateEvent)
    case toolCompleted(KernelToolCompletedEvent)
    case error(KernelErrorEvent)
    case ended(KernelEndedEvent)

    public var name: String {
        switch self {
        case .context: KernelEvents.context
        case .delta: KernelEvents.delta
        case .toolPending: KernelEvents.toolPending
        case .toolStarted: KernelEvents.toolStarted
        case .toolDelegate: KernelEvents.toolDelegate
        case .toolCompleted: KernelEvents.toolCompleted
        case .error: KernelEvents.error
        case .ended: KernelEvents.ended
        }
    }
}

public enum PermissionDecision: String, Sendable, Equatable, CaseIterable {
    case allow
    case ask
    case deny
}

public struct PermissionVerdict: Sendable, Equatable {
    public var decision: PermissionDecision
    public var target: String
    public var reason: String?

    public init(decision: PermissionDecision, target: String, reason: String? = nil) {
        self.decision = decision
        self.target = target
        self.reason = reason
    }
}

public struct ToolExecutionResult: Sendable, Equatable {
    public var ok: Bool
    public var output: String
    public var endTurn: Bool
    public var images: [ModelImage]

    public init(ok: Bool, output: String, endTurn: Bool = false, images: [ModelImage] = []) {
        self.ok = ok
        self.output = output
        self.endTurn = endTurn
        self.images = images
    }
}

public struct AgentCreateParams: Sendable, Equatable {
    public var name: String?
    public var description: String?
    public var tags: [String]?
    public var avatarColor: String?
    public var avatarShape: String?
    public var avatarMaterial: String?
    public var model: ModelRef?
    public var workspace: WorkspaceSettings?

    public init(
        name: String? = nil,
        description: String? = nil,
        tags: [String]? = nil,
        avatarColor: String? = nil,
        avatarShape: String? = nil,
        avatarMaterial: String? = nil,
        model: ModelRef? = nil,
        workspace: WorkspaceSettings? = nil
    ) {
        self.name = name
        self.description = description
        self.tags = tags
        self.avatarColor = avatarColor
        self.avatarShape = avatarShape
        self.avatarMaterial = avatarMaterial
        self.model = model
        self.workspace = workspace
    }
}

public struct AgentUpdateParams: Sendable, Equatable {
    public var id: String
    public var name: String?
    public var description: String?
    public var tags: [String]?
    public var avatarColor: String?
    public var avatarShape: String?
    public var avatarMaterial: String?
    public var model: ModelRef?
    public var workspace: WorkspaceSettings?
    public var execution: ExecutionPreferences?
    public var hiddenFromSidebar: Bool?

    public init(
        id: String,
        name: String? = nil,
        description: String? = nil,
        tags: [String]? = nil,
        avatarColor: String? = nil,
        avatarShape: String? = nil,
        avatarMaterial: String? = nil,
        model: ModelRef? = nil,
        workspace: WorkspaceSettings? = nil,
        execution: ExecutionPreferences? = nil,
        hiddenFromSidebar: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.avatarColor = avatarColor
        self.avatarShape = avatarShape
        self.avatarMaterial = avatarMaterial
        self.model = model
        self.workspace = workspace
        self.execution = execution
        self.hiddenFromSidebar = hiddenFromSidebar
    }
}

public struct AgentSendParams: Sendable, Equatable {
    public var id: String
    public var content: String
    public var attachments: [AttachmentUpload]

    public init(id: String, content: String, attachments: [AttachmentUpload] = []) {
        self.id = id
        self.content = content
        self.attachments = attachments
    }
}

public struct AgentAnswerWidgetParams: Sendable, Equatable {
    public var id: String
    public var messageId: String
    public var value: String

    public init(id: String, messageId: String, value: String) {
        self.id = id
        self.messageId = messageId
        self.value = value
    }
}

public struct SendResult: Sendable, Equatable {
    public var runId: String
    public var queued: Bool

    public init(runId: String, queued: Bool) {
        self.runId = runId
        self.queued = queued
    }
}

public struct PickedFile: Sendable, Equatable {
    public var name: String
    public var mimeType: String
    public var bytes: Data

    public init(name: String, mimeType: String, bytes: Data) {
        self.name = name
        self.mimeType = mimeType
        self.bytes = bytes
    }
}
