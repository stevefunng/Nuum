package com.nuum.agent

import com.nuum.contracts.AgentCreateParams
import com.nuum.contracts.AgentSnapshot
import com.nuum.contracts.AgentUpdateParams
import com.nuum.contracts.AgentView
import com.nuum.contracts.HostErrorCode
import com.nuum.contracts.HostEvent
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NuumException
import com.nuum.contracts.NuumPaths
import com.nuum.contracts.PublicSettings
import com.nuum.contracts.SettingsPatch
import com.nuum.contracts.TranscriptPage
import com.nuum.contracts.TranscriptQuery
import com.nuum.protocol.AgentProfile
import com.nuum.protocol.AgentRuntime
import com.nuum.protocol.AgentSettings
import com.nuum.protocol.AgentStatus
import com.nuum.protocol.DEFAULT_AGENT_NAME
import com.nuum.protocol.ProtocolJson
import com.nuum.protocol.ProtocolParseException
import com.nuum.protocol.Settings
import com.nuum.protocol.TranscriptEvent
import com.nuum.protocol.WorkBinding
import com.nuum.protocol.WorkEvent
import com.nuum.protocol.WorkGrants
import com.nuum.protocol.WorkMembership
import com.nuum.protocol.WorkRole
import com.nuum.protocol.normalizeAgentTags
import com.nuum.protocol.projectAgent
import com.nuum.protocol.resolveAgentAvatarColor
import com.nuum.protocol.rollAgentAvatar
import com.nuum.protocol.secretForProvider
import com.nuum.protocol.validateSidebar
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.builtins.ListSerializer

internal suspend fun HostRuntime.readPublicSettings(): PublicSettings {
    ensureLoaded()
    val secrets = secretStore.read().toProtocol()
    return settings.toPublic(secrets).toContract()
}

internal suspend fun HostRuntime.applySettings(patch: SettingsPatch): PublicSettings {
    ensureLoaded()
    val sidebar = patch.sidebar?.let { raw ->
        try {
            validateSidebar(raw.toProtocol())
        } catch (error: ProtocolParseException) {
            throw NuumException(KernelErrorCode.INVALID, error.message ?: "Invalid sidebar")
        }
    }
    val next = settings.copy(
        defaultToolPermission = patch.defaultToolPermission?.toProtocol() ?: settings.defaultToolPermission,
        defaultModel = patch.defaultModel?.toProtocol() ?: settings.defaultModel,
        theme = patch.theme?.toProtocol() ?: settings.theme,
        language = patch.language?.toProtocol() ?: settings.language,
        sidebar = if (patch.sidebar != null) sidebar else settings.sidebar
    )
    gate.withLock {
        settings = next
        store.writeDoc(NuumPaths.settingsPath(), Settings.serializer(), next)
    }
    val published = readPublicSettings()
    emit(HostEvent.SettingsUpdated(published))
    return published
}

internal suspend fun HostRuntime.listAgents(): List<AgentView> {
    ensureLoaded()
    return gate.withLock { agents.values.map { viewOf(it) } }
}

internal suspend fun HostRuntime.snapshot(id: String): AgentSnapshot {
    ensureLoaded()
    return gate.withLock {
        val record = requireAgent(id)
        val events = store.readTranscript(NuumPaths.transcriptPath(id))
        val live = liveParts[id]?.let {
            com.nuum.protocol.LiveAssistant(it.messageId, it.parts.toList())
        }
        val projection = projectAgent(events, live)
        AgentSnapshot(
            viewOf(record),
            events.map { it.toContract() },
            projection.blocks.map { it.toContract() },
            live?.let { com.nuum.contracts.LiveAssistant(it.messageId, it.parts.map { part -> part.toContractPart() }) }
        )
    }
}

internal suspend fun HostRuntime.createAgent(params: AgentCreateParams): AgentView {
    ensureLoaded()
    return gate.withLock { createAgentLocked(params) }
}

