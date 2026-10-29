package com.nuum.agent

import com.nuum.contracts.AgentAnswerWidgetParams
import com.nuum.contracts.AgentCreateParams
import com.nuum.contracts.AgentPort
import com.nuum.contracts.AgentSendParams
import com.nuum.contracts.AgentSnapshot
import com.nuum.contracts.AgentStore
import com.nuum.contracts.AgentUpdateParams
import com.nuum.contracts.AgentView
import com.nuum.contracts.Clock
import com.nuum.contracts.HostEvent
import com.nuum.contracts.KernelPort
import com.nuum.contracts.ProactiveConfigureParams
import com.nuum.contracts.ProactivePort
import com.nuum.contracts.ProactiveSnapshot
import com.nuum.contracts.PublicSettings
import com.nuum.contracts.SecretStore
import com.nuum.contracts.SendResult
import com.nuum.contracts.SettingsPatch
import com.nuum.contracts.SettingsPort
import com.nuum.contracts.ToolBackend
import com.nuum.contracts.ToolResolution
import com.nuum.contracts.TranscriptPage
import com.nuum.contracts.TranscriptQuery
import com.nuum.contracts.TurnSupervisor
import com.nuum.contracts.WorkCatalog
import com.nuum.contracts.WorkCatalogAddParams
import com.nuum.contracts.WorkCatalogRemoveParams
import com.nuum.contracts.WorkContinueParams
import com.nuum.contracts.WorkCreateParams
import com.nuum.contracts.WorkDispatchParams
import com.nuum.contracts.WorkEvent
import com.nuum.contracts.WorkListItem
import com.nuum.contracts.WorkMemberAttachParams
import com.nuum.contracts.WorkMemberDetachParams
import com.nuum.contracts.WorkMemberMoveParams
import com.nuum.contracts.WorkPort
import com.nuum.contracts.WorkPostMessageParams
import com.nuum.contracts.WorkSnapshot
import com.nuum.contracts.WorkTaskTranscriptParams
import com.nuum.contracts.WorkTaskTransitionParams
import com.nuum.contracts.WorkTaskView
import com.nuum.contracts.WorkUpdateParams
import com.nuum.protocol.AgentProfile
import com.nuum.protocol.AgentSettings
import com.nuum.protocol.DEFAULT_SETTINGS
import com.nuum.protocol.Settings
import com.nuum.protocol.WorkMembership
import com.nuum.protocol.WorkProfile
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Host for the Android PoC. Scheduling, wakes, prompts, memory, compaction,
 * transcript projection, delegated tools, room limits, and proactive snapshots
 * live here. Model calls go through [KernelPort]. Secrets are read from
 * [SecretStore] at the start of a turn and are not written back.
 *
 * Status is derived from the in-memory scheduler. A new instance is idle even
 * when the transcript holds an unfinished wake.
 *
 * The four ports are facades. `get` and `list` collide across Settings, Agent,
 * Work, and Proactive, so one class cannot override all four interfaces.
 */
