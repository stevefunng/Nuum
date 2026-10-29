package com.nuum.agent

import com.nuum.contracts.AgentProfile as CAgentProfile
import com.nuum.contracts.AgentRuntime as CAgentRuntime
import com.nuum.contracts.AgentSettings as CAgentSettings
import com.nuum.contracts.AgentStatus as CAgentStatus
import com.nuum.contracts.AgentView as CAgentView
import com.nuum.contracts.AssistantPart as CAssistantPart
import com.nuum.contracts.ChatMessage as CChatMessage
import com.nuum.contracts.CommandGrant as CCommandGrant
import com.nuum.contracts.CommandPermission as CCommandPermission
import com.nuum.contracts.ExecutionPreferences as CExecutionPreferences
import com.nuum.contracts.Language as CLanguage
import com.nuum.contracts.LocalToolAction as CLocalToolAction
import com.nuum.contracts.MessageRole as CMessageRole
import com.nuum.contracts.ModelImage as CModelImage
import com.nuum.contracts.ModelRef as CModelRef
import com.nuum.contracts.NetworkGrant as CNetworkGrant
import com.nuum.contracts.OutboundMessage as COutbound
import com.nuum.contracts.ProactiveActivity as CProactiveActivity
import com.nuum.contracts.ProactiveAgentSnapshot as CProactiveAgentSnapshot
import com.nuum.contracts.ProactivePolicy as CProactivePolicy
import com.nuum.contracts.ProactiveSnapshot as CProactiveSnapshot
import com.nuum.contracts.ProviderId as CProviderId
import com.nuum.contracts.PublicSettings as CPublicSettings
import com.nuum.contracts.Secrets as CSecrets
import com.nuum.contracts.Settings as CSettings
import com.nuum.contracts.SidebarOrganization as CSidebar
import com.nuum.contracts.SidebarSection as CSidebarSection
import com.nuum.contracts.ThemePreference as CTheme
import com.nuum.contracts.ToolApproval as CToolApproval
import com.nuum.contracts.ToolCall as CToolCall
import com.nuum.contracts.ToolDefinition as CToolDefinition
import com.nuum.contracts.ToolPermission as CToolPermission
import com.nuum.contracts.TranscriptEvent as CTranscriptEvent
import com.nuum.contracts.UserAttachment as CUserAttachment
import com.nuum.contracts.ViewBlock as CViewBlock
import com.nuum.contracts.WakeSource as CWakeSource
import com.nuum.contracts.WidgetOption as CWidgetOption
import com.nuum.contracts.WidgetPayload as CWidgetPayload
import com.nuum.contracts.WorkActor as CWorkActor
import com.nuum.contracts.WorkBinding as CWorkBinding
import com.nuum.contracts.WorkBlocker as CWorkBlocker
import com.nuum.contracts.WorkCatalog as CWorkCatalog
import com.nuum.contracts.WorkCatalogEntry as CCatalogEntry
import com.nuum.contracts.WorkDeliverable as CDeliverable
import com.nuum.contracts.WorkEvent as CWorkEvent
import com.nuum.contracts.WorkEventBody as CWorkBody
import com.nuum.contracts.WorkGrants as CWorkGrants
import com.nuum.contracts.WorkKind as CWorkKind
import com.nuum.contracts.WorkMembership as CWorkMembership
import com.nuum.contracts.WorkProfile as CWorkProfile
import com.nuum.contracts.WorkRole as CWorkRole
import com.nuum.contracts.WorkTask as CWorkTask
import com.nuum.contracts.WorkTaskPriority as CPriority
import com.nuum.contracts.WorkTaskState as CTaskState
import com.nuum.contracts.WorkspaceSettings as CWorkspace
import com.nuum.protocol.AgentProfile as PAgentProfile
import com.nuum.protocol.AgentRuntime as PAgentRuntime
import com.nuum.protocol.AgentSettings as PAgentSettings
import com.nuum.protocol.AgentStatus as PAgentStatus
import com.nuum.protocol.ChatMessage as PChatMessage
import com.nuum.protocol.ExecutionPreferences as PExecutionPreferences
import com.nuum.protocol.Language as PLanguage
import com.nuum.protocol.LocalToolAction as PLocalToolAction
import com.nuum.protocol.MessageRole as PMessageRole
import com.nuum.protocol.ModelRef as PModelRef
import com.nuum.protocol.OutboundMessage as POutbound
import com.nuum.protocol.ProactiveActivity as PProactiveActivity
import com.nuum.protocol.ProactiveAgentSnapshot as PProactiveAgent
import com.nuum.protocol.ProactivePolicy as PProactivePolicy
import com.nuum.protocol.ProactiveSnapshot as PProactiveSnapshot
import com.nuum.protocol.ProviderId as PProviderId
import com.nuum.protocol.PublicSettings as PPublicSettings
import com.nuum.protocol.Secrets as PSecrets
import com.nuum.protocol.Settings as PSettings
import com.nuum.protocol.SidebarOrganization as PSidebar
import com.nuum.protocol.ThemePreference as PTheme
import com.nuum.protocol.ToolApproval as PToolApproval
import com.nuum.protocol.ToolDefinition as PToolDefinition
import com.nuum.protocol.ToolPermission as PToolPermission
import com.nuum.protocol.TranscriptEvent as PTranscriptEvent
import com.nuum.protocol.ViewBlock as PViewBlock
import com.nuum.protocol.WakeSource as PWakeSource
import com.nuum.protocol.WorkActor as PWorkActor
import com.nuum.protocol.WorkCatalog as PWorkCatalog
import com.nuum.protocol.WorkCatalogEntry as PCatalogEntry
import com.nuum.protocol.WorkEvent as PWorkEvent
import com.nuum.protocol.WorkKind as PWorkKind
import com.nuum.protocol.WorkMembership as PWorkMembership
import com.nuum.protocol.WorkProfile as PWorkProfile
import com.nuum.protocol.WorkRole as PWorkRole
import com.nuum.protocol.WorkTask as PWorkTask
import com.nuum.protocol.WorkTaskPriority as PPriority
import com.nuum.protocol.WorkTaskState as PTaskState
import com.nuum.protocol.WorkspaceSettings as PWorkspace
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

