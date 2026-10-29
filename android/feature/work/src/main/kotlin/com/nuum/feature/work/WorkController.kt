package com.nuum.feature.work

import com.nuum.contracts.AgentView
import com.nuum.contracts.HostEvent
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.ToolResolution
import com.nuum.contracts.TranscriptPage
import com.nuum.contracts.WorkCatalog
import com.nuum.contracts.WorkCatalogAddParams
import com.nuum.contracts.WorkCatalogInput
import com.nuum.contracts.WorkCatalogRemoveParams
import com.nuum.contracts.WorkContinueParams
import com.nuum.contracts.WorkDispatchParams
import com.nuum.contracts.WorkKind
import com.nuum.contracts.WorkMemberAttachParams
import com.nuum.contracts.WorkMemberDetachParams
import com.nuum.contracts.WorkPostMessageParams
import com.nuum.contracts.WorkRole
import com.nuum.contracts.WorkSnapshot
import com.nuum.contracts.WorkTask
import com.nuum.contracts.WorkTaskState
import com.nuum.contracts.WorkTaskTranscriptParams
import com.nuum.contracts.WorkTaskTransitionParams
import com.nuum.contracts.WorkUpdateParams
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.UUID

internal data class PendingApproval(
    val agentId: String,
    val toolCallId: String,
    val action: LocalToolAction,
    val target: String,
    val justification: String?,
    val allowAlways: Boolean,
    val details: String?,
)

internal data class WorkUiState(
    val loading: Boolean = true,
    val snapshot: WorkSnapshot? = null,
    val notice: String? = null,
    val approvals: List<PendingApproval> = emptyList(),
)