class HostRuntime(
    internal val store: AgentStore,
    internal val kernel: KernelPort,
    internal val secretStore: SecretStore,
    internal val tools: ToolBackend,
    internal val clock: Clock,
    internal val supervisor: TurnSupervisor,
    internal val nuumRoot: String,
    internal val osLabel: String,
    internal val timeZone: String = "UTC",
    internal val contextWindowTokens: Int = DEFAULT_CONTEXT_WINDOW,
    internal val deniedRoots: List<String> = emptyList(),
    internal val ids: () -> String = { java.util.UUID.randomUUID().toString() }
) {
    private val _events = MutableSharedFlow<HostEvent>(extraBufferCapacity = 256)
    internal val events: Flow<HostEvent> = _events.asSharedFlow()

    val settingsPort: SettingsPort = object : SettingsPort {
        override val events: Flow<HostEvent> get() = this@HostRuntime.events
        override suspend fun get(): PublicSettings = this@HostRuntime.readPublicSettings()
        override suspend fun set(patch: SettingsPatch): PublicSettings = this@HostRuntime.applySettings(patch)
    }

    val agentPort: AgentPort = object : AgentPort {
        override val events: Flow<HostEvent> get() = this@HostRuntime.events
        override suspend fun list(): List<AgentView> = this@HostRuntime.listAgents()
        override suspend fun get(id: String): AgentSnapshot = this@HostRuntime.snapshot(id)
        override suspend fun create(params: AgentCreateParams): AgentView = this@HostRuntime.createAgent(params)
        override suspend fun update(params: AgentUpdateParams): AgentView = this@HostRuntime.updateAgent(params)
        override suspend fun delete(id: String) = this@HostRuntime.deleteAgent(id)
        override suspend fun transcript(query: TranscriptQuery): TranscriptPage = this@HostRuntime.readTranscriptPage(query)
        override suspend fun send(params: AgentSendParams): SendResult = this@HostRuntime.performSend(params)
        override suspend fun answerWidget(params: AgentAnswerWidgetParams): SendResult =
            this@HostRuntime.performSend(AgentSendParams(params.id, params.value), params.messageId)
        override suspend fun cancel(id: String) = this@HostRuntime.cancelAgent(id)
        override suspend fun approve(id: String, toolCallId: String, resolution: ToolResolution) =
            this@HostRuntime.resolveTool(id, toolCallId, resolution, allow = true)
        override suspend fun deny(id: String, toolCallId: String, resolution: ToolResolution) =
            this@HostRuntime.resolveTool(id, toolCallId, resolution, allow = false)
    }

    val workPort: WorkPort = object : WorkPort {
        override val events: Flow<HostEvent> get() = this@HostRuntime.events
        override suspend fun create(params: WorkCreateParams): com.nuum.contracts.WorkProfile = this@HostRuntime.createWork(params)
        override suspend fun list(): List<WorkListItem> = this@HostRuntime.listWorkItems()
        override suspend fun get(id: String): WorkSnapshot = this@HostRuntime.workSnapshot(id)
        override suspend fun update(params: WorkUpdateParams): com.nuum.contracts.WorkProfile = this@HostRuntime.updateWork(params)
        override suspend fun postMessage(params: WorkPostMessageParams): WorkEvent = this@HostRuntime.postWorkMessage(params)
        override suspend fun attachMember(params: WorkMemberAttachParams) = this@HostRuntime.attach(params)
        override suspend fun detachMember(params: WorkMemberDetachParams) = this@HostRuntime.detach(params)
        override suspend fun moveMember(params: WorkMemberMoveParams) = this@HostRuntime.move(params)
        override suspend fun continueDiscussion(params: WorkContinueParams) = this@HostRuntime.continueRoom(params)
        override suspend fun stopDiscussion(workId: String) = this@HostRuntime.stopRoom(workId)
        override suspend fun taskTranscript(params: WorkTaskTranscriptParams): TranscriptPage = this@HostRuntime.readTaskTranscript(params)
        override suspend fun transitionTask(params: WorkTaskTransitionParams): WorkTaskView = this@HostRuntime.transition(params)
        override suspend fun dispatch(params: WorkDispatchParams) = this@HostRuntime.dispatchWork(params)
        override suspend fun addCatalog(params: WorkCatalogAddParams): WorkCatalog = this@HostRuntime.addCatalogEntry(params)
        override suspend fun removeCatalog(params: WorkCatalogRemoveParams): WorkCatalog = this@HostRuntime.removeCatalogEntry(params)
    }

    val proactivePort: ProactivePort = object : ProactivePort {
        override val events: Flow<HostEvent> get() = this@HostRuntime.events
        override suspend fun get(): ProactiveSnapshot = this@HostRuntime.proactiveSnapshot()
        override suspend fun configure(params: ProactiveConfigureParams): ProactiveSnapshot = this@HostRuntime.configureProactive(params)
        override suspend fun check(agentId: String): ProactiveSnapshot = this@HostRuntime.checkProactive(agentId)
    }

    internal val gate = Mutex()
    internal val scheduler = AgentScheduler(supervisor, newRunId = ids)
    internal val wakes = WakeQueue { clock.nowMillis() }
    internal val agents = LinkedHashMap<String, AgentRecord>()
    internal val works = LinkedHashMap<String, WorkRecord>()
    internal val memberships = LinkedHashMap<String, LinkedHashMap<String, WorkMembership>>()
    internal val discussions = LinkedHashMap<String, LiveDiscussion>()
    internal val discussionQueues = LinkedHashMap<String, ArrayDeque<String>>()
    internal val discussionJobs = LinkedHashMap<String, Job>()
    internal val errored = mutableSetOf<String>()
    internal val liveParts = LinkedHashMap<String, LiveBuffer>()

    /**
     * Pending local-tool approvals, keyed by agent and tool-call id.
     * Filled from `turn.tool.pending` (action + canonical target), which is what
     * Mac stores. Write arguments do not carry `action`, and the call is not in
     * [liveParts] until after the user decides.
     */
    internal val pendingApprovals = ConcurrentHashMap<String, com.nuum.protocol.ToolApproval>()
    internal val pendingImages = LinkedHashMap<String, List<com.nuum.protocol.ModelImage>>()
    internal var settings: Settings = DEFAULT_SETTINGS
    internal var loaded = false
    private var collector: Job? = null

    suspend fun start() {
        ensureLoaded()
        if (collector == null) {
            collector = supervisor.launch {
                kernel.events.collect { event -> onKernel(event) }
            }
        }
    }

    fun close() {
        collector?.cancel()
        scheduler.close()
    }

    internal fun emit(event: HostEvent) {
        _events.tryEmit(event)
    }

    internal suspend fun ensureLoaded() {
        if (loaded) return
        gate.withLock {
            if (loaded) return@withLock
            loadBody()
            loaded = true
        }
    }

    private suspend fun loadBody() {
        settings = store.readDoc(com.nuum.contracts.NuumPaths.settingsPath(), Settings.serializer()) ?: DEFAULT_SETTINGS
        if (store.exists("agents")) {
            for (id in store.list("agents")) {
                val profile = store.readDoc(com.nuum.contracts.NuumPaths.profilePath(id), AgentProfile.serializer()) ?: continue
                val agentSettings = store.readDoc(com.nuum.contracts.NuumPaths.agentSettingsPath(id), AgentSettings.serializer())
                    ?: AgentSettings(model = settings.defaultModel)
                val events = store.readTranscript(com.nuum.contracts.NuumPaths.transcriptPath(id))
                val cursor = store.readDoc(com.nuum.contracts.NuumPaths.readCursorPath(id), ReadCursor.serializer())?.seq ?: 0
                agents[id] = AgentRecord(
                    profile,
                    agentSettings,
                    events.maxOfOrNull { it.seq } ?: 0,
                    events.maxOfOrNull { it.createdAt } ?: profile.createdAt,
                    cursor
                )
                pendingWake(events)?.let { wakes.enqueue(id, it) }
                claimReceipts(id, events)
            }
        }
        if (store.exists("works")) {
            for (id in store.list("works")) {
                val profile = store.readDoc(com.nuum.contracts.NuumPaths.workProfilePath(id), WorkProfile.serializer()) ?: continue
                val events = store.readWorkEvents(com.nuum.contracts.NuumPaths.workTimelinePath(id))
                events.forEach { applyMembership(it) }
                works[id] = WorkRecord(
                    profile,
                    events.maxOfOrNull { it.seq } ?: 0,
                    maxOf(profile.createdAt, events.maxOfOrNull { it.createdAt } ?: 0)
                )
            }
        }
    }
}

