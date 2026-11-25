import Foundation

public enum ProviderId: String, Sendable, Equatable, Codable, CaseIterable {
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

/// Preferred provider first when the selected provider has no key.
public let providerFallback: [ProviderId] = [.deepseek, .openai, .anthropic]

public let defaultAgentName = "Assistant"

public enum LocalToolAction: String, Sendable, Equatable, Codable, CaseIterable {
    case readFile = "read-file"
    case listDirectory = "list-directory"
    case writeFile = "write-file"
    case runCommand = "run-command"
    case network
}

public enum ToolPermission: String, Sendable, Equatable, Codable, CaseIterable {
    case always
    case ask
    case never
}

public enum ToolResolution: String, Sendable, Equatable, Codable, CaseIterable {
    case always
    case once
    case deny
    case never
}

public enum ThemePreference: String, Sendable, Equatable, Codable, CaseIterable {
    case light
    case dark
    case system
}

public enum Language: String, Sendable, Equatable, Codable, CaseIterable {
    case zhCN = "zh-CN"
    case en
}

public enum AgentStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case idle
    case running
    case error
}

public enum MessageRole: String, Sendable, Equatable, Codable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

public enum CommandPermission: String, Sendable, Equatable, Codable, CaseIterable {
    case ask
    case always
    case never
}

public struct ModelRef: WireRepresentable, Sendable, Equatable {
    public var provider: ProviderId
    public var model: String

    public init(provider: ProviderId, model: String) {
        self.provider = provider
        self.model = model
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        provider = try object.enumeration("provider", as: ProviderId.self)
        model = try object.string("model")
        if model.isEmpty {
            throw ProtocolParseException(["model"], "String must contain at least 1 character(s)")
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("provider", provider.rawValue)
        fields.add("model", model)
        return fields.json
    }
}

public struct ToolApproval: WireRepresentable, Sendable, Equatable {
    public var action: LocalToolAction
    public var target: String

    public init(action: LocalToolAction, target: String) {
        self.action = action
        self.target = target
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        action = try object.enumeration("action", as: LocalToolAction.self)
        target = try object.string("target")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("action", action.rawValue)
        fields.add("target", target)
        return fields.json
    }
}

public struct ToolCall: WireRepresentable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var arguments: JSONValue

    public init(id: String, name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        id = try object.string("id")
        name = try object.string("name")
        arguments = try object.require("arguments")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("id", id)
        fields.add("name", name)
        fields.add("arguments", arguments)
        return fields.json
    }
}

public struct ModelImage: WireRepresentable, Sendable, Equatable {
    public var mimeType: String
    public var data: String

    public init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        mimeType = try object.string("mimeType")
        guard imageMIMETypes.contains(mimeType) else {
            throw ProtocolParseException(["mimeType"], "Invalid enum value")
        }
        data = try object.string("data")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("mimeType", mimeType)
        fields.add("data", data)
        return fields.json
    }
}

public struct ToolDefinition: WireRepresentable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue
    public var mutating: Bool
    public var action: LocalToolAction?

    public init(
        name: String,
        description: String,
        inputSchema: JSONValue,
        mutating: Bool,
        action: LocalToolAction? = nil
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.mutating = mutating
        self.action = action
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        name = try object.string("name")
        description = try object.string("description")
        inputSchema = try object.require("inputSchema")
        mutating = try object.bool("mutating")
        action = try object.optionalEnumeration("action", as: LocalToolAction.self)
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("name", name)
        fields.add("description", description)
        fields.add("inputSchema", inputSchema)
        fields.add("mutating", mutating)
        if let action { fields.add("action", action.rawValue) }
        return fields.json
    }
}