internal fun PProviderId.toContract(): CProviderId = CProviderId.valueOf(name)
internal fun CProviderId.toProtocol(): PProviderId = PProviderId.valueOf(name)
internal fun PProviderId.wire(): String = toContract().wire

internal fun PModelRef.toContract() = CModelRef(provider.toContract(), model)
internal fun CModelRef.toProtocol() = PModelRef(provider.toProtocol(), model)

internal fun PSecrets.toContract() = CSecrets(openaiApiKey, anthropicApiKey, deepseekApiKey)
internal fun CSecrets.toProtocol() = PSecrets(openaiApiKey, anthropicApiKey, deepseekApiKey)

internal fun PToolPermission.toContract() = CToolPermission.valueOf(name)
internal fun CToolPermission.toProtocol() = PToolPermission.valueOf(name)
internal fun PTheme.toContract() = CTheme.valueOf(name)
internal fun CTheme.toProtocol() = PTheme.valueOf(name)
internal fun PLanguage.toContract() = CLanguage.valueOf(name)
internal fun CLanguage.toProtocol() = PLanguage.valueOf(name)
internal fun PLocalToolAction.toContract() = CLocalToolAction.valueOf(name)
internal fun CLocalToolAction.toProtocol() = PLocalToolAction.valueOf(name)
internal fun PMessageRole.toContract() = CMessageRole.valueOf(name)
internal fun PAgentStatus.toContract() = CAgentStatus.valueOf(name)
internal fun PWorkKind.toContract() = CWorkKind.valueOf(name)
internal fun CWorkKind.toProtocol() = PWorkKind.valueOf(name)
internal fun PWorkRole.toContract() = CWorkRole.valueOf(name)
internal fun CWorkRole.toProtocol() = PWorkRole.valueOf(name)
internal fun PTaskState.toContract() = CTaskState.valueOf(name)
internal fun CTaskState.toProtocol() = PTaskState.valueOf(name)
internal fun PPriority.toContract() = CPriority.valueOf(name)

