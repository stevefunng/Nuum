package com.nuum.contracts

enum class WorkKind(val wire: String) {
    ROOM("room"),
    WORK("work")
}

enum class WorkRole(val wire: String) {
    COORDINATOR("coordinator"),
    WORKER("worker"),
    OBSERVER("observer")
}

enum class WorkTaskState(val wire: String) {
    PROPOSED("proposed"),
    READY("ready"),
    IN_PROGRESS("in_progress"),
    BLOCKED("blocked"),
    REVIEW("review"),
    DONE("done"),
    CANCELLED("cancelled")
}

enum class WorkTaskPriority(val wire: String) {
    LOW("low"),
    NORMAL("normal"),
    HIGH("high")
}

data class WorkProfile(
    val id: String,
    val name: String,
    val description: String,
    val projectRoot: String?,
    val createdAt: Long,
    val kind: WorkKind? = null,
    val avatar: String? = null,
    val workspaceId: String? = null
)

data class WorkListItem(
    val profile: WorkProfile,
    val lastActivityAt: Long,
    val preview: String? = null
)

data class WorkGrants(
    val canPost: Boolean,
    val canManageOwnTasks: Boolean,
    val canAssignTasks: Boolean,
    val canEditCatalog: Boolean
)

data class WorkBinding(
    val workId: String,
    val role: WorkRole,
    val joinedAt: Long,
    val grants: WorkGrants
)

data class WorkMembership(val revision: Int, val binding: WorkBinding?)

data class AgentSettings(
    val model: ModelRef,
    val execution: ExecutionPreferences? = null,
    val workspace: WorkspaceSettings? = null,
    val hiddenFromSidebar: Boolean = false,
    val proactive: ProactivePolicy? = null,
    val workMembership: WorkMembership? = null
)

data class AgentView(
    val profile: AgentProfile,
    val settings: AgentSettings,
    val runtime: AgentRuntime,
    val roomMemberships: Map<String, WorkMembership> = emptyMap()
)

data class WorkDeliverable(
    val id: String,
    val name: String,
    val uri: String,
    val createdAt: Long,
    val mimeType: String? = null
)

data class WorkBlocker(
    val reason: String,
    val ownerId: String? = null,
    val resumeCondition: String? = null,
    val createdAt: Long? = null
)

data class WorkTask(
    val id: String,
    val title: String,
    val description: String,
    val acceptanceCriteria: List<String>,
    val state: WorkTaskState,
    val assigneeIds: List<String>,
    val dependencyIds: List<String>,
    val priority: WorkTaskPriority,
    val revision: Int,
    val deliverables: List<WorkDeliverable>,
    val createdAt: Long,
    val updatedAt: Long,
    val ownerAgentId: String? = null,
    val blocker: WorkBlocker? = null
)

data class WorkTaskView(val task: WorkTask, val allowedTransitions: List<WorkTaskState>)

sealed class WorkCatalogEntry {
    abstract val id: String
    abstract val name: String
    abstract val description: String
    abstract val enabled: Boolean

    data class Skill(
        override val id: String,
        override val name: String,
        override val description: String,
        override val enabled: Boolean,
        val manifestPath: String
    ) : WorkCatalogEntry()

    data class Cli(
        override val id: String,
        override val name: String,
        override val description: String,
        override val enabled: Boolean,
        val executable: String,
        val allowedSubcommands: List<String>
    ) : WorkCatalogEntry()

    data class Knowledge(
        override val id: String,
        override val name: String,
        override val description: String,
        override val enabled: Boolean,
        val roots: List<String>,
        val readOnly: Boolean = true
    ) : WorkCatalogEntry()

    data class LocalTool(
        override val id: String,
        override val name: String,
        override val description: String,
        override val enabled: Boolean,
        val toolNames: List<String>
    ) : WorkCatalogEntry()
}

data class WorkCatalog(val revision: Int, val entries: List<WorkCatalogEntry>)

sealed class WorkCatalogInput {
    abstract val name: String
    abstract val description: String

    data class Skill(
        override val name: String,
        override val description: String = "",
        val manifestPath: String
    ) : WorkCatalogInput()

    data class Cli(
        override val name: String,
        override val description: String = "",
        val executable: String,
        val allowedSubcommands: List<String> = emptyList()
    ) : WorkCatalogInput()

    data class Knowledge(
        override val name: String,
        override val description: String = "",
        val roots: List<String>,
        val readOnly: Boolean = true
    ) : WorkCatalogInput()