public struct ChatMessage: WireRepresentable, Sendable, Equatable {
    public var id: String
    public var role: MessageRole
    public var content: String
    public var images: [ModelImage]?
    public var thinking: String?
    public var toolCalls: [ToolCall]?
    public var toolCallId: String?
    public var name: String?
    public var seq: Int
    public var createdAt: Int64

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

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        id = try object.string("id")
        role = try object.enumeration("role", as: MessageRole.self)
        content = try object.string("content")
        if let imagesJSON = try object.optionalArray("images") {
            images = try imagesJSON.map { try ModelImage(protocolJSON: $0) }
        } else {
            images = nil
        }
        thinking = try object.optionalString("thinking")
        if let calls = try object.optionalArray("toolCalls") {
            toolCalls = try calls.map { try ToolCall(protocolJSON: $0) }
        } else {
            toolCalls = nil
        }
        toolCallId = try object.optionalString("toolCallId")
        name = try object.optionalString("name")
        seq = try object.int("seq")
        createdAt = try object.int64("createdAt")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("id", id)
        fields.add("role", role.rawValue)
        fields.add("content", content)
        if let images {
            fields.add("images", .array(images.map(\.protocolJSON)))
        }
        fields.addIfPresent("thinking", thinking)
        if let toolCalls {
            fields.add("toolCalls", .array(toolCalls.map(\.protocolJSON)))
        }
        fields.addIfPresent("toolCallId", toolCallId)
        fields.addIfPresent("name", name)
        fields.add("seq", seq)
        fields.add("createdAt", createdAt)
        return fields.json
    }

    /// Budget payload. Image bytes are removed; each image is charged separately.
    var budgetJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("id", id)
        fields.add("role", role.rawValue)
        fields.add("content", content)
        fields.addIfPresent("thinking", thinking)
        if let toolCalls {
            fields.add("toolCalls", .array(toolCalls.map(\.protocolJSON)))
        }
        fields.addIfPresent("toolCallId", toolCallId)
        fields.addIfPresent("name", name)
        fields.add("seq", seq)
        fields.add("createdAt", createdAt)
        return fields.json
    }
}

public struct CommandGrant: WireRepresentable, Sendable, Equatable {
    public var workspaceId: String
    public var command: String

    public init(workspaceId: String, command: String) {
        self.workspaceId = workspaceId
        self.command = command
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        workspaceId = try object.string("workspaceId")
        command = try object.string("command")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("workspaceId", workspaceId)
        fields.add("command", command)
        return fields.json
    }
}

public struct NetworkGrant: WireRepresentable, Sendable, Equatable {
    public var workspaceId: String
    public var target: String

    public init(workspaceId: String, target: String) {
        self.workspaceId = workspaceId
        self.target = target
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        workspaceId = try object.string("workspaceId")
        target = try object.string("target")
        guard isNetworkTarget(target) else {
            throw ProtocolParseException(["target"], "Use an exact hostname and port 80 or 443")
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("workspaceId", workspaceId)
        fields.add("target", target)
        return fields.json
    }
}

public struct ExecutionPreferences: WireRepresentable, Sendable, Equatable {
    public var workspaceId: String
    public var commands: CommandPermission
    public var commandGrants: [CommandGrant]
    public var externalGrants: [ExternalGrant]?
    public var networkGrants: [NetworkGrant]

    public init(
        workspaceId: String,
        commands: CommandPermission = .ask,
        commandGrants: [CommandGrant] = [],
        externalGrants: [ExternalGrant]? = nil,
        networkGrants: [NetworkGrant] = []
    ) {
        self.workspaceId = workspaceId
        self.commands = commands
        self.commandGrants = commandGrants
        self.externalGrants = externalGrants
        self.networkGrants = networkGrants
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        workspaceId = try object.string("workspaceId")
        commands = try object.optionalEnumeration("commands", as: CommandPermission.self) ?? .ask
        commandGrants = try object.optionalArray("commandGrants")?.map { try CommandGrant(protocolJSON: $0) } ?? []
        if let grants = try object.optionalArray("externalGrants") {
            externalGrants = try grants.map { try ExternalGrant(protocolJSON: $0) }
        } else {
            externalGrants = nil
        }
        networkGrants = try object.optionalArray("networkGrants")?.map { try NetworkGrant(protocolJSON: $0) } ?? []
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("workspaceId", workspaceId)
        fields.add("commands", commands.rawValue)
        fields.add("commandGrants", .array(commandGrants.map(\.protocolJSON)))
        if let externalGrants {
            fields.add("externalGrants", .array(externalGrants.map(\.protocolJSON)))
        }
        fields.add("networkGrants", .array(networkGrants.map(\.protocolJSON)))
        return fields.json
    }
}

public struct WorkspaceSettings: WireRepresentable, Sendable, Equatable {
    public var projectRoot: String?
    public var toolPermission: ToolPermission?

