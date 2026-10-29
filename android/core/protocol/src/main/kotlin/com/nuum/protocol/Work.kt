@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

package com.nuum.protocol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonClassDiscriminator

@Serializable
enum class WorkKind {
    @SerialName("room") ROOM,
    @SerialName("work") WORK
}

@Serializable
enum class WorkRole {
    @SerialName("coordinator") COORDINATOR,
    @SerialName("worker") WORKER,
    @SerialName("observer") OBSERVER
}

@Serializable
enum class WorkTaskState {
    @SerialName("proposed") PROPOSED,
    @SerialName("ready") READY,
    @SerialName("in_progress") IN_PROGRESS,
    @SerialName("blocked") BLOCKED,
    @SerialName("review") REVIEW,
    @SerialName("done") DONE,
    @SerialName("cancelled") CANCELLED
}

val WORK_TASK_STATES: List<String> = listOf(
    "proposed",
    "ready",
    "in_progress",
    "blocked",
    "review",
    "done",
    "cancelled"
)

@Serializable
enum class WorkTaskPriority {
    @SerialName("low") LOW,
    @SerialName("normal") NORMAL,
    @SerialName("high") HIGH
}

@Serializable
enum class HandoffNextStatus {
    @SerialName("in_progress") IN_PROGRESS,
    @SerialName("review") REVIEW,
    @SerialName("blocked") BLOCKED,
    @SerialName("done") DONE
}

@Serializable
enum class ExecutionFinishStatus {
    @SerialName("completed") COMPLETED,
    @SerialName("failed") FAILED,
    @SerialName("cancelled") CANCELLED
}

@Serializable
enum class DiscussionFinishStatus {
    @SerialName("completed") COMPLETED,
    @SerialName("cancelled") CANCELLED,
    @SerialName("interrupted") INTERRUPTED
}

@Serializable
data class WorkProfile(
    val kind: WorkKind? = null,
    val id: String,
    val name: String,
    val description: String,
    val avatar: String? = null,
    val projectRoot: String?,
    val workspaceId: String? = null,
    val createdAt: Long
)

/** Flat sidebar row: profile fields plus derived activity. Members are not stored here. */
@Serializable
data class WorkListItem(
    val kind: WorkKind? = null,
    val id: String,
    val name: String,
    val description: String,
    val avatar: String? = null,
    val projectRoot: String?,
    val workspaceId: String? = null,
    val createdAt: Long,
    val lastActivityAt: Long,
    val preview: String? = null
)

@Serializable
data class WorkGrants(
    val canPost: Boolean,
    val canManageOwnTasks: Boolean,
    val canAssignTasks: Boolean,
    val canEditCatalog: Boolean
)

@Serializable
data class WorkBinding(
    val workId: String,
    val role: WorkRole,
    val joinedAt: Long,
    val grants: WorkGrants
)

/** One dynamic slot. `revision` is the CAS token for drag in, drag out, and switching Works. */
@Serializable
data class WorkMembership(
    val revision: Int,
    val binding: WorkBinding?
)

@Serializable
data class WorkDeliverable(
    val id: String,
    val name: String,
    val uri: String,
    val mimeType: String? = null,
    val createdAt: Long
)

@Serializable
data class WorkTaskBlocker(
    val reason: String,
    val ownerId: String? = null,
    val resumeCondition: String? = null,
    val createdAt: Long
)

@Serializable
data class WorkTransitionBlocker(
    val reason: String,
    val ownerId: String? = null,
    val resumeCondition: String? = null
)

@Serializable
data class WorkTask(
    val id: String,
    val title: String,
    val description: String,
    val acceptanceCriteria: List<String>,
    val state: WorkTaskState,
    val ownerAgentId: String? = null,
    val assigneeIds: List<String>,
    val dependencyIds: List<String>,
    val priority: WorkTaskPriority,
    val revision: Int,
    val deliverables: List<WorkDeliverable>,
    val blocker: WorkTaskBlocker? = null,
    val createdAt: Long,
    val updatedAt: Long,
    val allowedTransitions: List<WorkTaskState>? = null
)

fun WorkTask.asView(allowedTransitions: List<WorkTaskState>): WorkTask = copy(allowedTransitions = allowedTransitions)

@Serializable
@JsonClassDiscriminator("kind")
sealed interface WorkCatalogEntry {
    val id: String
    val name: String
    val description: String
    val enabled: Boolean

    @Serializable
    @SerialName("skill")
    data class Skill(
        override val id: String,
        override val name: String,
        override val description: String,
        override val enabled: Boolean,
        val manifestPath: String
    ) : WorkCatalogEntry

    @Serializable
    @SerialName("cli")
    data class Cli(
        override val id: String,
        override val name: String,
        override val description: String,
        override val enabled: Boolean,
        val executable: String,
        val allowedSubcommands: List<String>
    ) : WorkCatalogEntry

    @Serializable
    @SerialName("knowledge")
    data class Knowledge(
        override val id: String,
        override val name: String,
        override val description: String,
        override val enabled: Boolean,
        val roots: List<String>,
        val readOnly: Boolean
    ) : WorkCatalogEntry {
        init {
            require(readOnly) { "knowledge catalog entries are readOnly" }
        }
    }

