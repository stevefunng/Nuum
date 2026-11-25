import Foundation

public enum ProviderId: String, Sendable, Equatable, CaseIterable {
    case openai
    case anthropic
    case deepseek
}

public enum DeepSeekModelID {
    public static let chat = "deepseek-chat"
    public static let reasoner = "deepseek-reasoner"
}

/// Mac and Android `DEFAULT_MODEL_ID`.
public func defaultModelID(for provider: ProviderId) -> String {
    switch provider {
    case .openai:
        "gpt-4o"
    case .anthropic:
        "claude-sonnet-4-20250514"
    case .deepseek:
        DeepSeekModelID.chat
    }
}

public let defaultModelIDs: [ProviderId: String] = [
    .openai: defaultModelID(for: .openai),
    .anthropic: defaultModelID(for: .anthropic),
    .deepseek: defaultModelID(for: .deepseek),
]

/// Selected provider with a key first, otherwise this order, back at that provider's default model.
public let providerFallback: [ProviderId] = [.deepseek, .openai, .anthropic]

public let defaultAgentName = "Assistant"

public enum LocalToolAction: String, Sendable, Equatable, CaseIterable {
    case readFile = "read-file"
    case listDirectory = "list-directory"
    case writeFile = "write-file"
    case runCommand = "run-command"
    case network
}

public enum ToolPermission: String, Sendable, Equatable, CaseIterable {
    case always
    case ask
    case never
}

public enum ToolResolution: String, Sendable, Equatable, CaseIterable {
    case always
    case once
    case deny
    case never
}

public enum ThemePreference: String, Sendable, Equatable, CaseIterable {
    case light
    case dark
    case system
}

public enum Language: String, Sendable, Equatable, CaseIterable {
    case zhCN = "zh-CN"
    case en
}

public enum AgentStatus: String, Sendable, Equatable, CaseIterable {
    case idle
    case running
    case error
}

public enum RunEndStatus: String, Sendable, Equatable, CaseIterable {
    case idle
    case error
    case cancelled
}

public enum MessageRole: String, Sendable, Equatable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

public enum MessagePart: String, Sendable, Equatable, CaseIterable {
    case text
    case thinking
}

public struct ModelRef: Sendable, Equatable {
    public var provider: ProviderId
    public var model: String

    public init(provider: ProviderId, model: String) {
        self.provider = provider
        self.model = model
    }
}

public struct ToolApproval: Sendable, Equatable {
    public var action: LocalToolAction
    public var target: String

    public init(action: LocalToolAction, target: String) {
        self.action = action
        self.target = target
    }
}

public struct ToolCall: Sendable, Equatable {
    public var id: String
    public var name: String
    public var arguments: [String: JSONValue]

    public init(id: String, name: String, arguments: [String: JSONValue]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct ToolDefinition: Sendable, Equatable {
    public var name: String
    public var description: String
    public var inputSchema: [String: JSONValue]
    public var mutating: Bool
    public var action: LocalToolAction?

    public init(
        name: String,
        description: String,
        inputSchema: [String: JSONValue],
        mutating: Bool,
        action: LocalToolAction? = nil
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.mutating = mutating
        self.action = action
    }
}

public struct ModelImage: Sendable, Equatable {
    public var mimeType: String
    public var data: String

    public init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }
}

public let imageMIMETypes: Set<String> = [
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/webp",
]

public struct ChatMessage: Sendable, Equatable {
    public var id: String
    public var role: MessageRole
    public var content: String
    public var seq: Int
    public var createdAt: Int64
    public var images: [ModelImage]?
    public var thinking: String?
    public var toolCalls: [ToolCall]?
    public var toolCallId: String?
    public var name: String?

    public init(
        id: String,
        role: MessageRole,
        content: String,
        seq: Int,
        createdAt: Int64,
        images: [ModelImage]? = nil,
        thinking: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        name: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.seq = seq
        self.createdAt = createdAt
        self.images = images
        self.thinking = thinking
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.name = name
    }
}

/// Key material. Description and debug description report presence only.
public struct Secrets: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var openaiApiKey: String?
    public var anthropicApiKey: String?
    public var deepseekApiKey: String?

    public init(
        openaiApiKey: String? = nil,
        anthropicApiKey: String? = nil,
        deepseekApiKey: String? = nil
    ) {
        self.openaiApiKey = openaiApiKey
        self.anthropicApiKey = anthropicApiKey
        self.deepseekApiKey = deepseekApiKey
    }

    public static let empty = Secrets()

    public var description: String {
        "Secrets(openai: \(openaiApiKey != nil), anthropic: \(anthropicApiKey != nil), deepseek: \(deepseekApiKey != nil))"
    }

    public var debugDescription: String { description }
}

public struct SidebarSection: Sendable, Equatable {
    public var id: String
    public var name: String
    public var agentIds: [String]
    public var isCollapsed: Bool

    public init(id: String, name: String, agentIds: [String], isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.agentIds = agentIds
        self.isCollapsed = isCollapsed
    }
}

public struct SidebarOrganization: Sendable, Equatable {
    public var pinnedAgentIds: [String]
    public var sections: [SidebarSection]

    public init(pinnedAgentIds: [String] = [], sections: [SidebarSection] = []) {
        self.pinnedAgentIds = pinnedAgentIds
        self.sections = sections
    }
}

public struct Settings: Sendable, Equatable {
    public var defaultToolPermission: ToolPermission
    public var defaultModel: ModelRef
    public var theme: ThemePreference
    public var language: Language
    public var sidebar: SidebarOrganization?