    public init(projectRoot: String?, toolPermission: ToolPermission?) {
        self.projectRoot = projectRoot
        self.toolPermission = toolPermission
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        projectRoot = try object.nullableString("projectRoot")
        if let raw = object.value("toolPermission") {
            if raw.isNull {
                toolPermission = nil
            } else if case .string(let wire) = raw, let permission = ToolPermission(rawValue: wire) {
                toolPermission = permission
            } else {
                throw ProtocolParseException(["toolPermission"], "Invalid enum value")
            }
        } else {
            throw ProtocolParseException(["toolPermission"], "Required")
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("projectRoot", projectRoot.map(JSONValue.string) ?? .null)
        fields.add("toolPermission", toolPermission.map { JSONValue.string($0.rawValue) } ?? .null)
        return fields.json
    }
}

public struct AgentProfile: WireRepresentable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var tags: [String]?
    public var avatarColor: String?
    public var avatarShape: String?
    public var avatarMaterial: String?
    public var createdAt: Int64

    public init(
        id: String,
        name: String,
        description: String,
        createdAt: Int64,
        tags: [String]? = nil,
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

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        id = try object.string("id")
        name = try object.string("name")
        description = try object.string("description")
        if let tags = try object.optionalStringArray("tags") {
            self.tags = try normalizeAgentTags(tags)
        } else {
            tags = nil
        }
        avatarColor = try object.optionalString("avatarColor")
        avatarShape = try object.optionalString("avatarShape")
        avatarMaterial = try object.optionalString("avatarMaterial")
        createdAt = try object.int64("createdAt")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("id", id)
        fields.add("name", name)
        fields.add("description", description)
        if let tags { fields.add("tags", .array(tags.map(JSONValue.string))) }
        fields.addIfPresent("avatarColor", avatarColor)
        fields.addIfPresent("avatarShape", avatarShape)
        fields.addIfPresent("avatarMaterial", avatarMaterial)
        fields.add("createdAt", createdAt)
        return fields.json
    }
}

public struct AgentSettings: WireRepresentable, Sendable, Equatable {
    public var execution: ExecutionPreferences?
    public var model: ModelRef
    public var workspace: WorkspaceSettings?
    public var hiddenFromSidebar: Bool?
    public var proactive: ProactivePolicy?
    public var workMembership: WorkMembership?

    public init(
        model: ModelRef,
        execution: ExecutionPreferences? = nil,
        workspace: WorkspaceSettings? = nil,
        hiddenFromSidebar: Bool? = nil,
        proactive: ProactivePolicy? = nil,
        workMembership: WorkMembership? = nil
    ) {
        self.model = model
        self.execution = execution
        self.workspace = workspace
        self.hiddenFromSidebar = hiddenFromSidebar
        self.proactive = proactive
        self.workMembership = workMembership
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        if let executionJSON = try object.optionalObject("execution") {
            execution = try ExecutionPreferences(protocolJSON: executionJSON.json)
        } else {
            execution = nil
        }
        model = try ModelRef(protocolJSON: object.require("model"))
        if let workspaceJSON = try object.optionalObject("workspace") {
            workspace = try WorkspaceSettings(protocolJSON: workspaceJSON.json)
        } else {
            workspace = nil
        }
        hiddenFromSidebar = try object.optionalBool("hiddenFromSidebar")
        if let proactiveJSON = try object.optionalObject("proactive") {
            proactive = try ProactivePolicy(protocolJSON: proactiveJSON.json)
        } else {
            proactive = nil
        }
        if let membershipJSON = try object.optionalObject("workMembership") {
            workMembership = try WorkMembership(protocolJSON: membershipJSON.json)
        } else {
            workMembership = nil
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        if let execution { fields.add("execution", execution.protocolJSON) }
        fields.add("model", model.protocolJSON)
        if let workspace { fields.add("workspace", workspace.protocolJSON) }
        fields.addIfPresent("hiddenFromSidebar", hiddenFromSidebar)
        if let proactive { fields.add("proactive", proactive.protocolJSON) }
        if let workMembership { fields.add("workMembership", workMembership.protocolJSON) }
        return fields.json
    }
}

public struct AgentRuntime: WireRepresentable, Sendable, Equatable {
    public var activeRunId: String?
    public var status: AgentStatus
    public var unread: Bool
    public var lastActivityAt: Int64

