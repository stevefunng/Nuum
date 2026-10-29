package com.nuum.feature.work

import com.nuum.contracts.AgentAnswerWidgetParams
import com.nuum.contracts.AgentCreateParams
import com.nuum.contracts.AgentPort
import com.nuum.contracts.AgentProfile
import com.nuum.contracts.AgentRuntime
import com.nuum.contracts.AgentSendParams
import com.nuum.contracts.AgentSettings
import com.nuum.contracts.AgentSnapshot
import com.nuum.contracts.AgentStatus
import com.nuum.contracts.AgentUpdateParams
import com.nuum.contracts.AgentView
import com.nuum.contracts.DesktopPort
import com.nuum.contracts.HostEvent
import com.nuum.contracts.ModelRef
import com.nuum.contracts.PickedFile
import com.nuum.contracts.ProviderId
import com.nuum.contracts.SendResult
import com.nuum.contracts.ToolResolution
import com.nuum.contracts.TranscriptPage
import com.nuum.contracts.TranscriptQuery
import com.nuum.contracts.WorkActor
import com.nuum.contracts.WorkBinding
import com.nuum.contracts.WorkBlocker
import com.nuum.contracts.WorkCatalog
import com.nuum.contracts.WorkCatalogAddParams
import com.nuum.contracts.WorkCatalogEntry
import com.nuum.contracts.WorkCatalogInput
import com.nuum.contracts.WorkCatalogRemoveParams
import com.nuum.contracts.WorkContinueParams
import com.nuum.contracts.WorkCreateParams
import com.nuum.contracts.WorkDispatchParams
import com.nuum.contracts.WorkEvent
import com.nuum.contracts.WorkEventBody
import com.nuum.contracts.WorkGrants
import com.nuum.contracts.WorkInterruption
import com.nuum.contracts.WorkKind
import com.nuum.contracts.WorkListItem
import com.nuum.contracts.WorkMemberAttachParams
import com.nuum.contracts.WorkMemberDetachParams
import com.nuum.contracts.WorkMemberMoveParams
import com.nuum.contracts.WorkMembership
import com.nuum.contracts.WorkPort
import com.nuum.contracts.WorkPostMessageParams
import com.nuum.contracts.WorkProfile
import com.nuum.contracts.WorkRole
import com.nuum.contracts.WorkSnapshot
import com.nuum.contracts.WorkTask
import com.nuum.contracts.WorkTaskPriority
import com.nuum.contracts.WorkTaskState
import com.nuum.contracts.WorkTaskTranscriptParams
import com.nuum.contracts.WorkTaskTransitionParams
import com.nuum.contracts.WorkTaskView
import com.nuum.contracts.WorkUpdateParams
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import java.util.Collections

internal class FakeWorkPort(
    initial: WorkSnapshot,
) : WorkPort {
    override val events: MutableSharedFlow<HostEvent> = MutableSharedFlow(extraBufferCapacity = 8)
    var snapshot: WorkSnapshot = initial
    val updates: MutableList<WorkUpdateParams> = Collections.synchronizedList(mutableListOf())
    val transitions: MutableList<WorkTaskTransitionParams> = Collections.synchronizedList(mutableListOf())
    val catalogAdds: MutableList<WorkCatalogAddParams> = Collections.synchronizedList(mutableListOf())
    val creates: MutableList<WorkCreateParams> = Collections.synchronizedList(mutableListOf())

    override suspend fun create(params: WorkCreateParams): WorkProfile {
        creates += params
        return WorkProfile(
            id = "created",
            name = params.name,
            description = "",
            projectRoot = null,
            createdAt = 0L,
            kind = params.kind,
        )
    }

    override suspend fun list(): List<WorkListItem> = emptyList()

    override suspend fun get(id: String): WorkSnapshot = snapshot

    override suspend fun update(params: WorkUpdateParams): WorkProfile {
        updates += params
        val next = snapshot.profile.copy(
            kind = params.kind ?: snapshot.profile.kind,
            name = params.name ?: snapshot.profile.name,
        )
        snapshot = snapshot.copy(profile = next)
        return next
    }

    override suspend fun postMessage(params: WorkPostMessageParams): WorkEvent =
        WorkEvent(
            type = "chat.posted",
            id = "posted",
            workId = params.workId,
            seq = snapshot.throughSeq + 1,
            createdAt = 0L,
            actor = WorkActor.User("local-user"),
            body = WorkEventBody.ChatPosted("posted", params.body, params.mentionedAgentIds),
        )

    override suspend fun attachMember(params: WorkMemberAttachParams) = Unit
    override suspend fun detachMember(params: WorkMemberDetachParams) = Unit
    override suspend fun moveMember(params: WorkMemberMoveParams) = Unit
    override suspend fun continueDiscussion(params: WorkContinueParams) = Unit
    override suspend fun stopDiscussion(workId: String) = Unit

    override suspend fun taskTranscript(params: WorkTaskTranscriptParams): TranscriptPage =
        TranscriptPage(id = params.sessionId ?: "session", entries = emptyList())

    override suspend fun transitionTask(params: WorkTaskTransitionParams): WorkTaskView {
        transitions += params
        val current = snapshot.tasks.first { it.task.id == params.taskId }.task
        val next = current.copy(state = params.to, revision = current.revision + 1, blocker = params.blocker ?: current.blocker)
        val view = WorkTaskView(next, emptyList())
        snapshot = snapshot.copy(tasks = snapshot.tasks.map { if (it.task.id == params.taskId) view else it })
        return view
    }

    override suspend fun dispatch(params: WorkDispatchParams) = Unit

    override suspend fun addCatalog(params: WorkCatalogAddParams): WorkCatalog {
        catalogAdds += params
        val entry = params.entry.toEntry("entry-${catalogAdds.size}")
        val catalog = snapshot.catalog.copy(
            revision = snapshot.catalog.revision + 1,
            entries = snapshot.catalog.entries + entry,
        )
        snapshot = snapshot.copy(catalog = catalog)
        return catalog
    }

    override suspend fun removeCatalog(params: WorkCatalogRemoveParams): WorkCatalog {
        val catalog = snapshot.catalog.copy(
            revision = snapshot.catalog.revision + 1,
            entries = snapshot.catalog.entries.filterNot { it.id == params.entryId },
        )
        snapshot = snapshot.copy(catalog = catalog)
        return catalog
    }
}

