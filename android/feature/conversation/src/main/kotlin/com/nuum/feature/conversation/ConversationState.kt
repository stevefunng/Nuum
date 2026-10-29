package com.nuum.feature.conversation

import com.nuum.contracts.AgentSnapshot
import com.nuum.contracts.AgentStatus
import com.nuum.contracts.AgentView
import com.nuum.contracts.AssistantPart
import com.nuum.contracts.HostEvent
import com.nuum.contracts.LiveAssistant
import com.nuum.contracts.MessagePart
import com.nuum.contracts.RunEndStatus
import com.nuum.contracts.TranscriptEvent
import com.nuum.contracts.ViewBlock

internal enum class Phase { Loading, Ready }

internal sealed class Banner {
    abstract val alert: Boolean

    data class Localized(val key: CopyKey, override val alert: Boolean) : Banner()
    data class Raw(val text: String, override val alert: Boolean) : Banner()
}

internal fun Throwable?.toBanner(): Banner {
    val message = this?.message
    return if (message.isNullOrBlank()) {
        Banner.Localized(CopyKey.HostError, alert = true)
    } else {
        Banner.Raw(message, alert = true)
    }
}

internal data class ConversationUiState(
    val phase: Phase = Phase.Loading,
    val agent: AgentView? = null,
    val peers: List<AgentView> = emptyList(),
    val events: List<TranscriptEvent> = emptyList(),
    val fallbackBlocks: List<ViewBlock> = emptyList(),
    val live: LiveAssistant? = null,
    val liveText: LiveText? = null,
    val streaming: Boolean = false,
    val draft: String = "",
    val attachments: List<ComposerAttachment> = emptyList(),
    val readingAttachments: Boolean = false,
    val attachmentError: CopyKey? = null,
    val attachmentLimitBlocked: Boolean = false,
    val notice: Banner? = null,
    val pending: PendingTool? = null,
    val deciding: Boolean = false,
    val approvalError: String? = null,
    val openPeerId: String? = null,
    val sending: Boolean = false,
    val toolResults: Map<String, ToolResult> = emptyMap(),
    val widgetErrors: Map<String, String> = emptyMap(),
    val widgetBusy: String? = null
) {
    val showStop: Boolean
        get() = streaming ||
            agent?.runtime?.status == AgentStatus.RUNNING ||
            oneToOneApproval(pending) != null

    fun visibleBlocks(): List<ViewBlock> {
        val projected = if (events.isNotEmpty() || live != null) {
            projectAgent(events, live, toolResults)
        } else {
            fallbackBlocks
        }
        return groupToolActivity(withLiveText(projected, liveText))
    }
}

internal fun ConversationUiState.withSnapshot(
    snapshot: AgentSnapshot,
    peers: List<AgentView>
): ConversationUiState {
    val liveSource = snapshot.live
    val text = liveSource?.parts?.filterIsInstance<AssistantPart.Text>()?.joinToString("") { it.text }.orEmpty()
    val remaining = liveSource?.parts?.filterNot { it is AssistantPart.Text }.orEmpty()
    val hostRunning = snapshot.view.runtime.status == AgentStatus.RUNNING
    return copy(
        phase = Phase.Ready,
        agent = snapshot.view,
        peers = peers.ifEmpty { listOf(snapshot.view) },
        events = snapshot.events,
        fallbackBlocks = if (snapshot.events.isEmpty()) snapshot.blocks else emptyList(),
        live = if (remaining.isEmpty() || liveSource == null) null else LiveAssistant(liveSource.messageId, remaining),
        liveText = if (liveSource != null && text.isNotEmpty()) LiveText(liveSource.messageId, text) else null,
        streaming = hostRunning || liveSource != null
    )
}

internal fun ConversationUiState.reduce(agentId: String, event: HostEvent): ConversationUiState = when (event) {
    is HostEvent.AgentUpdated -> reduceUpdated(agentId, event)
    is HostEvent.AgentMessageDelta -> reduceDelta(agentId, event)
    is HostEvent.AgentMessageCompleted -> reduceCompleted(agentId, event)
    is HostEvent.AgentToolPending -> reducePending(agentId, event)
    is HostEvent.AgentToolStarted -> reduceToolStarted(agentId, event)
    is HostEvent.AgentToolCompleted -> reduceToolCompleted(agentId, event)
    is HostEvent.AgentError -> reduceError(agentId, event)
    is HostEvent.AgentEnded -> reduceEnded(agentId, event)
    else -> this
}