    public init(status: AgentStatus, unread: Bool, lastActivityAt: Int64, activeRunId: String? = nil) {
        self.status = status
        self.unread = unread
        self.lastActivityAt = lastActivityAt
        self.activeRunId = activeRunId
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        activeRunId = try object.optionalString("activeRunId")
        status = try object.enumeration("status", as: AgentStatus.self)
        unread = try object.bool("unread")
        lastActivityAt = try object.int64("lastActivityAt")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.addIfPresent("activeRunId", activeRunId)
        fields.add("status", status.rawValue)
        fields.add("unread", unread)
        fields.add("lastActivityAt", lastActivityAt)
        return fields.json
    }
}

public struct AgentView: WireRepresentable, Sendable, Equatable {
    public var roomMemberships: [String: WorkMembership]?
    public var profile: AgentProfile
    public var settings: AgentSettings
    public var runtime: AgentRuntime

    public init(
        profile: AgentProfile,
        settings: AgentSettings,
        runtime: AgentRuntime,
        roomMemberships: [String: WorkMembership]? = nil
    ) {
        self.profile = profile
        self.settings = settings
        self.runtime = runtime
        self.roomMemberships = roomMemberships
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        if let rooms = try object.optionalObject("roomMemberships") {
            var mapped: [String: WorkMembership] = [:]
            for (key, value) in rooms.pairs {
                mapped[key] = try WorkMembership(protocolJSON: value)
            }
            roomMemberships = mapped
        } else {
            roomMemberships = nil
        }
        profile = try AgentProfile(protocolJSON: object.require("profile"))
        settings = try AgentSettings(protocolJSON: object.require("settings"))
        runtime = try AgentRuntime(protocolJSON: object.require("runtime"))
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        if let roomMemberships {
            let pairs = roomMemberships.keys.sorted().map { key in
                (key, roomMemberships[key]!.protocolJSON)
            }
            fields.add("roomMemberships", .object(pairs))
        }
        fields.add("profile", profile.protocolJSON)
        fields.add("settings", settings.protocolJSON)
        fields.add("runtime", runtime.protocolJSON)
        return fields.json
    }
}

public let sidebarNameMax = 80
public let sidebarUniquenessMessage = "Sidebar groups, memberships and pins must be unique"

public struct SidebarSection: WireRepresentable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var agentIds: [String]
    public var isCollapsed: Bool?

    public init(id: String, name: String, agentIds: [String], isCollapsed: Bool? = nil) {
        self.id = id
        self.name = name
        self.agentIds = agentIds
        self.isCollapsed = isCollapsed
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        id = try object.string("id")
        name = try object.string("name")
        agentIds = try object.stringArray("agentIds")
        isCollapsed = try object.optionalBool("isCollapsed")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("id", id)
        fields.add("name", name)
        fields.add("agentIds", .array(agentIds.map(JSONValue.string)))
        fields.addIfPresent("isCollapsed", isCollapsed)
        return fields.json
    }
}

public struct SidebarOrganization: WireRepresentable, Sendable, Equatable {
    public var pinnedAgentIds: [String]
    public var sections: [SidebarSection]

