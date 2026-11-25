/// Names match `HostEvents`. There is no `host.kernel.down` event.
/// Model failures use `agent.error` with `KernelErrorCode.model` or `HostErrorCode.noAPIKey`.
public enum HostEvents {
    public static let agentUpdated = "agent.updated"
    public static let agentMessageDelta = "agent.message.delta"
    public static let agentMessageCompleted = "agent.message.completed"
    public static let agentToolPending = "agent.tool.pending"
    public static let agentToolStarted = "agent.tool.started"
    public static let agentToolCompleted = "agent.tool.completed"
    public static let agentError = "agent.error"
    public static let agentEnded = "agent.ended"
    public static let workUpdated = "work.updated"
    public static let workEventAppended = "work.event.appended"
    public static let workCatalogUpdated = "work.catalog.updated"
    public static let proactiveUpdated = "proactive.updated"
    public static let settingsUpdated = "settings.updated"

    public static let all: Set<String> = [
        agentUpdated,
        agentMessageDelta,
        agentMessageCompleted,
        agentToolPending,
        agentToolStarted,
        agentToolCompleted,
        agentError,
        agentEnded,
        workUpdated,
        workEventAppended,
        workCatalogUpdated,
        proactiveUpdated,
        settingsUpdated,
    ]
}

public struct AgentMessageDeltaEvent: Sendable, Equatable {
    public var agentId: String
    public var runId: String
    public var messageId: String
    public var delta: String
    public var part: MessagePart

    public init(
        agentId: String,
        runId: String,
        messageId: String,
        delta: String,
        part: MessagePart = .text
    ) {
        self.agentId = agentId
        self.runId = runId
        self.messageId = messageId
        self.delta = delta
        self.part = part
    }
}

public struct AgentMessageCompletedEvent: Sendable, Equatable {
    public var agentId: String
    public var event: TranscriptEvent

    public init(agentId: String, event: TranscriptEvent) {
        self.agentId = agentId
        self.event = event
    }
}

public struct AgentToolPendingEvent: Sendable, Equatable {
    public var agentId: String
    public var runId: String
    public var toolCallId: String
    public var toolName: String
    public var arguments: [String: JSONValue]
    public var action: LocalToolAction
    public var target: String
    public var justification: String?
    public var allowAlways: Bool?
    public var details: String?

    public init(
        agentId: String,
        runId: String,
        toolCallId: String,
        toolName: String,
        arguments: [String: JSONValue],
        action: LocalToolAction,
        target: String,
        justification: String? = nil,
        allowAlways: Bool? = nil,
        details: String? = nil
    ) {
        self.agentId = agentId
        self.runId = runId
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.arguments = arguments
        self.action = action
        self.target = target
        self.justification = justification
        self.allowAlways = allowAlways
        self.details = details
    }
}

public struct AgentToolStartedEvent: Sendable, Equatable {
    public var agentId: String
    public var runId: String
    public var toolCallId: String
    public var toolName: String
    public var arguments: [String: JSONValue]

    public init(
        agentId: String,
        runId: String,
        toolCallId: String,
        toolName: String,
        arguments: [String: JSONValue]
    ) {
        self.agentId = agentId
        self.runId = runId
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.arguments = arguments
    }
}

public struct AgentToolCompletedEvent: Sendable, Equatable {
    public var agentId: String
    public var runId: String
    public var toolCallId: String
    public var toolName: String
    public var ok: Bool
    public var output: String

    public init(
        agentId: String,
        runId: String,
        toolCallId: String,
        toolName: String,
        ok: Bool,
        output: String
    ) {
        self.agentId = agentId
        self.runId = runId
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.ok = ok
        self.output = output
    }
}

public struct AgentErrorEvent: Sendable, Equatable {
    public var agentId: String
    public var runId: String
    public var code: Int
    public var message: String

    public init(agentId: String, runId: String, code: Int, message: String) {
        self.agentId = agentId
        self.runId = runId
        self.code = code
        self.message = message
    }
}

public struct AgentEndedEvent: Sendable, Equatable {
    public var agentId: String
    public var runId: String
    public var status: RunEndStatus

    public init(agentId: String, runId: String, status: RunEndStatus) {
        self.agentId = agentId
        self.runId = runId
        self.status = status
    }
}

public struct WorkEventAppendedEvent: Sendable, Equatable {
    public var workId: String
    public var event: WorkEvent

    public init(workId: String, event: WorkEvent) {
        self.workId = workId
        self.event = event
    }
}

public struct WorkCatalogUpdatedEvent: Sendable, Equatable {
    public var workId: String
    public var catalog: WorkCatalog

    public init(workId: String, catalog: WorkCatalog) {
        self.workId = workId
        self.catalog = catalog
    }
}

public enum HostEvent: Sendable, Equatable {
    case agentUpdated(AgentView)
    case agentMessageDelta(AgentMessageDeltaEvent)
    case agentMessageCompleted(AgentMessageCompletedEvent)
    case agentToolPending(AgentToolPendingEvent)
    case agentToolStarted(AgentToolStartedEvent)
    case agentToolCompleted(AgentToolCompletedEvent)
    case agentError(AgentErrorEvent)
    case agentEnded(AgentEndedEvent)
    case workUpdated(WorkProfile)
    case workEventAppended(WorkEventAppendedEvent)
    case workCatalogUpdated(WorkCatalogUpdatedEvent)
    case proactiveUpdated(ProactiveSnapshot?)
    case settingsUpdated(PublicSettings)

    public var name: String {
        switch self {
        case .agentUpdated: HostEvents.agentUpdated
        case .agentMessageDelta: HostEvents.agentMessageDelta
        case .agentMessageCompleted: HostEvents.agentMessageCompleted
        case .agentToolPending: HostEvents.agentToolPending
        case .agentToolStarted: HostEvents.agentToolStarted
        case .agentToolCompleted: HostEvents.agentToolCompleted
        case .agentError: HostEvents.agentError
        case .agentEnded: HostEvents.agentEnded
        case .workUpdated: HostEvents.workUpdated
        case .workEventAppended: HostEvents.workEventAppended
        case .workCatalogUpdated: HostEvents.workCatalogUpdated
        case .proactiveUpdated: HostEvents.proactiveUpdated
        case .settingsUpdated: HostEvents.settingsUpdated
        }
    }
}