internal class AgentRecord(
    var profile: AgentProfile,
    var settings: AgentSettings,
    var lastSeq: Int,
    var lastActivityAt: Long,
    var readCursor: Int
)

internal class WorkRecord(
    var profile: WorkProfile,
    var lastSeq: Int,
    var lastActivityAt: Long
)

internal class LiveDiscussion(
    val id: String,
    val triggers: List<String>,
    var stopped: Boolean = false,
    var superseded: Boolean = false,
    var total: Int = 0,
    val perExecution: MutableMap<String, Int> = mutableMapOf(),
    val replies: MutableList<MentionedMessage> = mutableListOf(),
    var runId: String? = null
)

internal class LiveBuffer(
    val messageId: String,
    val parts: MutableList<com.nuum.protocol.AssistantPart>
)

@kotlinx.serialization.Serializable
internal data class ReadCursor(val seq: Int)

@kotlinx.serialization.Serializable
internal data class ApprovalFile(
    val always: List<com.nuum.protocol.ToolApproval> = emptyList(),
    val refused: List<com.nuum.protocol.ToolApproval> = emptyList()
)

@kotlinx.serialization.Serializable
internal data class PromptCache(
    val epoch: Int = 0,
    val profileRender: String? = null,
    val identityName: String? = null,
    val identityDescription: String? = null,
    val identityTags: List<String> = emptyList(),
    val memory: String? = null
)