    public init(
        defaultToolPermission: ToolPermission,
        defaultModel: ModelRef,
        theme: ThemePreference,
        language: Language = .zhCN,
        sidebar: SidebarOrganization? = nil
    ) {
        self.defaultToolPermission = defaultToolPermission
        self.defaultModel = defaultModel
        self.theme = theme
        self.language = language
        self.sidebar = sidebar
    }
}

public struct PublicSettings: Sendable, Equatable {
    public var defaultToolPermission: ToolPermission
    public var defaultModel: ModelRef
    public var theme: ThemePreference
    public var hasOpenaiKey: Bool
    public var hasAnthropicKey: Bool
    public var hasDeepseekKey: Bool
    public var language: Language
    public var sidebar: SidebarOrganization?

    public init(
        defaultToolPermission: ToolPermission,
        defaultModel: ModelRef,
        theme: ThemePreference,
        hasOpenaiKey: Bool,
        hasAnthropicKey: Bool,
        hasDeepseekKey: Bool,
        language: Language = .zhCN,
        sidebar: SidebarOrganization? = nil
    ) {
        self.defaultToolPermission = defaultToolPermission
        self.defaultModel = defaultModel
        self.theme = theme
        self.hasOpenaiKey = hasOpenaiKey
        self.hasAnthropicKey = hasAnthropicKey
        self.hasDeepseekKey = hasDeepseekKey
        self.language = language
        self.sidebar = sidebar
    }
}

public let defaultSettings = Settings(
    defaultToolPermission: .ask,
    defaultModel: ModelRef(provider: .deepseek, model: defaultModelID(for: .deepseek)),
    theme: .dark,
    language: .zhCN
)

public struct SettingsPatch: Sendable, Equatable {
    public var defaultToolPermission: ToolPermission?
    public var defaultModel: ModelRef?
    public var theme: ThemePreference?
    public var language: Language?
    public var sidebar: SidebarOrganization?

    public init(
        defaultToolPermission: ToolPermission? = nil,
        defaultModel: ModelRef? = nil,
        theme: ThemePreference? = nil,
        language: Language? = nil,
        sidebar: SidebarOrganization? = nil
    ) {
        self.defaultToolPermission = defaultToolPermission
        self.defaultModel = defaultModel
        self.theme = theme
        self.language = language
        self.sidebar = sidebar
    }
}

/// Mac `MAX_ATTACHMENTS`, `MAX_ATTACHMENT_BYTES`, and `MAX_ATTACHMENT_TOTAL_BYTES`.
public enum AttachmentLimits {
    public static let maxCount = 5
    public static let maxBytes = 10 * 1024 * 1024
    public static let maxTotalBytes = 20 * 1024 * 1024
}

/// In-memory upload. Transcript persistence stores name, path, and size, not these bytes.
public struct AttachmentUpload: Sendable, Equatable {
    public var name: String
    public var mimeType: String
    public var bytes: Data

    public init(name: String, mimeType: String, bytes: Data) {
        self.name = name
        self.mimeType = mimeType
        self.bytes = bytes
    }
}

public struct CommandGrant: Sendable, Equatable {
    public var workspaceId: String
    public var command: String

    public init(workspaceId: String, command: String) {
        self.workspaceId = workspaceId
        self.command = command
    }
}

public struct NetworkGrant: Sendable, Equatable {
    public var workspaceId: String
    public var target: String

    public init(workspaceId: String, target: String) {
        self.workspaceId = workspaceId
        self.target = target
    }
}

public enum CommandPermission: String, Sendable, Equatable, CaseIterable {
    case ask
    case always
    case never
}

public struct ExecutionPreferences: Sendable, Equatable {
    public var workspaceId: String
    public var commands: CommandPermission
    public var commandGrants: [CommandGrant]
    public var networkGrants: [NetworkGrant]

    public init(
        workspaceId: String,
        commands: CommandPermission = .ask,
        commandGrants: [CommandGrant] = [],
        networkGrants: [NetworkGrant] = []
    ) {
        self.workspaceId = workspaceId
        self.commands = commands
        self.commandGrants = commandGrants
        self.networkGrants = networkGrants
    }
}

public struct WorkspaceSettings: Sendable, Equatable {
    public var projectRoot: String?
    public var toolPermission: ToolPermission?

    public init(projectRoot: String?, toolPermission: ToolPermission?) {
        self.projectRoot = projectRoot
        self.toolPermission = toolPermission
    }
}

public struct AgentProfile: Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var createdAt: Int64
    public var tags: [String]
    public var avatarColor: String?
    public var avatarShape: String?
    public var avatarMaterial: String?

    public init(
        id: String,
        name: String,
        description: String,
        createdAt: Int64,
        tags: [String] = [],
        avatarColor: String? = nil,
        avatarShape: String? = nil,
        avatarMaterial: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.tags = tags
        self.avatarColor = avatarColor
        self.avatarShape = avatarShape
        self.avatarMaterial = avatarMaterial
    }
}

public struct AgentRuntime: Sendable, Equatable {
    public var status: AgentStatus
    public var unread: Bool
    public var lastActivityAt: Int64
    public var activeRunId: String?

    public init(status: AgentStatus, unread: Bool, lastActivityAt: Int64, activeRunId: String? = nil) {
        self.status = status
        self.unread = unread
        self.lastActivityAt = lastActivityAt
        self.activeRunId = activeRunId
    }
}

/// Sentences the tool table returns until a later package implements the real behavior.
public enum UnimplementedToolMessage {
    public static let iosClient = "This iOS client does not implement this tool."
    public static let runWorkCLI = "This version of Nuum has no local executable. RunWorkCLI is not implemented."
}

/// Environment sentence for the unfrozen prompt section. WP-07 owns prompt assembly.
public enum IOSEnvironmentPrompt {
    public static let sentence = "This is a local iOS app. You can read files in directories the user authorized. You cannot run a shell."
}
