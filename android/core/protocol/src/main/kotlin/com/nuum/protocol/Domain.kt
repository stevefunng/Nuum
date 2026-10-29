package com.nuum.protocol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

@Serializable
enum class ProviderId {
    @SerialName("openai") OPENAI,
    @SerialName("anthropic") ANTHROPIC,
    @SerialName("deepseek") DEEPSEEK
}

val DEFAULT_MODEL_ID: Map<ProviderId, String> = mapOf(
    ProviderId.OPENAI to "gpt-4o",
    ProviderId.ANTHROPIC to "claude-sonnet-4-20250514",
    ProviderId.DEEPSEEK to "deepseek-chat"
)

/** Preferred provider first when the selected provider has no key. */
val PROVIDER_FALLBACK: List<ProviderId> = listOf(
    ProviderId.DEEPSEEK,
    ProviderId.OPENAI,
    ProviderId.ANTHROPIC
)

const val DEFAULT_AGENT_NAME = "Assistant"

@Serializable
enum class LocalToolAction {
    @SerialName("read-file") READ_FILE,
    @SerialName("list-directory") LIST_DIRECTORY,
    @SerialName("write-file") WRITE_FILE,
    @SerialName("run-command") RUN_COMMAND,
    @SerialName("network") NETWORK
}

@Serializable
enum class ToolPermission {
    @SerialName("always") ALWAYS,
    @SerialName("ask") ASK,
    @SerialName("never") NEVER
}

@Serializable
enum class ToolResolution {
    @SerialName("always") ALWAYS,
    @SerialName("once") ONCE,
    @SerialName("deny") DENY,
    @SerialName("never") NEVER
}

@Serializable
enum class ThemePreference {
    @SerialName("light") LIGHT,
    @SerialName("dark") DARK,
    @SerialName("system") SYSTEM
}

@Serializable
enum class Language {
    @SerialName("zh-CN") ZH_CN,
    @SerialName("en") EN
}

@Serializable
enum class AgentStatus {
    @SerialName("idle") IDLE,
    @SerialName("running") RUNNING,
    @SerialName("error") ERROR
}

@Serializable
enum class MessageRole {
    @SerialName("system") SYSTEM,
    @SerialName("user") USER,
    @SerialName("assistant") ASSISTANT,
    @SerialName("tool") TOOL
}

@Serializable
enum class CommandPermission {
    @SerialName("ask") ASK,
    @SerialName("always") ALWAYS,
    @SerialName("never") NEVER
}

@Serializable
data class ModelRef(val provider: ProviderId, val model: String)

@Serializable
data class ToolApproval(val action: LocalToolAction, val target: String)

@Serializable
data class ToolCall(val id: String, val name: String, val arguments: JsonObject)

@Serializable
data class ModelImage(val mimeType: String, val data: String)

@Serializable
data class ToolDefinition(
    val name: String,
    val description: String,
    val inputSchema: JsonObject,
    val mutating: Boolean,
    val action: LocalToolAction? = null
)

@Serializable
data class ChatMessage(
    val id: String,
    val role: MessageRole,
    val content: String,
    val images: List<ModelImage>? = null,
    val thinking: String? = null,
    val toolCalls: List<ToolCall>? = null,
    val toolCallId: String? = null,
    val name: String? = null,
    val seq: Int,
    val createdAt: Long
)

@Serializable
data class CommandGrant(val workspaceId: String, val command: String)

@Serializable
data class NetworkGrant(val workspaceId: String, val target: String)

@Serializable
data class ExecutionPreferences(
    val workspaceId: String,
    val commands: CommandPermission = CommandPermission.ASK,
    val commandGrants: List<CommandGrant> = emptyList(),
    val externalGrants: List<ExternalGrant>? = null,
    val networkGrants: List<NetworkGrant> = emptyList()
)

@Serializable
data class WorkspaceSettings(
    val projectRoot: String?,
    val toolPermission: ToolPermission?
)

@Serializable
data class AgentProfile(
    val id: String,
    val name: String,
    val description: String,
    val tags: List<String>? = null,
    val avatarColor: String? = null,
    val avatarShape: String? = null,
    val avatarMaterial: String? = null,
    val createdAt: Long
)

@Serializable
data class AgentSettings(
    val execution: ExecutionPreferences? = null,
    val model: ModelRef,
    val workspace: WorkspaceSettings? = null,
    val hiddenFromSidebar: Boolean? = null,
    val proactive: ProactivePolicy? = null,
    val workMembership: WorkMembership? = null
)

@Serializable
data class AgentRuntime(
    val activeRunId: String? = null,
    val status: AgentStatus,
    val unread: Boolean,
    val lastActivityAt: Long
)

@Serializable
data class AgentView(
    val roomMemberships: Map<String, WorkMembership>? = null,
    val profile: AgentProfile,
    val settings: AgentSettings,
    val runtime: AgentRuntime
)