    public init(pinnedAgentIds: [String] = [], sections: [SidebarSection] = []) {
        self.pinnedAgentIds = pinnedAgentIds
        self.sections = sections
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        pinnedAgentIds = try object.stringArray("pinnedAgentIds")
        if object.contains("sections") {
            sections = try object.array("sections").map { try SidebarSection(protocolJSON: $0) }
        } else {
            sections = []
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("pinnedAgentIds", .array(pinnedAgentIds.map(JSONValue.string)))
        fields.add("sections", .array(sections.map(\.protocolJSON)))
        return fields.json
    }
}

/// Pins, section ids, and section memberships are each unique.
/// Returns the Mac validation sentence, or nil when the organization is valid.
/// Does not trim; `validateSidebar` does.
public func sidebarUniquenessError(_ value: SidebarOrganization) -> String? {
    let groupIDs = value.sections.map(\.id)
    let members = value.sections.flatMap(\.agentIds)
    let unique = Set(groupIDs).count == groupIDs.count
        && Set(members).count == members.count
        && Set(value.pinnedAgentIds).count == value.pinnedAgentIds.count
    return unique ? nil : sidebarUniquenessMessage
}

/// Trims section names and enforces the Mac sidebar schema, including uniqueness.
public func validateSidebar(_ value: SidebarOrganization) throws -> SidebarOrganization {
    var issues: [ProtocolIssue] = []
    let sections = value.sections.enumerated().map { index, section in
        let name = section.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if section.id.isEmpty {
            issues.append(ProtocolIssue(path: ["sections", String(index), "id"], message: "String must contain at least 1 character(s)"))
        }
        if name.isEmpty {
            issues.append(ProtocolIssue(path: ["sections", String(index), "name"], message: "String must contain at least 1 character(s)"))
        } else if name.count > sidebarNameMax {
            issues.append(ProtocolIssue(path: ["sections", String(index), "name"], message: "String must contain at most 80 character(s)"))
        }
        return SidebarSection(id: section.id, name: name, agentIds: section.agentIds, isCollapsed: section.isCollapsed)
    }
    let normalized = SidebarOrganization(pinnedAgentIds: value.pinnedAgentIds, sections: sections)
    if let uniqueness = sidebarUniquenessError(normalized) {
        issues.append(ProtocolIssue(path: [], message: uniqueness))
    }
    if !issues.isEmpty { throw ProtocolParseException(issues) }
    return normalized
}

/// Trim, reject blanks, and keep the first occurrence of each tag.
/// Matches `AgentTags` in domain.ts.
public func normalizeAgentTags(_ tags: [String]) throws -> [String] {
    var seen: [String] = []
    for (index, raw) in tags.enumerated() {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag.isEmpty {
            throw ProtocolParseException(["tags", String(index)], "String must contain at least 1 character(s)")
        }
        if !seen.contains(tag) { seen.append(tag) }
    }
    return seen
}

public struct Settings: WireRepresentable, Sendable, Equatable {
    public var defaultToolPermission: ToolPermission
    public var defaultModel: ModelRef
    public var theme: ThemePreference
    public var language: Language?
    public var sidebar: SidebarOrganization?

    public init(
        defaultToolPermission: ToolPermission,
        defaultModel: ModelRef,
        theme: ThemePreference,
        language: Language? = nil,
        sidebar: SidebarOrganization? = nil
    ) {
        self.defaultToolPermission = defaultToolPermission
        self.defaultModel = defaultModel
        self.theme = theme
        self.language = language
        self.sidebar = sidebar
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        defaultToolPermission = try object.enumeration("defaultToolPermission", as: ToolPermission.self)
        defaultModel = try ModelRef(protocolJSON: object.require("defaultModel"))
        theme = try object.enumeration("theme", as: ThemePreference.self)
        language = try object.optionalEnumeration("language", as: Language.self)
        if let sidebarJSON = try object.optionalObject("sidebar") {
            sidebar = try SidebarOrganization(protocolJSON: sidebarJSON.json)
        } else {
            sidebar = nil
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("defaultToolPermission", defaultToolPermission.rawValue)
        fields.add("defaultModel", defaultModel.protocolJSON)
        fields.add("theme", theme.rawValue)
        if let language { fields.add("language", language.rawValue) }
        if let sidebar { fields.add("sidebar", sidebar.protocolJSON) }
        return fields.json
    }
}

public struct PublicSettings: WireRepresentable, Sendable, Equatable {
    public var defaultToolPermission: ToolPermission
    public var defaultModel: ModelRef
    public var theme: ThemePreference
    public var language: Language?
    public var sidebar: SidebarOrganization?
    public var hasOpenaiKey: Bool
    public var hasAnthropicKey: Bool
    public var hasDeepseekKey: Bool