private fun ConversationUiState.reduceUpdated(
    agentId: String,
    event: HostEvent.AgentUpdated
): ConversationUiState {
    val updatedPeers = peers.map { peer ->
        if (peer.profile.id == event.agent.profile.id) event.agent else peer
    }
    if (event.agent.profile.id != agentId) return copy(peers = updatedPeers)
    val hostRunning = event.agent.runtime.status == AgentStatus.RUNNING
    return copy(
        agent = event.agent,
        peers = updatedPeers.ifEmpty { listOf(event.agent) },
        streaming = hostRunning || live != null || liveText != null
    )
}

private fun ConversationUiState.reduceDelta(
    agentId: String,
    event: HostEvent.AgentMessageDelta
): ConversationUiState {
    if (event.agentId != agentId) return this
    return if (event.part == MessagePart.THINKING) {
        val parts = appendAssistantDelta(
            parts = if (live?.messageId == event.messageId) live.parts else emptyList(),
            kind = MessagePart.THINKING,
            delta = event.delta
        )
        copy(streaming = true, live = LiveAssistant(event.messageId, parts))
    } else {
        copy(streaming = true, liveText = appendText(liveText, event.messageId, event.delta))
    }
}

private fun ConversationUiState.reduceCompleted(
    agentId: String,
    event: HostEvent.AgentMessageCompleted
): ConversationUiState {
    if (event.agentId != agentId) return this
    val transcriptEvent = event.event
    var next = copy(events = mergeEvents(events, transcriptEvent), fallbackBlocks = emptyList())
    if (transcriptEvent is TranscriptEvent.Assistant && live?.messageId == transcriptEvent.id) {
        next = next.copy(live = null)
    }
    if (transcriptEvent is TranscriptEvent.Assistant && liveText?.messageId == transcriptEvent.id) {
        next = next.copy(liveText = null)
    }
    if (transcriptEvent is TranscriptEvent.Message) {
        next = next.copy(liveText = null)
    }
    return next
}

private fun ConversationUiState.reducePending(
    agentId: String,
    event: HostEvent.AgentToolPending
): ConversationUiState {
    if (event.agentId != agentId) return this
    return copy(pending = event.toPending(), streaming = true, approvalError = null, deciding = false)
}

private fun ConversationUiState.reduceToolStarted(
    agentId: String,
    event: HostEvent.AgentToolStarted
): ConversationUiState {
    if (event.agentId != agentId) return this
    return copy(
        streaming = true,
        live = ensureToolCall(live, event.toolCallId, event.toolName, event.arguments)
    )
}

private fun ConversationUiState.reduceToolCompleted(
    agentId: String,
    event: HostEvent.AgentToolCompleted
): ConversationUiState {
    if (event.agentId != agentId) return this
    return copy(
        toolResults = toolResults + (event.toolCallId to ToolResult(event.output, event.ok)),
        pending = pending?.takeIf { it.toolCallId != event.toolCallId },
        deciding = if (pending?.toolCallId == event.toolCallId) false else deciding,
        live = ensureToolCall(live, event.toolCallId, event.toolName, emptyMap())
    )
}

private fun ConversationUiState.reduceError(
    agentId: String,
    event: HostEvent.AgentError
): ConversationUiState {
    if (event.agentId != agentId) return this
    return copy(
        streaming = false,
        live = null,
        liveText = null,
        pending = null,
        deciding = false,
        notice = event.message.toBannerMessage()
    )
}

private fun ConversationUiState.reduceEnded(
    agentId: String,
    event: HostEvent.AgentEnded
): ConversationUiState {
    if (event.agentId != agentId) return this
    val stopped = event.status == RunEndStatus.CANCELLED
    val nextStatus = when (event.status) {
        RunEndStatus.ERROR -> AgentStatus.ERROR
        RunEndStatus.CANCELLED, RunEndStatus.IDLE -> AgentStatus.IDLE
    }
    val nextNotice = when {
        stopped -> Banner.Localized(CopyKey.Stopped, alert = false)
        notice is Banner.Localized && notice.key == CopyKey.Stopped -> null
        else -> notice
    }
    return copy(
        streaming = false,
        live = null,
        liveText = null,
        pending = null,
        deciding = false,
        notice = nextNotice,
        agent = agent?.copy(
            runtime = agent.runtime.copy(status = nextStatus, activeRunId = null)
        )
    )
}

private fun String.toBannerMessage(): Banner {
    return if (isBlank()) Banner.Localized(CopyKey.HostError, alert = true) else Banner.Raw(this, alert = true)
}