const val SIDEBAR_NAME_MAX = 80
const val SIDEBAR_UNIQUENESS_MESSAGE = "Sidebar groups, memberships and pins must be unique"

@Serializable
data class SidebarSection(
    val id: String,
    val name: String,
    val agentIds: List<String>,
    val isCollapsed: Boolean? = null
)

@Serializable
data class SidebarOrganization(
    val pinnedAgentIds: List<String> = emptyList(),
    val sections: List<SidebarSection> = emptyList()
)

/**
 * Pins, section ids, and section memberships are each unique.
 * Returns the Mac validation sentence, or null when the organization is valid.
 * Does not trim; [validateSidebar] does.
 */
fun sidebarUniquenessError(value: SidebarOrganization): String? {
    val groupIds = value.sections.map { it.id }
    val members = value.sections.flatMap { it.agentIds }
    val unique = groupIds.toSet().size == groupIds.size &&
        members.toSet().size == members.size &&
        value.pinnedAgentIds.toSet().size == value.pinnedAgentIds.size
    return if (unique) null else SIDEBAR_UNIQUENESS_MESSAGE
}

/** Trims section names and enforces the Mac sidebar schema, including uniqueness. */
fun validateSidebar(value: SidebarOrganization): SidebarOrganization {
    val issues = mutableListOf<ProtocolIssue>()
    val sections = value.sections.mapIndexed { index, section ->
        val name = section.name.trim()
        if (section.id.isEmpty()) {
            issues += ProtocolIssue(listOf("sections", index.toString(), "id"), "String must contain at least 1 character(s)")
        }
        if (name.isEmpty()) {
            issues += ProtocolIssue(listOf("sections", index.toString(), "name"), "String must contain at least 1 character(s)")
        } else if (name.length > SIDEBAR_NAME_MAX) {
            issues += ProtocolIssue(listOf("sections", index.toString(), "name"), "String must contain at most 80 character(s)")
        }
        section.copy(name = name)
    }
    val normalized = value.copy(sections = sections)
    sidebarUniquenessError(normalized)?.let { issues += ProtocolIssue(emptyList(), it) }
    if (issues.isNotEmpty()) throw ProtocolParseException(issues)
    return normalized
}

/**
 * Trim, reject blanks, and keep the first occurrence of each tag.
 * Matches `AgentTags` in domain.ts.
 */
fun normalizeAgentTags(tags: List<String>): List<String> {
    val seen = LinkedHashSet<String>()
    tags.forEachIndexed { index, raw ->
        val tag = raw.trim()
        if (tag.isEmpty()) {
            throw ProtocolParseException(
                listOf(ProtocolIssue(listOf("tags", index.toString()), "String must contain at least 1 character(s)"))
            )
        }
        seen += tag
    }
    return seen.toList()
}

@Serializable
data class Settings(
    val defaultToolPermission: ToolPermission,
    val defaultModel: ModelRef,
    val theme: ThemePreference,
    val language: Language? = null,
    val sidebar: SidebarOrganization? = null
)

@Serializable
data class PublicSettings(
    val defaultToolPermission: ToolPermission,
    val defaultModel: ModelRef,
    val theme: ThemePreference,
    val language: Language? = null,
    val sidebar: SidebarOrganization? = null,
    val hasOpenaiKey: Boolean,
    val hasAnthropicKey: Boolean,
    val hasDeepseekKey: Boolean
)

@Serializable
data class Secrets(
    val openaiApiKey: String? = null,
    val anthropicApiKey: String? = null,
    val deepseekApiKey: String? = null
)

fun secretForProvider(secrets: Secrets, provider: ProviderId): String? = when (provider) {
    ProviderId.OPENAI -> secrets.openaiApiKey
    ProviderId.ANTHROPIC -> secrets.anthropicApiKey
    ProviderId.DEEPSEEK -> secrets.deepseekApiKey
}

/**
 * Keeps [preferred] when that provider has a non-empty key.
 * Otherwise walks [PROVIDER_FALLBACK] and returns that provider's [DEFAULT_MODEL_ID].
 * An empty string is not a key, matching JavaScript truthiness.
 */
fun resolveAvailableModel(secrets: Secrets, preferred: ModelRef? = null): ModelRef? {
    if (preferred != null && !secretForProvider(secrets, preferred.provider).isNullOrEmpty()) return preferred
    for (provider in PROVIDER_FALLBACK) {
        if (!secretForProvider(secrets, provider).isNullOrEmpty()) {
            return ModelRef(provider, DEFAULT_MODEL_ID.getValue(provider))
        }
    }
    return null
}

val DEFAULT_SETTINGS = Settings(
    defaultToolPermission = ToolPermission.ASK,
    defaultModel = ModelRef(ProviderId.DEEPSEEK, DEFAULT_MODEL_ID.getValue(ProviderId.DEEPSEEK)),
    theme = ThemePreference.DARK,
    language = Language.ZH_CN
)