internal fun PSidebar.toContract() = CSidebar(
    pinnedAgentIds,
    sections.map { CSidebarSection(it.id, it.name, it.agentIds, it.isCollapsed == true) }
)

internal fun CSidebar.toProtocol() = PSidebar(
    pinnedAgentIds,
    sections.map {
        com.nuum.protocol.SidebarSection(it.id, it.name, it.agentIds, it.isCollapsed)
    }
)

internal fun PSettings.toContract() = CSettings(
    defaultToolPermission.toContract(),
    defaultModel.toContract(),
    theme.toContract(),
    language?.toContract() ?: CLanguage.ZH_CN,
    sidebar?.toContract()
)

internal fun CSettings.toProtocol() = PSettings(
    defaultToolPermission.toProtocol(),
    defaultModel.toProtocol(),
    theme.toProtocol(),
    language.toProtocol(),
    sidebar?.toProtocol()
)

internal fun PPublicSettings.toContract() = CPublicSettings(
    defaultToolPermission.toContract(),
    defaultModel.toContract(),
    theme.toContract(),
    hasOpenaiKey,
    hasAnthropicKey,
    hasDeepseekKey,
    language?.toContract() ?: CLanguage.ZH_CN,
    sidebar?.toContract()
)

internal fun PWorkspace.toContract() = CWorkspace(projectRoot, toolPermission?.toContract())
internal fun CWorkspace.toProtocol() = PWorkspace(projectRoot, toolPermission?.toProtocol())

internal fun PExecutionPreferences.toContract() = CExecutionPreferences(
    workspaceId,
    when (commands.name) {
        "ALWAYS" -> CCommandPermission.ALWAYS
        "NEVER" -> CCommandPermission.NEVER
        else -> CCommandPermission.ASK
    },
    commandGrants.map { CCommandGrant(it.workspaceId, it.command) },
    networkGrants.map { CNetworkGrant(it.workspaceId, it.target) }
)

internal fun CExecutionPreferences.toProtocol() = PExecutionPreferences(
    workspaceId = workspaceId,
    commands = com.nuum.protocol.CommandPermission.valueOf(commands.name),
    commandGrants = commandGrants.map { com.nuum.protocol.CommandGrant(it.workspaceId, it.command) },
    networkGrants = networkGrants.map { com.nuum.protocol.NetworkGrant(it.workspaceId, it.target) }
)

internal fun PProactivePolicy.toContract() = CProactivePolicy(
    revision, isDefault, enabled, pausedUntil, sourceIds, intervalMs
)

internal fun CProactivePolicy.toProtocol() = PProactivePolicy(
    revision, isDefault, enabled, pausedUntil, sourceIds, intervalMs
)

internal fun PWorkMembership.toContract() = CWorkMembership(
    revision,
    binding?.let {
        CWorkBinding(
            it.workId,
            it.role.toContract(),
            it.joinedAt,
            CWorkGrants(it.grants.canPost, it.grants.canManageOwnTasks, it.grants.canAssignTasks, it.grants.canEditCatalog)
        )
    }
)

internal fun PAgentProfile.toContract() = CAgentProfile(
    id, name, description, createdAt, tags ?: emptyList(), avatarColor, avatarShape, avatarMaterial
)

internal fun PAgentSettings.toContract(room: CWorkMembership? = workMembership?.toContract()) = CAgentSettings(
    model.toContract(),
    execution?.toContract(),
    workspace?.toContract(),
    hiddenFromSidebar == true,
    proactive?.toContract(),
    room
)

internal fun PAgentRuntime.toContract() = CAgentRuntime(status.toContract(), unread, lastActivityAt, activeRunId)

internal fun CAgentView(
    profile: PAgentProfile,
    settings: PAgentSettings,
    runtime: PAgentRuntime,
    rooms: Map<String, PWorkMembership>
) = CAgentView(
    profile.toContract(),
    settings.toContract(),
    runtime.toContract(),
    rooms.mapValues { it.value.toContract() }
)