internal suspend fun HostRuntime.createAgentLocked(params: AgentCreateParams): AgentView {
        if (agents.size >= MAX_AGENTS) throw NuumException(KernelErrorCode.INVALID, MAX_AGENTS_MESSAGE)
        val id = ids()
        val now = clock.nowMillis()
        val roll = rollAgentAvatar()
        val color = params.avatarColor?.let { resolveAgentAvatarColor(id, it).id } ?: roll.color
        val profile = AgentProfile(
            id = id,
            name = params.name?.trim()?.ifEmpty { null } ?: DEFAULT_AGENT_NAME,
            description = params.description?.trim().orEmpty(),
            tags = params.tags?.let { normalizeAgentTags(it) } ?: emptyList(),
            avatarColor = color,
            avatarShape = params.avatarShape ?: roll.shape,
            avatarMaterial = params.avatarMaterial ?: roll.material,
            createdAt = now
        )
        val agentSettings = AgentSettings(
            model = params.model?.toProtocol() ?: settings.defaultModel,
            workspace = params.workspace?.toProtocol()
        )
        store.writeDoc(NuumPaths.profilePath(id), AgentProfile.serializer(), profile)
        store.writeDoc(NuumPaths.agentSettingsPath(id), AgentSettings.serializer(), agentSettings)
        val record = AgentRecord(profile, agentSettings, 0, now, 0)
        agents[id] = record
        val view = viewOf(record)
        emit(HostEvent.AgentUpdated(view))
        return view
}

internal suspend fun HostRuntime.updateAgent(params: AgentUpdateParams): AgentView {
    ensureLoaded()
    return gate.withLock {
        val record = requireAgent(params.id)
        val tags = params.tags?.let { normalizeAgentTags(it) }
        record.profile = record.profile.copy(
            name = params.name?.trim() ?: record.profile.name,
            description = params.description?.trim() ?: record.profile.description,
            tags = tags ?: record.profile.tags,
            avatarColor = params.avatarColor ?: record.profile.avatarColor,
            avatarShape = params.avatarShape ?: record.profile.avatarShape,
            avatarMaterial = params.avatarMaterial ?: record.profile.avatarMaterial
        )
        record.settings = record.settings.copy(
            model = params.model?.toProtocol() ?: record.settings.model,
            workspace = params.workspace?.toProtocol() ?: record.settings.workspace,
            execution = params.execution?.toProtocol() ?: record.settings.execution,
            hiddenFromSidebar = params.hiddenFromSidebar ?: record.settings.hiddenFromSidebar
        )
        store.writeDoc(NuumPaths.profilePath(params.id), AgentProfile.serializer(), record.profile)
        store.writeDoc(NuumPaths.agentSettingsPath(params.id), AgentSettings.serializer(), record.settings)
        val view = viewOf(record)
        emit(HostEvent.AgentUpdated(view))
        view
    }
}

internal suspend fun HostRuntime.deleteAgent(id: String) {
    ensureLoaded()
    cancelAgent(id)
    gate.withLock {
        if (agents.remove(id) == null) throw NuumException(HostErrorCode.AGENT_NOT_FOUND, "Agent not found")
        wakes.drop(id)
        store.delete(NuumPaths.agentDir(id))
    }
}

internal suspend fun HostRuntime.readTranscriptPage(query: TranscriptQuery): TranscriptPage {
    ensureLoaded()
    return gate.withLock {
        requireAgent(query.id)
        val events = store.readTranscript(NuumPaths.transcriptPath(query.id))
        val before = query.beforeSeq
        val limit = query.limit
        val filtered = events.filter { before == null || it.seq < before }
        val slice = if (limit == null) filtered else filtered.takeLast(limit)
        val next = if (slice.size < filtered.size) slice.firstOrNull()?.seq else null
        val last = events.maxOfOrNull { it.seq } ?: 0
        agents[query.id]?.readCursor = last
        store.writeDoc(NuumPaths.readCursorPath(query.id), ReadCursor.serializer(), ReadCursor(last))
        TranscriptPage(query.id, slice.map { it.toContract() }, next)
    }
}

internal fun HostRuntime.requireAgent(id: String): AgentRecord =
    agents[id] ?: throw NuumException(HostErrorCode.AGENT_NOT_FOUND, "Agent not found")