internal class FakeAgentPort : AgentPort {
    override val events: Flow<HostEvent> = MutableSharedFlow(extraBufferCapacity = 8)
    override suspend fun list(): List<AgentView> = emptyList()
    override suspend fun get(id: String): AgentSnapshot = AgentSnapshot(
        view = member(id, id, canManage = true),
        events = emptyList(),
        blocks = emptyList(),
        live = null,
    )
    override suspend fun create(params: AgentCreateParams): AgentView = member("new", params.name ?: "Nunu", true)
    override suspend fun update(params: AgentUpdateParams): AgentView = member(params.id, params.name ?: params.id, true)
    override suspend fun delete(id: String) = Unit
    override suspend fun transcript(query: TranscriptQuery): TranscriptPage = TranscriptPage(query.id, emptyList())
    override suspend fun send(params: AgentSendParams): SendResult = SendResult("run", false)
    override suspend fun answerWidget(params: AgentAnswerWidgetParams): SendResult = SendResult("run", false)
    override suspend fun cancel(id: String) = Unit
    override suspend fun approve(id: String, toolCallId: String, resolution: ToolResolution) = Unit
    override suspend fun deny(id: String, toolCallId: String, resolution: ToolResolution) = Unit
}

internal class FakeDesktopPort : DesktopPort {
    var directory: String? = null
    override suspend fun pickDirectory(): String? = directory
    override suspend fun pickFiles(): List<PickedFile> = emptyList()
    override suspend fun openAttachment(path: String) = Unit
    override suspend fun share(path: String) = Unit
}

internal fun member(id: String, name: String, canManage: Boolean, workId: String = "work-1"): AgentView {
    val grants = WorkGrants(
        canPost = true,
        canManageOwnTasks = canManage,
        canAssignTasks = false,
        canEditCatalog = false,
    )
    val binding = WorkBinding(workId, WorkRole.WORKER, 0L, grants)
    val membership = WorkMembership(revision = 1, binding = binding)
    return AgentView(
        profile = AgentProfile(id = id, name = name, description = "", createdAt = 0L, avatarColor = "blue"),
        settings = AgentSettings(
            model = ModelRef(ProviderId.DEEPSEEK, "deepseek-chat"),
            workMembership = membership,
        ),
        runtime = AgentRuntime(status = AgentStatus.IDLE, unread = false, lastActivityAt = 0L),
        roomMemberships = mapOf(workId to membership),
    )
}

internal fun workSnapshot(
    kind: WorkKind,
    tasks: List<WorkTaskView> = emptyList(),
    members: List<AgentView> = emptyList(),
    interruptions: List<WorkInterruption> = emptyList(),
    name: String = "NunuBar · Launch",
): WorkSnapshot = WorkSnapshot(
    discussionRunning = false,
    interruptions = interruptions,
    throughSeq = 0,
    profile = WorkProfile(
        id = "work-1",
        name = name,
        description = "",
        projectRoot = null,
        createdAt = 0L,
        kind = kind,
    ),
    members = members,
    catalog = WorkCatalog(revision = 0, entries = emptyList()),
    events = emptyList(),
    tasks = tasks,
    chat = emptyList(),
)

internal fun blockedTask(reason: String, revision: Int = 4): WorkTaskView {
    val task = WorkTask(
        id = "task-1",
        title = "Write spec",
        description = "Cover the board",
        acceptanceCriteria = listOf("Reason is kept"),
        state = WorkTaskState.BLOCKED,
        assigneeIds = listOf("ada"),
        dependencyIds = emptyList(),
        priority = WorkTaskPriority.HIGH,
        revision = revision,
        deliverables = emptyList(),
        createdAt = 0L,
        updatedAt = 0L,
        ownerAgentId = "ada",
        blocker = WorkBlocker(reason = reason),
    )
    return WorkTaskView(task, listOf(WorkTaskState.IN_PROGRESS, WorkTaskState.CANCELLED))
}

private fun WorkCatalogInput.toEntry(id: String): WorkCatalogEntry = when (this) {
    is WorkCatalogInput.Skill -> WorkCatalogEntry.Skill(id, name, description, true, manifestPath)
    is WorkCatalogInput.Cli -> WorkCatalogEntry.Cli(id, name, description, true, executable, allowedSubcommands)
    is WorkCatalogInput.Knowledge -> WorkCatalogEntry.Knowledge(id, name, description, true, roots, readOnly)
    is WorkCatalogInput.LocalTool -> WorkCatalogEntry.LocalTool(id, name, description, true, toolNames)
}
