package com.nuum.contracts

enum class ProviderId(val wire: String) {
    OPENAI("openai"),
    ANTHROPIC("anthropic"),
    DEEPSEEK("deepseek")
}

val DEFAULT_MODEL_ID: Map<ProviderId, String> = mapOf(
    ProviderId.OPENAI to "gpt-4o",
    ProviderId.ANTHROPIC to "claude-sonnet-4-20250514",
    ProviderId.DEEPSEEK to "deepseek-chat"
)

const val DEFAULT_AGENT_NAME = "Assistant"

enum class LocalToolAction(val wire: String) {
    READ_FILE("read-file"),
    LIST_DIRECTORY("list-directory"),
    WRITE_FILE("write-file"),
    RUN_COMMAND("run-command"),
    NETWORK("network")
}

enum class ToolPermission(val wire: String) {
    ALWAYS("always"),
    ASK("ask"),
    NEVER("never")
}

enum class ToolResolution(val wire: String) {
    ALWAYS("always"),
    ONCE("once"),
    DENY("deny"),
    NEVER("never")
}

enum class ThemePreference(val wire: String) {
    LIGHT("light"),
    DARK("dark"),
    SYSTEM("system")
}

enum class Language(val wire: String) {
    ZH_CN("zh-CN"),
    EN("en")
}

enum class AgentStatus(val wire: String) {
    IDLE("idle"),
    RUNNING("running"),
    ERROR("error")
}

enum class RunEndStatus(val wire: String) {
    IDLE("idle"),
    ERROR("error"),
    CANCELLED("cancelled")
}

enum class MessageRole(val wire: String) {
    SYSTEM("system"),
    USER("user"),
    ASSISTANT("assistant"),
    TOOL("tool")
}

enum class MessagePart(val wire: String) {
    TEXT("text"),
    THINKING("thinking")
}

data class ModelRef(val provider: ProviderId, val model: String)

data class ToolApproval(val action: LocalToolAction, val target: String)

data class ToolCall(val id: String, val name: String, val arguments: Map<String, Any?>)

data class ToolDefinition(
    val name: String,
    val description: String,
    val inputSchema: Map<String, Any?>,
    val mutating: Boolean,
    val action: LocalToolAction? = null
)

data class ModelImage(val mimeType: String, val data: String)

val IMAGE_MIME_TYPES: Set<String> = setOf(
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/webp"
)

data class ChatMessage(
    val id: String,
    val role: MessageRole,
    val content: String,
    val seq: Int,
    val createdAt: Long,
    val images: List<ModelImage>? = null,
    val thinking: String? = null,
    val toolCalls: List<ToolCall>? = null,
    val toolCallId: String? = null,
    val name: String? = null
)

data class Secrets(
    val openaiApiKey: String? = null,
    val anthropicApiKey: String? = null,
    val deepseekApiKey: String? = null
)

data class SidebarSection(
    val id: String,
    val name: String,
    val agentIds: List<String>,
    val isCollapsed: Boolean = false
)

data class SidebarOrganization(
    val pinnedAgentIds: List<String> = emptyList(),
    val sections: List<SidebarSection> = emptyList()
)

data class Settings(
    val defaultToolPermission: ToolPermission,
    val defaultModel: ModelRef,
    val theme: ThemePreference,
    val language: Language = Language.ZH_CN,
    val sidebar: SidebarOrganization? = null
)

data class PublicSettings(
    val defaultToolPermission: ToolPermission,
    val defaultModel: ModelRef,
    val theme: ThemePreference,
    val hasOpenaiKey: Boolean,
    val hasAnthropicKey: Boolean,
    val hasDeepseekKey: Boolean,
    val language: Language = Language.ZH_CN,
    val sidebar: SidebarOrganization? = null
)

val DEFAULT_SETTINGS = Settings(
    defaultToolPermission = ToolPermission.ASK,
    defaultModel = ModelRef(ProviderId.DEEPSEEK, DEFAULT_MODEL_ID.getValue(ProviderId.DEEPSEEK)),
    theme = ThemePreference.DARK,
    language = Language.ZH_CN
)

data class SettingsPatch(
    val defaultToolPermission: ToolPermission? = null,
    val defaultModel: ModelRef? = null,
    val theme: ThemePreference? = null,
    val language: Language? = null,
    val sidebar: SidebarOrganization? = null
)

const val MAX_ATTACHMENTS = 5
const val MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024
const val MAX_ATTACHMENT_TOTAL_BYTES = 20 * 1024 * 1024

/** In-memory upload. Transcript persistence stores name, path, and size, not these bytes. */
class AttachmentUpload(
    val name: String,
    val mimeType: String,
    val bytes: ByteArray
)

data class CommandGrant(val workspaceId: String, val command: String)

data class NetworkGrant(val workspaceId: String, val target: String)

enum class CommandPermission(val wire: String) {
    ASK("ask"),
    ALWAYS("always"),
    NEVER("never")
}

data class ExecutionPreferences(
    val workspaceId: String,
    val commands: CommandPermission = CommandPermission.ASK,
    val commandGrants: List<CommandGrant> = emptyList(),
    val networkGrants: List<NetworkGrant> = emptyList()
)

data class WorkspaceSettings(
    val projectRoot: String?,
    val toolPermission: ToolPermission?
)

data class AgentProfile(
    val id: String,
    val name: String,
    val description: String,
    val createdAt: Long,
    val tags: List<String> = emptyList(),
    val avatarColor: String? = null,
    val avatarShape: String? = null,
    val avatarMaterial: String? = null
)

data class AgentRuntime(
    val status: AgentStatus,
    val unread: Boolean,
    val lastActivityAt: Long,
    val activeRunId: String? = null
)
