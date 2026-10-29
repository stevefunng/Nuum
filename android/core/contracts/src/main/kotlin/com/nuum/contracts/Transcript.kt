package com.nuum.contracts

data class UserAttachment(
    val name: String,
    val path: String,
    val mimeType: String,
    val size: Int,
    val text: String? = null
)

data class WidgetOption(
    val label: String,
    val value: String? = null,
    val description: String? = null,
    val style: String? = null
)

data class WidgetPayload(
    val prompt: String,
    val options: List<WidgetOption>,
    val helpText: String? = null,
    val allowCustom: Boolean = false
)

data class OutboundImage(val path: String, val alt: String? = null)

sealed class OutboundMessage {
    data class Text(val content: String, val images: List<OutboundImage> = emptyList()) : OutboundMessage()
    data class Attachment(val path: String, val caption: String? = null) : OutboundMessage()
    data class Widget(val widget: WidgetPayload) : OutboundMessage()
    data class LegacyWidget(val widget: String, val props: Map<String, Any?> = emptyMap()) : OutboundMessage()
}

sealed class AssistantPart {
    data class Thinking(val text: String) : AssistantPart()
    data class Text(val text: String) : AssistantPart()
    data class ToolCallPart(
        val id: String,
        val name: String,
        val arguments: Map<String, Any?>,
        val executionId: String? = null
    ) : AssistantPart()
}

sealed class WakeSource {
    data class Agent(
        val fromId: String,
        val fromName: String,
        val priority: Boolean = false
    ) : WakeSource()

    data class Work(
        val workId: String,
        val workName: String,
        val bridgeId: String,
        val taskId: String? = null
    ) : WakeSource()

    data class Routine(val routineId: String, val routineName: String) : WakeSource()
}

sealed class TranscriptEvent {
    abstract val type: String
    abstract val id: String
    abstract val seq: Int
    abstract val createdAt: Long

    data class User(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val text: String,
        val attachments: List<UserAttachment> = emptyList(),
        val widgetAnswerTo: String? = null
    ) : TranscriptEvent() {
        override val type = "user"
    }

    data class Wake(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val source: WakeSource,
        val text: String,
        val hops: Int = 0
    ) : TranscriptEvent() {
        override val type = "wake"
    }

    data class Assistant(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val parts: List<AssistantPart>
    ) : TranscriptEvent() {
        override val type = "assistant"
    }

    data class Tool(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val toolCallId: String,
        val name: String,
        val content: String,
        val assistantId: String? = null,
        val ok: Boolean? = null,
        val spillPath: String? = null
    ) : TranscriptEvent() {
        override val type = "tool"
    }

    data class Message(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val payload: OutboundMessage,
        val assistantId: String? = null,
        val toolCallId: String? = null
    ) : TranscriptEvent() {
        override val type = "message"
    }

    data class Compact(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val epoch: Int,
        val throughSeq: Int,
        val tailFromSeq: Int,
        val summary: String
    ) : TranscriptEvent() {
        override val type = "compact"
    }

    data class Profile(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val name: String? = null,
        val description: String? = null,
        val tags: List<String>? = null
    ) : TranscriptEvent() {
        override val type = "profile"
    }
}

data class TranscriptQuery(val id: String, val beforeSeq: Int? = null, val limit: Int? = null)

data class TranscriptPage(
    val id: String,
    val entries: List<TranscriptEvent>,
    val nextBeforeSeq: Int? = null
)

data class LiveAssistant(val messageId: String, val parts: List<AssistantPart>)

data class ToolView(
    val id: String,
    val name: String,
    val arguments: Map<String, Any?>,
    val output: String? = null,
    val status: String
)

sealed class ViewBlock {
    data class User(
        val id: String,
        val text: String,
        val attachments: List<UserAttachment> = emptyList(),
        val widgetAnswerTo: String? = null
    ) : ViewBlock()

    data class Assistant(
        val id: String,
        val thinking: String,
        val tools: List<ToolView>,
        val live: Boolean = false
    ) : ViewBlock()

    data class Message(val id: String, val payload: OutboundMessage) : ViewBlock()

    data class Peer(
        val id: String,
        val direction: String,
        val agentId: String,
        val agentName: String,
        val text: String,
        val priority: Boolean
    ) : ViewBlock()

    data class Notice(val id: String, val kind: String, val text: String) : ViewBlock()
}

data class AgentSnapshot(
    val view: AgentView,
    val events: List<TranscriptEvent>,
    val blocks: List<ViewBlock>,
    val live: LiveAssistant?
)