internal fun PChatMessage.toContract() = CChatMessage(
    id = id,
    role = role.toContract(),
    content = content,
    seq = seq,
    createdAt = createdAt,
    images = images?.map { CModelImage(it.mimeType, it.data) },
    thinking = thinking,
    toolCalls = toolCalls?.map { CToolCall(it.id, it.name, it.arguments.toArgs()) },
    toolCallId = toolCallId,
    name = name
)

internal fun PToolDefinition.toContract() = CToolDefinition(
    name, description, inputSchema.toArgs(), mutating, action?.toContract()
)

internal fun PToolApproval.toContract() = CToolApproval(action.toContract(), target)

internal fun PTranscriptEvent.toContract(): CTranscriptEvent = when (this) {
    is PTranscriptEvent.User -> CTranscriptEvent.User(
        id, seq, createdAt, text,
        attachments.orEmpty().map { CUserAttachment(it.name, it.path, it.mimeType, it.size, it.text) },
        widgetAnswerTo
    )
    is PTranscriptEvent.Wake -> CTranscriptEvent.Wake(id, seq, createdAt, source.toContract(), text, hops)
    is PTranscriptEvent.Assistant -> CTranscriptEvent.Assistant(id, seq, createdAt, parts.map { it.toContract() })
    is PTranscriptEvent.Tool -> CTranscriptEvent.Tool(id, seq, createdAt, toolCallId, name, content, assistantId, ok, spillPath)
    is PTranscriptEvent.Message -> CTranscriptEvent.Message(id, seq, createdAt, payload.toContract(), assistantId, toolCallId)
    is PTranscriptEvent.Compact -> CTranscriptEvent.Compact(id, seq, createdAt, epoch, throughSeq, tailFromSeq, summary)
    is PTranscriptEvent.Profile -> CTranscriptEvent.Profile(id, seq, createdAt, patch.name, patch.description, patch.tags)
}

private fun com.nuum.protocol.AssistantPart.toContract(): CAssistantPart = when (this) {
    is com.nuum.protocol.AssistantPart.Thinking -> CAssistantPart.Thinking(text)
    is com.nuum.protocol.AssistantPart.Text -> CAssistantPart.Text(text)
    is com.nuum.protocol.AssistantPart.ToolCall -> CAssistantPart.ToolCallPart(id, name, arguments.toArgs(), executionId)
}

private fun PWakeSource.toContract(): CWakeSource = when (this) {
    is PWakeSource.Agent -> CWakeSource.Agent(fromId, fromName, priority == true)
    is PWakeSource.Work -> CWakeSource.Work(workId, workName, bridgeId, taskId)
    is PWakeSource.Routine -> CWakeSource.Routine(routineId, routineName)
}

private fun POutbound.toContract(): COutbound = when (this) {
    is POutbound.Text -> COutbound.Text(content, images.orEmpty().map { com.nuum.contracts.OutboundImage(it.path, it.alt) })
    is POutbound.Attachment -> COutbound.Attachment(path, caption)
    is POutbound.Widget -> COutbound.Widget(
        CWidgetPayload(
            widget.prompt,
            widget.options.map { CWidgetOption(it.label, it.value, it.description, it.style?.name?.lowercase()) },
            widget.helpText,
            widget.allowCustom == true
        )
    )
    is POutbound.LegacyWidget -> COutbound.LegacyWidget(widget, props?.toArgs() ?: emptyMap())
}

internal fun PViewBlock.toContract(): CViewBlock = when (this) {
    is PViewBlock.User -> CViewBlock.User(
        id, text,
        attachments.orEmpty().map { CUserAttachment(it.name, it.path, it.mimeType, it.size, it.text) },
        widgetAnswerTo
    )
    is PViewBlock.Assistant -> CViewBlock.Assistant(
        id, thinking,
        tools.map {
            com.nuum.contracts.ToolView(it.id, it.name, it.arguments.toArgs(), it.output, it.status.name.lowercase())
        },
        live == true
    )
    is PViewBlock.Message -> CViewBlock.Message(id, payload.toContract())
    is PViewBlock.Peer -> CViewBlock.Peer(id, direction.name.lowercase(), agentId, agentName, text, priority)
    is PViewBlock.Notice -> CViewBlock.Notice(id, kind.name.lowercase(), text)
}