    data class LocalTool(
        override val name: String,
        override val description: String = "",
        val toolNames: List<String>
    ) : WorkCatalogInput()
}

sealed class WorkActor {
    abstract val id: String
    data class User(override val id: String) : WorkActor()
    data class Agent(override val id: String) : WorkActor()
    data class System(override val id: String) : WorkActor()
}

data class WorkEvent(
    val type: String,
    val id: String,
    val workId: String,
    val seq: Int,
    val createdAt: Long,
    val actor: WorkActor,
    val body: WorkEventBody,
    val causationId: String? = null,
    val correlationId: String? = null,
    val clientEventId: String? = null
)

sealed class WorkEventBody {
    data class ChatPosted(
        val messageId: String,
        val body: String,
        val mentionedAgentIds: List<String>,
        val inputAfterSeq: Int? = null,
        val sourceSessionId: String? = null,
        val taskId: String? = null
    ) : WorkEventBody()

    data class TaskCreated(val task: WorkTask) : WorkEventBody()

    data class TaskTransitioned(
        val taskId: String,
        val from: WorkTaskState,
        val to: WorkTaskState,
        val revision: Int,
        val blocker: WorkBlocker? = null
    ) : WorkEventBody()

    data class MemberAttached(
        val membershipOperationId: String,
        val agentId: String,
        val role: WorkRole,
        val membershipRevision: Int
    ) : WorkEventBody()

    data class MemberDetached(
        val membershipOperationId: String,
        val agentId: String,
        val membershipRevision: Int
    ) : WorkEventBody()

    data class DiscussionStarted(val triggerEventIds: List<String>) : WorkEventBody()

    data class DiscussionFinished(
        val discussionId: String,
        val status: String,
        val error: String? = null
    ) : WorkEventBody()

    data class WorkRequested(
        val agentId: String,
        val instruction: String,
        val membershipRevision: Int,
        val taskId: String? = null,
        val inputAfterSeq: Int? = null
    ) : WorkEventBody()

    data class ExecutionFinished(
        val executionId: String,
        val sourceEventId: String,
        val agentId: String,
        val status: String,
        val taskId: String? = null,
        val error: String? = null
    ) : WorkEventBody()
}

data class WorkInterruption(
    val eventId: String,
    val error: String,
    val kind: String,
    val agentId: String? = null,
    val taskId: String? = null
)

data class WorkSnapshot(
    val discussionRunning: Boolean,
    val interruptions: List<WorkInterruption>,
    val throughSeq: Int,
    val profile: WorkProfile,
    val members: List<AgentView>,
    val catalog: WorkCatalog,
    val events: List<WorkEvent>,
    val tasks: List<WorkTaskView>,
    val chat: List<WorkEvent>
)

data class WorkCreateParams(val name: String, val kind: WorkKind? = null)

data class WorkUpdateParams(val id: String, val kind: WorkKind? = null, val name: String? = null)

data class WorkPostMessageParams(
    val workId: String,
    val body: String,
    val mentionedAgentIds: List<String> = emptyList(),
    val clientEventId: String? = null,
    val inputAfterSeq: Int? = null
)

data class WorkMemberAttachParams(
    val workId: String,
    val agentId: String,
    val expectedRevision: Int,
    val role: WorkRole = WorkRole.WORKER
)

data class WorkMemberDetachParams(
    val workId: String,
    val agentId: String,
    val expectedRevision: Int
)

data class WorkMemberMoveParams(
    val fromWorkId: String,
    val toWorkId: String,
    val agentId: String,
    val expectedRevision: Int,
    val role: WorkRole = WorkRole.WORKER
)

data class WorkTaskTranscriptParams(
    val workId: String,
    val taskId: String,
    val sessionId: String? = null,
    val beforeSeq: Int? = null
)

data class WorkTaskTransitionParams(
    val workId: String,
    val taskId: String,
    val to: WorkTaskState,
    val expectedRevision: Int,
    val blocker: WorkBlocker? = null
)

data class WorkDispatchParams(
    val workId: String,
    val agentId: String,
    val instruction: String,
    val taskId: String? = null
)

data class WorkCatalogAddParams(
    val workId: String,
    val expectedRevision: Int,
    val entry: WorkCatalogInput
)

data class WorkCatalogRemoveParams(
    val workId: String,
    val entryId: String,
    val expectedRevision: Int
)

data class WorkContinueParams(
    val workId: String,
    val eventId: String,
    val inputAfterSeq: Int? = null
)
