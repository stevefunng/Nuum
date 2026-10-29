package com.nuum.contracts

import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow

data class NormalizedChatRequest(
    val model: ModelRef,
    val messages: List<ChatMessage>,
    val tools: List<ToolDefinition>,
    val apiKey: String,
    val maxOutputTokens: Int? = null
)

sealed class NormalizedChunk {
    data class Text(val text: String) : NormalizedChunk()
    data class Thinking(val text: String) : NormalizedChunk()
    data class ToolCallChunk(
        val id: String,
        val name: String,
        val arguments: Map<String, Any?>
    ) : NormalizedChunk()
}

/** Cancellation is the collecting coroutine's [Job]. */
interface ModelPort {
    fun streamChat(request: NormalizedChatRequest): Flow<NormalizedChunk>
}

data class ToolRoots(
    val home: String,
    val project: String?,
    val scratch: String,
    val terminals: String,
    val denied: List<String>,
    val readOnly: List<String> = emptyList()
)

data class TurnStartParams(
    val runId: String,
    val messages: List<ChatMessage>,
    val model: ModelRef,
    val roots: ToolRoots,
    val toolPermission: ToolPermission,
    val localToolNames: List<String>,
    val secrets: Secrets,
    val contextWindow: Int? = null,
    val approvals: List<ToolApproval> = emptyList(),
    val refused: List<ToolApproval> = emptyList(),
    val delegatedTools: List<ToolDefinition> = emptyList(),
    val voiceToolNames: List<String> = listOf("SendMessage")
)

data class TurnToolDecision(
    val runId: String,
    val toolCallId: String,
    val resolution: ToolResolution
)

data class TurnToolResult(
    val runId: String,
    val toolCallId: String,
    val ok: Boolean,
    val output: String,
    val endTurn: Boolean = false
)

data class TurnContextResult(
    val runId: String,
    val requestId: String,
    val messages: List<ChatMessage>? = null,
    val error: String? = null
)

data class SummarizeRunParams(
    val runId: String,
    val systemPrompt: String,
    val messages: List<ChatMessage>,
    val model: ModelRef,
    val secrets: Secrets,
    val timeoutMs: Long? = null,
    val maxOutputTokens: Int? = null
)

data class SummarizeRunResult(val text: String)

sealed class KernelEvent {
    abstract val name: String

    data class Context(
        val runId: String,
        val requestId: String,
        val usedTokens: Int
    ) : KernelEvent() {
        override val name = KernelEvents.CONTEXT
    }

    data class Delta(
        val runId: String,
        val messageId: String,
        val delta: String,
        val part: MessagePart = MessagePart.TEXT
    ) : KernelEvent() {
        override val name = KernelEvents.DELTA
    }

    data class ToolPending(
        val runId: String,
        val toolCallId: String,
        val toolName: String,
        val arguments: Map<String, Any?>,
        val mutating: Boolean,
        val action: LocalToolAction,
        val target: String,
        val justification: String? = null,
        val allowAlways: Boolean? = null,
        val details: String? = null
    ) : KernelEvent() {
        override val name = KernelEvents.TOOL_PENDING
    }

    data class ToolStarted(
        val runId: String,
        val toolCallId: String,
        val toolName: String,
        val arguments: Map<String, Any?>
    ) : KernelEvent() {
        override val name = KernelEvents.TOOL_STARTED
    }

    data class ToolDelegate(
        val runId: String,
        val toolCallId: String,
        val toolName: String,
        val arguments: Map<String, Any?>
    ) : KernelEvent() {
        override val name = KernelEvents.TOOL_DELEGATE
    }

    data class ToolCompleted(
        val runId: String,
        val toolCallId: String,
        val toolName: String,
        val ok: Boolean,
        val output: String
    ) : KernelEvent() {
        override val name = KernelEvents.TOOL_COMPLETED
    }

    data class Error(val runId: String, val code: Int, val message: String) : KernelEvent() {
        override val name = KernelEvents.ERROR
    }

    data class Ended(val runId: String, val status: RunEndStatus) : KernelEvent() {
        override val name = KernelEvents.ENDED
    }
}

object KernelEvents {
    const val CONTEXT = "turn.context"
    const val DELTA = "turn.delta"
    const val TOOL_PENDING = "turn.tool.pending"
    const val TOOL_STARTED = "turn.tool.started"
    const val TOOL_DELEGATE = "turn.tool.delegate"
    const val TOOL_COMPLETED = "turn.tool.completed"
    const val ERROR = "turn.error"
    const val ENDED = "turn.ended"
}

interface KernelPort {
    val events: Flow<KernelEvent>
    suspend fun start(params: TurnStartParams)
    suspend fun cancel(runId: String)
    suspend fun approveTool(decision: TurnToolDecision)
    suspend fun denyTool(decision: TurnToolDecision)
    suspend fun provideContext(result: TurnContextResult)
    suspend fun provideToolResult(result: TurnToolResult)
    suspend fun summarize(params: SummarizeRunParams): SummarizeRunResult
    suspend fun cancelSummary(runId: String)
}

enum class PermissionDecision { ALLOW, ASK, DENY }

data class PermissionVerdict(
    val decision: PermissionDecision,
    val target: String,
    val reason: String? = null
)

data class ToolExecutionResult(
    val ok: Boolean,
    val output: String,
    val endTurn: Boolean = false,
    val images: List<ModelImage> = emptyList()
)

/**
 * Kernel-facing tool boundary. The kernel keeps the approval loop and does not
 * touch the filesystem. State is per [runId] after [bind].
 */