internal class WorkController(
    private val workId: String,
    private val ports: WorkPorts,
) {
    val state = MutableStateFlow(WorkUiState())
    private val gate = Mutex()
    private var scope: CoroutineScope? = null

    suspend fun activate(scope: CoroutineScope) {
        this.scope = scope
        reload()
        kotlinx.coroutines.coroutineScope {
            launch { observeWork() }
            launch { observeAgents() }
        }
    }

    fun upgrade() = launchAction {
        ports.work.update(WorkUpdateParams(id = workId, kind = WorkKind.WORK))
        reload()
    }

    fun post(body: String) = launchAction {
        val trimmed = body.trim()
        if (trimmed.isEmpty()) return@launchAction
        ports.work.postMessage(
            WorkPostMessageParams(
                workId = workId,
                body = trimmed,
                mentionedAgentIds = emptyList(),
                clientEventId = UUID.randomUUID().toString(),
            ),
        )
        reload()
    }

    fun continueDiscussion(eventId: String, inputAfterSeq: Int? = null) = launchAction {
        ports.work.continueDiscussion(WorkContinueParams(workId, eventId, inputAfterSeq))
        reload()
    }

    fun stopDiscussion() = launchAction {
        ports.work.stopDiscussion(workId)
        reload()
    }

    fun detach(agentId: String, revision: Int) = launchAction {
        ports.work.detachMember(WorkMemberDetachParams(workId, agentId, revision))
        reload()
    }

    fun attach(agentId: String) = launchAction {
        val view = ports.agent.get(agentId).view
        val membership = view.roomMemberships[workId]
        if (membership?.binding != null) return@launchAction
        ports.work.attachMember(
            WorkMemberAttachParams(
                workId = workId,
                agentId = agentId,
                expectedRevision = membership?.revision ?: 0,
                role = WorkRole.WORKER,
            ),
        )
        reload()
    }

    suspend fun transition(task: WorkTask, to: WorkTaskState) {
        gate.withLock {
            val view = ports.work.transitionTask(
                WorkTaskTransitionParams(
                    workId = workId,
                    taskId = task.id,
                    to = to,
                    expectedRevision = task.revision,
                    blocker = blockerForTransition(task, to),
                ),
            )
            state.update { current ->
                val snapshot = current.snapshot ?: return@update current
                current.copy(
                    snapshot = snapshot.copy(
                        tasks = snapshot.tasks.map { if (it.task.id == view.task.id) view else it },
                    ),
                )
            }
        }
    }

    suspend fun dispatch(agentId: String, taskId: String, instruction: String) {
        gate.withLock {
            ports.work.dispatch(
                WorkDispatchParams(
                    workId = workId,
                    agentId = agentId,
                    instruction = instruction.trim(),
                    taskId = taskId,
                ),
            )
            reload()
        }
    }

    suspend fun loadTrace(taskId: String, sessionId: String?, beforeSeq: Int?): TranscriptPage =
        gate.withLock {
            ports.work.taskTranscript(
                WorkTaskTranscriptParams(
                    workId = workId,
                    taskId = taskId,
                    sessionId = sessionId,
                    beforeSeq = beforeSeq,
                ),
            )
        }

    suspend fun addCatalog(entry: WorkCatalogInput): WorkCatalog = gate.withLock {
        val revision = state.value.snapshot?.catalog?.revision ?: 0
        val catalog = ports.work.addCatalog(
            WorkCatalogAddParams(workId = workId, expectedRevision = revision, entry = entry),
        )
        state.update { current ->
            val snapshot = current.snapshot ?: return@update current
            current.copy(snapshot = snapshot.copy(catalog = catalog))
        }
        catalog
    }

    fun removeCatalog(entryId: String) = launchAction {
        val revision = state.value.snapshot?.catalog?.revision ?: 0
        val catalog = ports.work.removeCatalog(
            WorkCatalogRemoveParams(workId = workId, entryId = entryId, expectedRevision = revision),
        )
        state.update { current ->
            val snapshot = current.snapshot ?: return@update current
            current.copy(snapshot = snapshot.copy(catalog = catalog))
        }
    }

    suspend fun decide(approval: PendingApproval, resolution: ToolResolution) {
        if (resolution == ToolResolution.DENY) {
            ports.agent.deny(approval.agentId, approval.toolCallId, ToolResolution.DENY)
        } else {
            ports.agent.approve(approval.agentId, approval.toolCallId, resolution)
        }
        state.update { current ->
            current.copy(
                approvals = current.approvals.filterNot {
                    it.agentId == approval.agentId && it.toolCallId == approval.toolCallId
                },
            )
        }
    }

    suspend fun pickDirectory(): String? = ports.desktop.pickDirectory()

    private fun launchAction(block: suspend () -> Unit) {
        val scope = scope ?: return
        scope.launch {
            gate.withLock {
                state.update { it.copy(notice = null) }
                try {
                    block()
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (error: Exception) {
                    state.update { it.copy(notice = error.message) }
                }
            }
        }
    }

    private suspend fun reload() {
        try {
            val snapshot = ports.work.get(workId)
            state.update { it.copy(loading = false, snapshot = snapshot) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            state.update { it.copy(loading = false, notice = error.message) }
        }
    }

    private suspend fun observeWork() {
        ports.work.events.collect { event ->
            when (event) {
                is HostEvent.WorkUpdated -> if (event.work.id == workId) reload()
                is HostEvent.WorkEventAppended -> if (event.workId == workId) reload()
                is HostEvent.WorkCatalogUpdated -> if (event.workId == workId) reload()
                else -> Unit
            }
        }
    }

    private suspend fun observeAgents() {
        ports.agent.events.collect { event ->
            when (event) {
                is HostEvent.AgentToolPending -> onPending(event)
                is HostEvent.AgentToolStarted -> clearApproval(event.agentId, event.toolCallId)
                is HostEvent.AgentToolCompleted -> clearApproval(event.agentId, event.toolCallId)
                is HostEvent.AgentEnded -> clearAgent(event.agentId)
                is HostEvent.AgentError -> clearAgent(event.agentId)
                is HostEvent.AgentUpdated -> updateMember(event.agent)
                else -> Unit
            }
        }
    }

    private fun onPending(event: HostEvent.AgentToolPending) {
        val members = state.value.snapshot?.members.orEmpty()
        if (members.none { it.profile.id == event.agentId }) return
        val approval = PendingApproval(
            agentId = event.agentId,
            toolCallId = event.toolCallId,
            action = event.action,
            target = event.target,
            justification = event.justification,
            allowAlways = event.allowAlways != false,
            details = event.details,
        )
        state.update { current ->
            current.copy(
                approvals = current.approvals.filterNot {
                    it.agentId == approval.agentId && it.toolCallId == approval.toolCallId
                } + approval,
            )
        }
    }

    private fun clearApproval(agentId: String, toolCallId: String) {
        state.update { current ->
            current.copy(
                approvals = current.approvals.filterNot { it.agentId == agentId && it.toolCallId == toolCallId },
            )
        }
    }

    private fun clearAgent(agentId: String) {
        state.update { current ->
            current.copy(approvals = current.approvals.filterNot { it.agentId == agentId })
        }
    }

    private fun updateMember(agent: AgentView) {
        state.update { current ->
            val snapshot = current.snapshot ?: return@update current
            if (snapshot.members.none { it.profile.id == agent.profile.id }) return@update current
            current.copy(
                snapshot = snapshot.copy(
                    members = snapshot.members.map { if (it.profile.id == agent.profile.id) agent else it },
                ),
            )
        }
    }
}