internal fun PWorkProfile.toContract() = CWorkProfile(
    id, name, description, projectRoot, createdAt, kind?.toContract(), avatar, workspaceId
)

internal fun PWorkTask.toContract() = CWorkTask(
    id, title, description, acceptanceCriteria, state.toContract(), assigneeIds, dependencyIds,
    priority.toContract(), revision,
    deliverables.map { CDeliverable(it.id, it.name, it.uri, it.createdAt, it.mimeType) },
    createdAt, updatedAt, ownerAgentId,
    blocker?.let { CWorkBlocker(it.reason, it.ownerId, it.resumeCondition, it.createdAt) }
)

internal fun PWorkCatalog.toContract() = CWorkCatalog(revision, entries.map { it.toContract() })

private fun PCatalogEntry.toContract(): CCatalogEntry = when (this) {
    is PCatalogEntry.Skill -> CCatalogEntry.Skill(id, name, description, enabled, manifestPath)
    is PCatalogEntry.Cli -> CCatalogEntry.Cli(id, name, description, enabled, executable, allowedSubcommands)
    is PCatalogEntry.Knowledge -> CCatalogEntry.Knowledge(id, name, description, enabled, roots, readOnly)
    is PCatalogEntry.LocalTool -> CCatalogEntry.LocalTool(id, name, description, enabled, toolNames)
}

internal fun PWorkEvent.toContract(): CWorkEvent? {
    val body: CWorkBody = when (this) {
        is PWorkEvent.ChatPosted -> CWorkBody.ChatPosted(messageId, body, mentionedAgentIds, inputAfterSeq, sourceSessionId, taskId)
        is PWorkEvent.TaskCreated -> CWorkBody.TaskCreated(task.toContract())
        is PWorkEvent.TaskTransitioned -> CWorkBody.TaskTransitioned(
            taskId, from.toContract(), to.toContract(), revision,
            blocker?.let { CWorkBlocker(it.reason, it.ownerId, it.resumeCondition, createdAt) }
        )
        is PWorkEvent.MemberAttached -> CWorkBody.MemberAttached(membershipOperationId, agentId, role.toContract(), membershipRevision)
        is PWorkEvent.MemberDetached -> CWorkBody.MemberDetached(membershipOperationId, agentId, membershipRevision)
        is PWorkEvent.DiscussionStarted -> CWorkBody.DiscussionStarted(triggerEventIds)
        is PWorkEvent.DiscussionFinished -> CWorkBody.DiscussionFinished(discussionId, status.name.lowercase(), error)
        is PWorkEvent.WorkRequested -> CWorkBody.WorkRequested(agentId, instruction, membershipRevision, taskId, inputAfterSeq)
        is PWorkEvent.ExecutionFinished -> CWorkBody.ExecutionFinished(
            executionId, sourceEventId, agentId, status.name.lowercase(), taskId, error
        )
        else -> return null
    }
    return CWorkEvent(
        type = wireType(),
        id = id,
        workId = workId,
        seq = seq,
        createdAt = createdAt,
        actor = actor.toContract(),
        body = body,
        causationId = causation(),
        correlationId = correlation(),
        clientEventId = clientEvent()
    )
}

private fun PWorkActor.toContract(): CWorkActor = when (this) {
    is PWorkActor.User -> CWorkActor.User(id)
    is PWorkActor.Agent -> CWorkActor.Agent(id)
    is PWorkActor.SystemActor -> CWorkActor.System(id)
}

private fun PWorkEvent.wireType(): String = when (this) {
    is PWorkEvent.ChatPosted -> "chat.posted"
    is PWorkEvent.TaskCreated -> "task.created"
    is PWorkEvent.TaskTransitioned -> "task.transitioned"
    is PWorkEvent.MemberAttached -> "member.attached"
    is PWorkEvent.MemberDetached -> "member.detached"
    is PWorkEvent.DiscussionStarted -> "discussion.started"
    is PWorkEvent.DiscussionFinished -> "discussion.finished"
    is PWorkEvent.WorkRequested -> "work.requested"
    is PWorkEvent.ExecutionFinished -> "execution.finished"
    else -> "work.event"
}