internal fun HostRuntime.viewOf(record: AgentRecord): AgentView {
    val active = scheduler.activeRunFor(record.profile.id)
    val status = when {
        active != null -> AgentStatus.RUNNING
        record.profile.id in errored -> AgentStatus.ERROR
        else -> AgentStatus.IDLE
    }
    val runtime = AgentRuntime(
        activeRunId = active,
        status = status,
        unread = record.lastSeq > record.readCursor,
        lastActivityAt = record.lastActivityAt
    )
    return CAgentView(record.profile, record.settings, runtime, roomsFor(record.profile.id))
}

internal fun HostRuntime.roomsFor(agentId: String): Map<String, WorkMembership> =
    memberships.mapNotNull { (workId, members) ->
        val membership = members[agentId] ?: return@mapNotNull null
        if (membership.binding == null) null else workId to membership
    }.toMap()

internal fun HostRuntime.membershipOf(workId: String, agentId: String): WorkMembership =
    memberships[workId]?.get(agentId) ?: WorkMembership(0, null)

internal fun HostRuntime.applyMembership(event: WorkEvent) {
    when (event) {
        is WorkEvent.MemberAttached -> {
            val members = memberships.getOrPut(event.workId) { LinkedHashMap() }
            members[event.agentId] = WorkMembership(
                event.membershipRevision,
                WorkBinding(event.workId, event.role, event.createdAt, grantsFor(event.role))
            )
        }
        is WorkEvent.MemberDetached -> {
            val members = memberships.getOrPut(event.workId) { LinkedHashMap() }
            members[event.agentId] = WorkMembership(event.membershipRevision, null)
        }
        else -> Unit
    }
}

internal fun grantsFor(role: WorkRole): WorkGrants = when (role) {
    WorkRole.COORDINATOR -> WorkGrants(true, true, true, true)
    WorkRole.WORKER -> WorkGrants(true, true, false, false)
    WorkRole.OBSERVER -> WorkGrants(false, false, false, false)
}

internal suspend fun HostRuntime.claimReceipts(agentId: String, events: List<TranscriptEvent>) {
    val path = "${NuumPaths.agentDir(agentId)}/execution-receipts.json"
    val receipts = store.readReceipts(path)
    if (receipts.isEmpty()) return
    var current = events
    for (receipt in receipts) {
        val claimed = claimExecutionResult(current, receipt, clock.nowMillis(), ids)
        for (event in claimed) {
            store.appendTranscript(NuumPaths.transcriptPath(agentId), event)
            current = current + event
        }
    }
    store.writeTextAtomic(path, ProtocolJson.encodeToString(ListSerializer(ExecutionReceipt.serializer()), emptyList()) + "\n")
    agents[agentId]?.let { record ->
        record.lastSeq = current.maxOfOrNull { it.seq } ?: record.lastSeq
        record.lastActivityAt = current.maxOfOrNull { it.createdAt } ?: record.lastActivityAt
    }
}

internal fun Settings.toPublic(secrets: com.nuum.protocol.Secrets) = com.nuum.protocol.PublicSettings(
    defaultToolPermission = defaultToolPermission,
    defaultModel = defaultModel,
    theme = theme,
    language = language,
    sidebar = sidebar,
    hasOpenaiKey = !secretForProvider(secrets, com.nuum.protocol.ProviderId.OPENAI).isNullOrEmpty(),
    hasAnthropicKey = !secretForProvider(secrets, com.nuum.protocol.ProviderId.ANTHROPIC).isNullOrEmpty(),
    hasDeepseekKey = !secretForProvider(secrets, com.nuum.protocol.ProviderId.DEEPSEEK).isNullOrEmpty()
)

private fun com.nuum.protocol.AssistantPart.toContractPart(): com.nuum.contracts.AssistantPart = when (this) {
    is com.nuum.protocol.AssistantPart.Thinking -> com.nuum.contracts.AssistantPart.Thinking(text)
    is com.nuum.protocol.AssistantPart.Text -> com.nuum.contracts.AssistantPart.Text(text)
    is com.nuum.protocol.AssistantPart.ToolCall ->
        com.nuum.contracts.AssistantPart.ToolCallPart(id, name, arguments.toArgs(), executionId)
}

internal fun deriveName(content: String): String {
    val line = content.replace(Regex("\\s+"), " ").trim()
    if (line.isEmpty()) return DEFAULT_AGENT_NAME
    return if (line.length <= 42) line else line.take(41) + "…"
}