interface ToolExecutor {
    fun bind(
        runId: String,
        roots: ToolRoots,
        permission: ToolPermission,
        approvals: List<ToolApproval> = emptyList(),
        refused: List<ToolApproval> = emptyList()
    )

    suspend fun authorize(runId: String, action: LocalToolAction, target: String): PermissionVerdict
    fun grantOnce(runId: String, action: LocalToolAction, target: String)
    fun refuse(runId: String, action: LocalToolAction, target: String)
    fun setPermission(runId: String, permission: ToolPermission)
    suspend fun execute(runId: String, call: ToolCall): ToolExecutionResult
    fun release(runId: String)
}

/** Host-facing file tools. Shell, network, and external_operation return a fixed not-implemented sentence. */
interface ToolBackend : ToolExecutor {
    fun definitions(): List<ToolDefinition>
}

/**
 * Keystore-backed secrets. Encryption failure throws [NuumException] with
 * [DesktopErrorCode.SECRET_STORE] and must not write plaintext.
 */
interface SecretStore {
    suspend fun read(): Secrets
    suspend fun write(secrets: Secrets)
}

/** Settings screen only. Empty or null deletes the key. Never returns plaintext. */
interface SecretWriter {
    suspend fun write(provider: ProviderId, apiKey: String?)
}

fun interface Clock {
    fun nowMillis(): Long
}

/** Local PoC has a null [userId]. Transcript records do not gain a user field. */
interface IdentityContext {
    val userId: String?
}

/** No-op in the PoC. Later sync units are an agent directory and a work timeline, not Room rows. */
interface SyncPort {
    suspend fun pushAgent(agentId: String)
    suspend fun pullAgent(agentId: String)
    suspend fun pushWork(workId: String)
    suspend fun pullWork(workId: String)
}

/** In-process turn lifetime. A later build can move this to a foreground service. */
interface TurnSupervisor {
    fun launch(block: suspend () -> Unit): Job
}

/** Unregistered in the PoC. [collect] returns context refs, never bodies or credentials. */
interface ProactiveSource {
    val id: String
    suspend fun collect(agentId: String): List<String>
}

interface SettingsPort {
    val events: Flow<HostEvent>
    suspend fun get(): PublicSettings
    suspend fun set(patch: SettingsPatch): PublicSettings
}

data class AgentCreateParams(
    val name: String? = null,
    val description: String? = null,
    val tags: List<String>? = null,
    val avatarColor: String? = null,
    val avatarShape: String? = null,
    val avatarMaterial: String? = null,
    val model: ModelRef? = null,
    val workspace: WorkspaceSettings? = null
)

data class AgentUpdateParams(
    val id: String,
    val name: String? = null,
    val description: String? = null,
    val tags: List<String>? = null,
    val avatarColor: String? = null,
    val avatarShape: String? = null,
    val avatarMaterial: String? = null,
    val model: ModelRef? = null,
    val workspace: WorkspaceSettings? = null,
    val execution: ExecutionPreferences? = null,
    val hiddenFromSidebar: Boolean? = null
)

data class AgentSendParams(
    val id: String,
    val content: String,
    val attachments: List<AttachmentUpload> = emptyList()
)

data class AgentAnswerWidgetParams(
    val id: String,
    val messageId: String,
    val value: String
)

data class SendResult(val runId: String, val queued: Boolean)

interface AgentPort {
    val events: Flow<HostEvent>
    suspend fun list(): List<AgentView>
    suspend fun get(id: String): AgentSnapshot
    suspend fun create(params: AgentCreateParams = AgentCreateParams()): AgentView
    suspend fun update(params: AgentUpdateParams): AgentView
    suspend fun delete(id: String)
    suspend fun transcript(query: TranscriptQuery): TranscriptPage
    suspend fun send(params: AgentSendParams): SendResult
    suspend fun answerWidget(params: AgentAnswerWidgetParams): SendResult
    suspend fun cancel(id: String)
    suspend fun approve(id: String, toolCallId: String, resolution: ToolResolution)
    suspend fun deny(id: String, toolCallId: String, resolution: ToolResolution = ToolResolution.DENY)
}

interface WorkPort {
    val events: Flow<HostEvent>
    suspend fun create(params: WorkCreateParams): WorkProfile
    suspend fun list(): List<WorkListItem>
    suspend fun get(id: String): WorkSnapshot
    suspend fun update(params: WorkUpdateParams): WorkProfile
    suspend fun postMessage(params: WorkPostMessageParams): WorkEvent
    suspend fun attachMember(params: WorkMemberAttachParams)
    suspend fun detachMember(params: WorkMemberDetachParams)
    suspend fun moveMember(params: WorkMemberMoveParams)
    suspend fun continueDiscussion(params: WorkContinueParams)
    suspend fun stopDiscussion(workId: String)
    suspend fun taskTranscript(params: WorkTaskTranscriptParams): TranscriptPage
    suspend fun transitionTask(params: WorkTaskTransitionParams): WorkTaskView
    suspend fun dispatch(params: WorkDispatchParams)
    suspend fun addCatalog(params: WorkCatalogAddParams): WorkCatalog
    suspend fun removeCatalog(params: WorkCatalogRemoveParams): WorkCatalog
}

interface ProactivePort {
    val events: Flow<HostEvent>
    suspend fun get(): ProactiveSnapshot
    suspend fun configure(params: ProactiveConfigureParams): ProactiveSnapshot
    suspend fun check(agentId: String): ProactiveSnapshot
}

class PickedFile(
    val name: String,
    val mimeType: String,
    val bytes: ByteArray
)

interface DesktopPort {
    suspend fun pickDirectory(): String?
    suspend fun pickFiles(): List<PickedFile>
    suspend fun openAttachment(path: String)
    suspend fun share(path: String)
}
