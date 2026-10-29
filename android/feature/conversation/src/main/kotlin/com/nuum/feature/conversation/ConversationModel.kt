package com.nuum.feature.conversation

import com.nuum.contracts.AgentAnswerWidgetParams
import com.nuum.contracts.AgentPort
import com.nuum.contracts.AgentSendParams
import com.nuum.contracts.AttachmentUpload
import com.nuum.contracts.DesktopPort
import com.nuum.contracts.MAX_ATTACHMENTS
import com.nuum.contracts.ToolResolution
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class ConversationPorts(
    val agent: AgentPort,
    val desktop: DesktopPort
)

internal class ConversationModel(
    private val agentId: String,
    private val ports: ConversationPorts
) {
    private val _state = MutableStateFlow(ConversationUiState())
    val state: StateFlow<ConversationUiState> = _state.asStateFlow()
    private var scope: CoroutineScope? = null

    suspend fun run(): Unit = coroutineScope {
        scope = this
        val gate = Mutex()
        val buffer = mutableListOf<com.nuum.contracts.HostEvent>()
        var ready = false
        // UNDISPATCHED subscribes before get(), so events that arrive during the snapshot load are buffered.
        launch(start = CoroutineStart.UNDISPATCHED) {
            ports.agent.events.collect { event ->
                gate.withLock {
                    if (ready) _state.update { it.reduce(agentId, event) }
                    else buffer += event
                }
            }
        }
        val snapshot = async { runCatching { ports.agent.get(agentId) } }
        val peers = async { runCatching { ports.agent.list() }.getOrDefault(emptyList()) }
        val loaded = snapshot.await()
        val peerList = peers.await()
        gate.withLock {
            _state.update { current ->
                if (loaded.isSuccess) {
                    current.withSnapshot(loaded.getOrThrow(), peerList)
                } else {
                    current.copy(phase = Phase.Ready, notice = loaded.exceptionOrNull().toBanner())
                }
            }
            ready = true
            buffer.toList().forEach { event -> _state.update { it.reduce(agentId, event) } }
            buffer.clear()
        }
        awaitCancellation()
    }

    fun onDraft(value: String) {
        _state.update { state ->
            if (value == state.draft) {
                state
            } else {
                state.copy(
                    draft = value,
                    attachmentLimitBlocked = false,
                    attachmentError = if (state.attachmentLimitBlocked && state.attachmentError == CopyKey.AtMost5) {
                        null
                    } else {
                        state.attachmentError
                    }
                )
            }
        }
    }

    fun send() {
        scope?.launch { performSend() }
    }

    fun cancel() {
        scope?.launch {
            try {
                ports.agent.cancel(agentId)
            } catch (error: Exception) {
                _state.update { it.copy(notice = error.toBanner()) }
            }
        }
    }

    fun pickAttachments() {
        val current = _state.value
        if (current.agent == null || current.sending || current.readingAttachments || current.showStop) return
        scope?.launch { performPick() }
    }

    fun removeAttachment(index: Int) {
        _state.update { state ->
            if (state.sending || state.readingAttachments || state.showStop) {
                state
            } else {
                state.copy(
                    attachments = state.attachments.filterIndexed { item, _ -> item != index },
                    attachmentLimitBlocked = false,
                    attachmentError = if (state.attachmentError == CopyKey.AtMost5) null else state.attachmentError
                )
            }
        }
    }

    fun decide(resolution: ToolResolution) {
        if (resolution == ToolResolution.NEVER) return
        val pending = oneToOneApproval(_state.value.pending) ?: return
        if (_state.value.deciding) return
        if (resolution == ToolResolution.ALWAYS && !pending.alwaysEnabled) return
        scope?.launch {
            _state.update { it.copy(deciding = true, approvalError = null) }
            try {
                if (resolution == ToolResolution.DENY) {
                    ports.agent.deny(agentId, pending.toolCallId, resolution)
                } else {
                    ports.agent.approve(agentId, pending.toolCallId, resolution)
                }
                _state.update { state ->
                    state.copy(
                        deciding = false,
                        approvalError = null,
                        pending = if (state.pending?.toolCallId == pending.toolCallId) null else state.pending
                    )
                }
            } catch (error: Exception) {
                _state.update { it.copy(deciding = false, approvalError = error.message.orEmpty()) }
            }
        }
    }

    fun answer(messageId: String, value: String) {
        val trimmed = value.trim()
        if (trimmed.isEmpty() || _state.value.widgetBusy == messageId) return
        scope?.launch {
            _state.update { it.copy(widgetBusy = messageId, widgetErrors = it.widgetErrors - messageId) }
            try {
                ports.agent.answerWidget(AgentAnswerWidgetParams(id = agentId, messageId = messageId, value = trimmed))
                _state.update { state ->
                    if (state.widgetBusy == messageId) state.copy(widgetBusy = null) else state
                }
            } catch (error: Exception) {
                _state.update { state ->
                    state.copy(
                        widgetBusy = if (state.widgetBusy == messageId) null else state.widgetBusy,
                        widgetErrors = state.widgetErrors + (messageId to error.message.orEmpty())
                    )
                }
            }
        }
    }

    fun openAttachment(path: String) {
        scope?.launch {
            try {
                ports.desktop.openAttachment(path)
            } catch (openError: Exception) {
                try {
                    ports.desktop.share(path)
                } catch (_: Exception) {
                    _state.update { it.copy(notice = openError.toBanner()) }
                }
            }
        }
    }

    fun openPeer(peerId: String) {
        _state.update { it.copy(openPeerId = peerId) }
    }

    fun closePeer() {
        _state.update { it.copy(openPeerId = null) }
    }

    private suspend fun performSend() {
        val current = _state.value
        if (current.attachmentLimitBlocked || current.attachments.size > MAX_ATTACHMENTS) {
            _state.update { it.copy(attachmentError = CopyKey.AtMost5, attachmentLimitBlocked = true) }
            return
        }
        if (current.sending || current.readingAttachments || current.showStop) return
        if (current.draft.isBlank() && current.attachments.isEmpty()) return
        val draft = current.draft
        val attachments = current.attachments
        _state.update { it.copy(sending = true, notice = null) }
        try {
            ports.agent.send(
                AgentSendParams(
                    id = agentId,
                    content = draft,
                    attachments = attachments.map { AttachmentUpload(it.name, it.mimeType, it.bytes) }
                )
            )
            _state.update {
                it.copy(
                    sending = false,
                    draft = "",
                    attachments = emptyList(),
                    attachmentError = null,
                    attachmentLimitBlocked = false
                )
            }
        } catch (error: Exception) {
            _state.update { it.copy(sending = false, notice = error.toBanner()) }
        }
    }

    private suspend fun performPick() {
        _state.update { it.copy(readingAttachments = true) }
        try {
            val picked = ports.desktop.pickFiles()
            _state.update { state ->
                when (val decision = validateAttachments(state.attachments, picked)) {
                    is AttachmentDecision.Accept -> state.copy(
                        readingAttachments = false,
                        attachments = decision.files,
                        attachmentError = if (picked.isEmpty()) state.attachmentError else null,
                        attachmentLimitBlocked = if (picked.isEmpty()) state.attachmentLimitBlocked else false
                    )
                    is AttachmentDecision.Reject -> state.copy(
                        readingAttachments = false,
                        attachmentError = decision.reason,
                        attachmentLimitBlocked = decision.reason == CopyKey.AtMost5
                    )
                }
            }
        } catch (_: Exception) {
            _state.update { it.copy(readingAttachments = false, attachmentError = CopyKey.ReadFailed) }
        }
    }
}