    @Serializable
    @SerialName("local-tool")
    data class LocalTool(
        override val id: String,
        override val name: String,
        override val description: String,
        override val enabled: Boolean,
        val toolNames: List<String>
    ) : WorkCatalogEntry
}

@Serializable
data class WorkCatalog(
    val revision: Int,
    val entries: List<WorkCatalogEntry>
)

val EMPTY_WORK_CATALOG = WorkCatalog(revision = 0, entries = emptyList())

@Serializable
@JsonClassDiscriminator("kind")
sealed interface WorkActor {
    val id: String

    @Serializable
    @SerialName("user")
    data class User(override val id: String) : WorkActor

    @Serializable
    @SerialName("agent")
    data class Agent(override val id: String) : WorkActor

    @Serializable
    @SerialName("system")
    data class SystemActor(override val id: String) : WorkActor
}

@Serializable
data class DispatchDiscussion(
    val rootId: String,
    val round: Int,
    val order: List<String>,
    val index: Int
)

@Serializable
sealed interface WorkEvent {
    val id: String
    val workId: String
    val seq: Int
    val createdAt: Long
    val actor: WorkActor

    @Serializable
    @SerialName("chat.posted")
    data class ChatPosted(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val messageId: String,
        val inputAfterSeq: Int? = null,
        val body: String,
        val mentionedAgentIds: List<String>,
        val sourceSessionId: String? = null,
        val taskId: String? = null,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("task.created")
    data class TaskCreated(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val task: WorkTask,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("task.claimed")
    data class TaskClaimed(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val taskId: String,
        val assigneeIds: List<String>,
        val revision: Int,
        val messageId: String,
        val body: String,
        val sourceSessionId: String? = null,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("task.assigned")
    data class TaskAssigned(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val taskId: String,
        val assigneeIds: List<String>,
        val revision: Int,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("task.delegated")
    data class TaskDelegated(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val taskId: String,
        val agentId: String,
        val instruction: String,
        val revision: Int,
        val messageId: String,
        val membershipRevision: Int,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("task.transitioned")
    data class TaskTransitioned(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val taskId: String,
        val from: WorkTaskState,
        val to: WorkTaskState,
        val revision: Int,
        val blocker: WorkTransitionBlocker? = null,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("task.progressed")
    data class TaskProgressed(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val taskId: String,
        val summary: String,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("task.handed_off")
    data class TaskHandedOff(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val taskId: String,
        val summary: String,
        val deliverables: List<WorkDeliverable>,
        val nextStatus: HandoffNextStatus,
        val returnToAgentId: String? = null,
        val blockerReason: String? = null,
        val revision: Int,
        val messageId: String? = null,
        val sourceSessionId: String? = null,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("history.imported")
    data class HistoryImported(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val unconfirmedEventIds: List<String>,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("work.requested")
    data class WorkRequested(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val agentId: String,
        val taskId: String? = null,
        val instruction: String,
        val membershipRevision: Int,
        val resumesExecutionId: String? = null,
        val inputAfterSeq: Int? = null,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("execution.started")
    data class ExecutionStarted(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val executionId: String,
        val sourceEventId: String,
        val agentId: String,
        val taskId: String? = null,
        val sessionId: String,
        val runId: String,
        val membershipRevision: Int,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("execution.finished")
    data class ExecutionFinished(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val executionId: String,
        val sourceEventId: String,
        val agentId: String,
        val taskId: String? = null,
        val status: ExecutionFinishStatus,
        val error: String? = null,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("discussion.started")
    data class DiscussionStarted(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val triggerEventIds: List<String>,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("discussion.finished")
    data class DiscussionFinished(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val discussionId: String,
        val status: DiscussionFinishStatus,
        val error: String? = null,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("dispatch.requested")
    data class DispatchRequested(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val bridgeId: String,
        val agentId: String,
        val taskId: String? = null,
        val instruction: String,
        val membershipRevision: Int? = null,
        val discussion: DispatchDiscussion? = null,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("dispatch.acknowledged")
    data class DispatchAcknowledged(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val bridgeId: String,
        val agentId: String,
        val transcriptEventId: String,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("dispatch.finished")
    data class DispatchFinished(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val bridgeId: String,
        val agentId: String,
        val status: ExecutionFinishStatus,
        val error: String? = null,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("member.attached")
    data class MemberAttached(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val membershipOperationId: String,
        val agentId: String,
        val role: WorkRole,
        val membershipRevision: Int,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent

    @Serializable
    @SerialName("member.detached")
    data class MemberDetached(
        override val id: String,
        override val workId: String,
        override val seq: Int,
        override val createdAt: Long,
        override val actor: WorkActor,
        val membershipOperationId: String,
        val agentId: String,
        val membershipRevision: Int,
        val causationId: String? = null,
        val correlationId: String? = null,
        val clientEventId: String? = null,
        val serverWatermark: Int? = null
    ) : WorkEvent
}

data class WorkProjection(
    val tasks: List<WorkTask>,
    val chat: List<WorkEvent.ChatPosted>
)