    public init(
        defaultToolPermission: ToolPermission,
        defaultModel: ModelRef,
        theme: ThemePreference,
        hasOpenaiKey: Bool,
        hasAnthropicKey: Bool,
        hasDeepseekKey: Bool,
        language: Language? = nil,
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

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        defaultToolPermission = try object.enumeration("defaultToolPermission", as: ToolPermission.self)
        defaultModel = try ModelRef(protocolJSON: object.require("defaultModel"))
        theme = try object.enumeration("theme", as: ThemePreference.self)
        language = try object.optionalEnumeration("language", as: Language.self)
        if let sidebarJSON = try object.optionalObject("sidebar") {
            sidebar = try SidebarOrganization(protocolJSON: sidebarJSON.json)
        } else {
            sidebar = nil
        }
        hasOpenaiKey = try object.bool("hasOpenaiKey")
        hasAnthropicKey = try object.bool("hasAnthropicKey")
        hasDeepseekKey = try object.bool("hasDeepseekKey")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("defaultToolPermission", defaultToolPermission.rawValue)
        fields.add("defaultModel", defaultModel.protocolJSON)
        fields.add("theme", theme.rawValue)
        if let language { fields.add("language", language.rawValue) }
        if let sidebar { fields.add("sidebar", sidebar.protocolJSON) }
        fields.add("hasOpenaiKey", hasOpenaiKey)
        fields.add("hasAnthropicKey", hasAnthropicKey)
        fields.add("hasDeepseekKey", hasDeepseekKey)
        return fields.json
    }
}

/// Key material. Description and debug description report presence only.
public struct Secrets: WireRepresentable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var openaiApiKey: String?
    public var anthropicApiKey: String?
    public var deepseekApiKey: String?

    public init(openaiApiKey: String? = nil, anthropicApiKey: String? = nil, deepseekApiKey: String? = nil) {
        self.openaiApiKey = openaiApiKey
        self.anthropicApiKey = anthropicApiKey
        self.deepseekApiKey = deepseekApiKey
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        openaiApiKey = try object.optionalString("openaiApiKey")
        anthropicApiKey = try object.optionalString("anthropicApiKey")
        deepseekApiKey = try object.optionalString("deepseekApiKey")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.addIfPresent("openaiApiKey", openaiApiKey)
        fields.addIfPresent("anthropicApiKey", anthropicApiKey)
        fields.addIfPresent("deepseekApiKey", deepseekApiKey)
        return fields.json
    }

    public var description: String {
        "Secrets(openai: \(openaiApiKey != nil), anthropic: \(anthropicApiKey != nil), deepseek: \(deepseekApiKey != nil))"
    }

    public var debugDescription: String { description }
}

public func secretForProvider(_ secrets: Secrets, _ provider: ProviderId) -> String? {
    switch provider {
    case .openai:
        secrets.openaiApiKey
    case .anthropic:
        secrets.anthropicApiKey
    case .deepseek:
        secrets.deepseekApiKey
    }
}

/// Keeps `preferred` when that provider has a non-empty key.
/// Otherwise walks `providerFallback` and returns that provider's default model id.
/// An empty string is not a key, matching JavaScript truthiness.
public func resolveAvailableModel(_ secrets: Secrets, preferred: ModelRef? = nil) -> ModelRef? {
    if let preferred, let key = secretForProvider(secrets, preferred.provider), !key.isEmpty {
        return preferred
    }
    for provider in providerFallback {
        if let key = secretForProvider(secrets, provider), !key.isEmpty {
            return ModelRef(provider: provider, model: defaultModelID(for: provider))
        }
    }
    return nil
}

public let defaultSettings = Settings(
    defaultToolPermission: .ask,
    defaultModel: ModelRef(provider: .deepseek, model: defaultModelID(for: .deepseek)),
    theme: .dark,
    language: .zhCN
)

extension JSONObject {
    var json: JSONValue { .object(pairs) }
}