private fun PWorkEvent.causation(): String? = when (this) {
    is PWorkEvent.ChatPosted -> causationId
    is PWorkEvent.TaskCreated -> causationId
    is PWorkEvent.TaskTransitioned -> causationId
    is PWorkEvent.MemberAttached -> causationId
    is PWorkEvent.MemberDetached -> causationId
    is PWorkEvent.DiscussionStarted -> causationId
    is PWorkEvent.DiscussionFinished -> causationId
    is PWorkEvent.WorkRequested -> causationId
    is PWorkEvent.ExecutionFinished -> causationId
    else -> null
}

private fun PWorkEvent.correlation(): String? = when (this) {
    is PWorkEvent.ChatPosted -> correlationId
    is PWorkEvent.TaskCreated -> correlationId
    is PWorkEvent.TaskTransitioned -> correlationId
    is PWorkEvent.MemberAttached -> correlationId
    is PWorkEvent.MemberDetached -> correlationId
    is PWorkEvent.DiscussionStarted -> correlationId
    is PWorkEvent.DiscussionFinished -> correlationId
    is PWorkEvent.WorkRequested -> correlationId
    is PWorkEvent.ExecutionFinished -> correlationId
    else -> null
}

private fun PWorkEvent.clientEvent(): String? = when (this) {
    is PWorkEvent.ChatPosted -> clientEventId
    is PWorkEvent.TaskCreated -> clientEventId
    is PWorkEvent.TaskTransitioned -> clientEventId
    is PWorkEvent.MemberAttached -> clientEventId
    is PWorkEvent.MemberDetached -> clientEventId
    is PWorkEvent.DiscussionStarted -> clientEventId
    is PWorkEvent.DiscussionFinished -> clientEventId
    is PWorkEvent.WorkRequested -> clientEventId
    is PWorkEvent.ExecutionFinished -> clientEventId
    else -> null
}

internal fun PProactiveSnapshot.toContract() = CProactiveSnapshot(
    defaultAgentId,
    agents.map { it.toContract() },
    availableSourceIds,
    false
)

private fun PProactiveAgent.toContract() = CProactiveAgentSnapshot(
    agentId,
    name,
    policy.toContract(),
    state.name.lowercase().replace('_', '-'),
    activity.map { it.toContract() }
)

private fun PProactiveActivity.toContract() = CProactiveActivity(
    id, at, kind.name.lowercase().replace('_', '-'), contextRefs
)

internal fun JsonObject.toArgs(): Map<String, Any?> = mapValues { (_, value) -> value.toKotlin() }

internal fun Map<String, Any?>.toJsonObject(): JsonObject =
    JsonObject(mapValues { (_, value) -> value.toJsonElement() })

private fun JsonElement.toKotlin(): Any? = when (this) {
    is JsonNull -> null
    is JsonPrimitive -> when {
        isString -> content
        booleanOrNull != null -> booleanOrNull
        longOrNull != null && '.' !in content && 'e' !in content && 'E' !in content -> longOrNull
        doubleOrNull != null -> doubleOrNull
        else -> content
    }
    is JsonArray -> map { it.toKotlin() }
    is JsonObject -> toArgs()
}

private fun Any?.toJsonElement(): JsonElement = when (this) {
    null -> JsonNull
    is JsonElement -> this
    is String -> JsonPrimitive(this)
    is Boolean -> JsonPrimitive(this)
    is Int -> JsonPrimitive(this)
    is Long -> JsonPrimitive(this)
    is Double -> JsonPrimitive(this)
    is Float -> JsonPrimitive(this)
    is Map<*, *> -> JsonObject(entries.associate { (key, value) -> key.toString() to value.toJsonElement() })
    is Iterable<*> -> JsonArray(map { it.toJsonElement() })
    else -> JsonPrimitive(toString())
}
