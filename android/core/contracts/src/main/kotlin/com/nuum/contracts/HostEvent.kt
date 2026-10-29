package com.nuum.contracts

/**
 * Names match `HostEvents`. There is no `host.kernel.down` event: model
 * failures use [AgentError] with [KernelErrorCode.MODEL] or [HostErrorCode.NO_API_KEY].
 */
object HostEvents {
    const val AGENT_UPDATED = "agent.updated"
    const val AGENT_MESSAGE_DELTA = "agent.message.delta"
    const val AGENT_MESSAGE_COMPLETED = "agent.message.completed"
    const val AGENT_TOOL_PENDING = "agent.tool.pending"
    const val AGENT_TOOL_STARTED = "agent.tool.started"
    const val AGENT_TOOL_COMPLETED = "agent.tool.completed"
    const val AGENT_ERROR = "agent.error"
    const val AGENT_ENDED = "agent.ended"
    const val WORK_UPDATED = "work.updated"
    const val WORK_EVENT_APPENDED = "work.event.appended"
    const val WORK_CATALOG_UPDATED = "work.catalog.updated"
    const val PROACTIVE_UPDATED = "proactive.updated"
    const val SETTINGS_UPDATED = "settings.updated"

    val ALL: Set<String> = setOf(
        AGENT_UPDATED,
        AGENT_MESSAGE_DELTA,
        AGENT_MESSAGE_COMPLETED,
        AGENT_TOOL_PENDING,
        AGENT_TOOL_STARTED,
        AGENT_TOOL_COMPLETED,
        AGENT_ERROR,
        AGENT_ENDED,
        WORK_UPDATED,
        WORK_EVENT_APPENDED,
        WORK_CATALOG_UPDATED,
        PROACTIVE_UPDATED,
        SETTINGS_UPDATED
    )
}

sealed class HostEvent {
    abstract val name: String

    data class AgentUpdated(val agent: AgentView) : HostEvent() {
        override val name = HostEvents.AGENT_UPDATED
    }

    data class AgentMessageDelta(
        val agentId: String,
        val runId: String,
        val messageId: String,
        val delta: String,
        val part: MessagePart = MessagePart.TEXT
    ) : HostEvent() {
        override val name = HostEvents.AGENT_MESSAGE_DELTA
    }

    data class AgentMessageCompleted(val agentId: String, val event: TranscriptEvent) : HostEvent() {
        override val name = HostEvents.AGENT_MESSAGE_COMPLETED
    }

    data class AgentToolPending(
        val agentId: String,
        val runId: String,
        val toolCallId: String,
        val toolName: String,
        val arguments: Map<String, Any?>,
        val action: LocalToolAction,
        val target: String,
        val justification: String? = null,
        val allowAlways: Boolean? = null,
        val details: String? = null
    ) : HostEvent() {
        override val name = HostEvents.AGENT_TOOL_PENDING
    }

    data class AgentToolStarted(
        val agentId: String,
        val runId: String,
        val toolCallId: String,
        val toolName: String,
        val arguments: Map<String, Any?>
    ) : HostEvent() {
        override val name = HostEvents.AGENT_TOOL_STARTED
    }

    data class AgentToolCompleted(
        val agentId: String,
        val runId: String,
        val toolCallId: String,
        val toolName: String,
        val ok: Boolean,
        val output: String
    ) : HostEvent() {
        override val name = HostEvents.AGENT_TOOL_COMPLETED
    }

    data class AgentError(
        val agentId: String,
        val runId: String,
        val code: Int,
        val message: String
    ) : HostEvent() {
        override val name = HostEvents.AGENT_ERROR
    }

    data class AgentEnded(
        val agentId: String,
        val runId: String,
        val status: RunEndStatus
    ) : HostEvent() {
        override val name = HostEvents.AGENT_ENDED
    }

    data class WorkUpdated(val work: WorkProfile) : HostEvent() {
        override val name = HostEvents.WORK_UPDATED
    }

    data class WorkEventAppended(val workId: String, val event: WorkEvent) : HostEvent() {
        override val name = HostEvents.WORK_EVENT_APPENDED
    }

    data class WorkCatalogUpdated(val workId: String, val catalog: WorkCatalog) : HostEvent() {
        override val name = HostEvents.WORK_CATALOG_UPDATED
    }

    data class ProactiveUpdated(val snapshot: ProactiveSnapshot? = null) : HostEvent() {
        override val name = HostEvents.PROACTIVE_UPDATED
    }

    data class SettingsUpdated(val settings: PublicSettings) : HostEvent() {
        override val name = HostEvents.SETTINGS_UPDATED
    }
}
