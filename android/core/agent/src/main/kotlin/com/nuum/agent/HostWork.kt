package com.nuum.agent

import com.nuum.contracts.HostErrorCode
import com.nuum.contracts.HostEvent
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NuumException
import com.nuum.contracts.NuumPaths
import com.nuum.contracts.TranscriptPage
import com.nuum.contracts.WorkCatalog
import com.nuum.contracts.WorkCatalogAddParams
import com.nuum.contracts.WorkCatalogInput
import com.nuum.contracts.WorkCatalogRemoveParams
import com.nuum.contracts.WorkContinueParams
import com.nuum.contracts.WorkCreateParams
import com.nuum.contracts.WorkDispatchParams
import com.nuum.contracts.WorkEvent as CWorkEvent
import com.nuum.contracts.WorkInterruption
import com.nuum.contracts.WorkListItem
import com.nuum.contracts.WorkMemberAttachParams
import com.nuum.contracts.WorkMemberDetachParams
import com.nuum.contracts.WorkMemberMoveParams
import com.nuum.contracts.WorkPostMessageParams
import com.nuum.contracts.WorkProfile as CWorkProfile
import com.nuum.contracts.WorkSnapshot
import com.nuum.contracts.WorkTaskTranscriptParams
import com.nuum.contracts.WorkTaskTransitionParams
import com.nuum.contracts.WorkTaskView
import com.nuum.contracts.WorkUpdateParams
import com.nuum.protocol.DiscussionFinishStatus
import com.nuum.protocol.EMPTY_WORK_CATALOG
import com.nuum.protocol.WorkActor
import com.nuum.protocol.WorkCatalog as PWorkCatalog
import com.nuum.protocol.WorkCatalogEntry as PCatalog
import com.nuum.protocol.WorkEvent
import com.nuum.protocol.WorkKind
import com.nuum.protocol.WorkProfile
import java.io.File
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.yield

internal suspend fun HostRuntime.createWork(params: WorkCreateParams): CWorkProfile {
    ensureLoaded()
    val name = params.name.trim()
    if (name.isEmpty()) throw NuumException(KernelErrorCode.INVALID, "Work name is required")
    return gate.withLock {
        val id = ids()
        val workspaceId = ids()
        val root = if (nuumRoot.isBlank()) null else File(nuumRoot, NuumPaths.managedWorkspaceDir(workspaceId)).apply { mkdirs() }.path
        val profile = WorkProfile(
            kind = params.kind?.toProtocol() ?: WorkKind.WORK,
            id = id,
            name = name,
            description = "",
            projectRoot = root,
            workspaceId = workspaceId,
            createdAt = clock.nowMillis()
        )
        store.writeDoc(NuumPaths.workProfilePath(id), WorkProfile.serializer(), profile)
        store.writeDoc(NuumPaths.workCatalogPath(id), PWorkCatalog.serializer(), EMPTY_WORK_CATALOG)
        works[id] = WorkRecord(profile, 0, profile.createdAt)
        val view = profile.toContract()
        emit(HostEvent.WorkUpdated(view))
        view
    }
}

internal suspend fun HostRuntime.listWorkItems(): List<WorkListItem> {
    ensureLoaded()
    return gate.withLock {
        works.values.map { record ->
            val preview = store.readWorkEvents(NuumPaths.workTimelinePath(record.profile.id))
                .filterIsInstance<WorkEvent.ChatPosted>()
                .lastOrNull()
                ?.body
            WorkListItem(record.profile.toContract(), record.lastActivityAt, preview)
        }
    }
}

internal suspend fun HostRuntime.workSnapshot(id: String): WorkSnapshot {
    ensureLoaded()
    return gate.withLock {
        val record = works[id] ?: throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Work not found")
        val events = store.readWorkEvents(NuumPaths.workTimelinePath(id))
        val catalog = store.readDoc(NuumPaths.workCatalogPath(id), PWorkCatalog.serializer()) ?: EMPTY_WORK_CATALOG
        val members = agents.values.filter { membershipOf(id, it.profile.id).binding != null }.map { viewOf(it) }
        val tasks = foldTasks(events)
        val chat = events.mapNotNull { event ->
            val mapped = event.toContract() ?: return@mapNotNull null
            if (mapped.body is com.nuum.contracts.WorkEventBody.ChatPosted) mapped else null
        }
        val live = discussions[id]
        WorkSnapshot(
            discussionRunning = live != null && !live.stopped,
            interruptions = interruptions(events),
            throughSeq = events.maxOfOrNull { it.seq } ?: 0,
            profile = record.profile.toContract(),
            members = members,
            catalog = catalog.toContract(),
            events = events.mapNotNull { it.toContract() },
            tasks = tasks.map { task ->
                val role = TaskActorRole.USER
                WorkTaskView(task.toContract(), allowedTaskTransitions(task.state, role).map { it.toContract() })
            },
            chat = chat
        )
    }
}

internal suspend fun HostRuntime.updateWork(params: WorkUpdateParams): CWorkProfile {
    ensureLoaded()
    return gate.withLock {
        val record = works[params.id] ?: throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Work not found")
        record.profile = record.profile.copy(
            kind = params.kind?.toProtocol() ?: record.profile.kind,
            name = params.name?.trim()?.ifEmpty { null } ?: record.profile.name
        )
        store.writeDoc(NuumPaths.workProfilePath(params.id), WorkProfile.serializer(), record.profile)
        val view = record.profile.toContract()
        emit(HostEvent.WorkUpdated(view))
        view
    }
}

internal suspend fun HostRuntime.postWorkMessage(params: WorkPostMessageParams): CWorkEvent {
    ensureLoaded()
    val event = gate.withLock {
        if (works[params.workId] == null) throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Work not found")
        val body = params.body.trim()
        if (body.isEmpty()) throw NuumException(KernelErrorCode.INVALID, "Message body is required")
        val timeline = store.readWorkEvents(NuumPaths.workTimelinePath(params.workId))
        val inputAfter = params.inputAfterSeq
        if (inputAfter != null && inputAfter > (timeline.maxOfOrNull { it.seq } ?: 0)) {
            throw NuumException(KernelErrorCode.INVALID, "Invalid room history start sequence")
        }
        if (params.clientEventId != null) {
            val previous = timeline.find { it.clientEvent() == params.clientEventId }
            if (previous != null) return@withLock previous
        }
        appendWork(params.workId) { seq ->
            WorkEvent.ChatPosted(
                id = ids(),
                workId = params.workId,
                seq = seq,
                createdAt = clock.nowMillis(),
                actor = WorkActor.User("local-user"),
                messageId = ids(),
                body = body,
                mentionedAgentIds = params.mentionedAgentIds,
                inputAfterSeq = params.inputAfterSeq,
                clientEventId = params.clientEventId
            )
        }
    }
    enqueueDiscussion(params.workId, event.id)
    return event.toContract() ?: throw NuumException(KernelErrorCode.INTERNAL, "Work event could not be projected")
}

internal suspend fun HostRuntime.attach(params: WorkMemberAttachParams) {
    ensureLoaded()
    gate.withLock {
        if (works[params.workId] == null) throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Work not found")
        requireAgent(params.agentId)
        val current = membershipOf(params.workId, params.agentId)
        if (current.revision != params.expectedRevision) {
            throw NuumException(HostErrorCode.WORK_CONFLICT, "Membership revision conflict")
        }
        appendWork(params.workId) { seq ->
            WorkEvent.MemberAttached(
                id = ids(),
                workId = params.workId,
                seq = seq,
                createdAt = clock.nowMillis(),
                actor = WorkActor.User("local-user"),
                membershipOperationId = ids(),
                agentId = params.agentId,
                role = params.role.toProtocol(),
                membershipRevision = current.revision + 1
            )
        }
    }
}

internal suspend fun HostRuntime.detach(params: WorkMemberDetachParams) {
    ensureLoaded()
    gate.withLock {
        if (works[params.workId] == null) throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Work not found")
        val current = membershipOf(params.workId, params.agentId)
        if (current.revision != params.expectedRevision) {
            throw NuumException(HostErrorCode.WORK_CONFLICT, "Membership revision conflict")
        }
        appendWork(params.workId) { seq ->
            WorkEvent.MemberDetached(
                id = ids(),
                workId = params.workId,
                seq = seq,
                createdAt = clock.nowMillis(),
                actor = WorkActor.User("local-user"),
                membershipOperationId = ids(),
                agentId = params.agentId,
                membershipRevision = current.revision + 1
            )
        }
    }
}

internal suspend fun HostRuntime.move(@Suppress("UNUSED_PARAMETER") params: WorkMemberMoveParams) {
    throw NuumException(
        HostErrorCode.WORK_CONFLICT,
        "Rooms now have independent membership. Attach to the new room, then explicitly remove from the old room."
    )
}

internal suspend fun HostRuntime.continueRoom(params: WorkContinueParams) {
    ensureLoaded()
    if (works[params.workId] == null) throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Work not found")
    enqueueDiscussion(params.workId, params.eventId)
}

internal suspend fun HostRuntime.stopRoom(workId: String) {
    ensureLoaded()
    if (works[workId] == null) throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Work not found")
    discussions[workId]?.stopped = true
    discussionQueues.remove(workId)
    agents.keys.filter { scheduler.contextFor(scheduler.activeRunFor(it) ?: "") is RunContext.Work }.forEach { id ->
        val run = scheduler.activeRunFor(id) ?: return@forEach
        val context = scheduler.contextFor(run) as? RunContext.Work ?: return@forEach
        if (context.workId == workId) {
            scheduler.cancelAgent(id)
            kernel.cancel(run)
        }
    }
}

internal suspend fun HostRuntime.readTaskTranscript(params: WorkTaskTranscriptParams): TranscriptPage {
    ensureLoaded()
    if (works[params.workId] == null) throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Work not found")
    val task = tasksOf(params.workId).find { it.id == params.taskId }
        ?: throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Card not found")
    val owner = task.ownerAgentId
    val session = if (owner == null) null else cardSession(params.workId, params.taskId, owner, membershipOf(params.workId, owner).revision)
    val path = session?.let { "${cardSessionDir(it)}/transcript.jsonl" }
    val events = if (path == null) emptyList() else store.readTranscript(path)
    val before = params.beforeSeq
    val filtered = events.filter { before == null || it.seq < before }
    return TranscriptPage(params.taskId, filtered.map { it.toContract() }, null)
}

internal suspend fun HostRuntime.transition(params: WorkTaskTransitionParams): WorkTaskView {
    ensureLoaded()
    if (works[params.workId] == null) throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Work not found")
    val task = tasksOf(params.workId).find { it.id == params.taskId }
        ?: throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Card not found")
    if (task.revision != params.expectedRevision) {
        throw NuumException(HostErrorCode.WORK_CONFLICT, "Card revision conflict")
    }
    if (params.to == com.nuum.contracts.WorkTaskState.BLOCKED && params.blocker?.reason.isNullOrBlank()) {
        throw NuumException(KernelErrorCode.INVALID, "A blocked card needs a reason.")
    }
    return try {
        val next = transitionCard(
            params.workId,
            params.taskId,
            params.to.toProtocol(),
            params.blocker?.reason,
            TaskActorRole.USER
        )
        WorkTaskView(next.toContract(), allowedTaskTransitions(next.state, TaskActorRole.USER).map { it.toContract() })
    } catch (error: IllegalArgumentException) {
        throw NuumException(HostErrorCode.WORK_CONFLICT, error.message ?: "Transition refused")
    }
}

internal suspend fun HostRuntime.dispatchWork(params: WorkDispatchParams) {
    ensureLoaded()
    if (works[params.workId] == null) throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Work not found")
    requireAgent(params.agentId)
    val membership = membershipOf(params.workId, params.agentId)
    if (membership.binding?.grants?.canPost != true) {
        throw NuumException(HostErrorCode.WORK_FORBIDDEN, "Agent cannot execute in this room")
    }
    val context = RunContext.Work(
        workId = params.workId,
        bridgeId = ids(),
        taskId = params.taskId,
        instruction = params.instruction,
        membershipRevision = membership.revision
    )
    gate.withLock {
        appendWork(params.workId) { seq ->
            WorkEvent.WorkRequested(
                id = ids(),
                workId = params.workId,
                seq = seq,
                createdAt = clock.nowMillis(),
                actor = WorkActor.User("local-user"),
                agentId = params.agentId,
                taskId = params.taskId,
                instruction = params.instruction,
                membershipRevision = membership.revision
            )
        }
    }
    scheduler.submit(
        AgentScheduler.RunRequest(params.agentId, context, works[params.workId]?.profile?.projectRoot) { runId ->
            beginTurn(params.agentId, runId, context)
        }
    )
}

internal suspend fun HostRuntime.addCatalogEntry(params: WorkCatalogAddParams): WorkCatalog {
    ensureLoaded()
    return gate.withLock {
        if (works[params.workId] == null) throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Work not found")
        val current = store.readDoc(NuumPaths.workCatalogPath(params.workId), PWorkCatalog.serializer()) ?: EMPTY_WORK_CATALOG
        if (current.revision != params.expectedRevision) {
            throw NuumException(HostErrorCode.WORK_CONFLICT, "Catalog revision conflict")
        }
        val entry = catalogEntry(params.entry)
        val next = current.copy(revision = current.revision + 1, entries = current.entries + entry)
        store.writeDoc(NuumPaths.workCatalogPath(params.workId), PWorkCatalog.serializer(), next)
        val view = next.toContract()
        emit(HostEvent.WorkCatalogUpdated(params.workId, view))
        view
    }
}

internal suspend fun HostRuntime.removeCatalogEntry(params: WorkCatalogRemoveParams): WorkCatalog {
    ensureLoaded()
    return gate.withLock {
        if (works[params.workId] == null) throw NuumException(HostErrorCode.WORK_NOT_FOUND, "Work not found")
        val current = store.readDoc(NuumPaths.workCatalogPath(params.workId), PWorkCatalog.serializer()) ?: EMPTY_WORK_CATALOG
        if (current.revision != params.expectedRevision) {
            throw NuumException(HostErrorCode.WORK_CONFLICT, "Catalog revision conflict")
        }
        val next = current.copy(revision = current.revision + 1, entries = current.entries.filter { it.id != params.entryId })
        store.writeDoc(NuumPaths.workCatalogPath(params.workId), PWorkCatalog.serializer(), next)
        val view = next.toContract()
        emit(HostEvent.WorkCatalogUpdated(params.workId, view))
        view
    }
}

internal suspend fun HostRuntime.appendWork(workId: String, build: (seq: Int) -> WorkEvent): WorkEvent {
    val path = NuumPaths.workTimelinePath(workId)
    val existing = store.readWorkEvents(path)
    val event = build((existing.maxOfOrNull { it.seq } ?: 0) + 1)
    store.appendWork(path, event)
    applyMembership(event)
    works[workId]?.let {
        it.lastSeq = event.seq
        it.lastActivityAt = maxOf(it.lastActivityAt, event.createdAt)
    }
    event.toContract()?.let { emit(HostEvent.WorkEventAppended(workId, it)) }
    return event
}

private fun HostRuntime.enqueueDiscussion(workId: String, eventId: String) {
    val queue = discussionQueues.getOrPut(workId) { ArrayDeque() }
    if (eventId !in queue) queue.addLast(eventId)
    discussions[workId]?.superseded = true
    if (discussionJobs[workId] != null) return
    val job = supervisor.launch {
        try {
            driveDiscussion(workId)
        } finally {
            discussionJobs.remove(workId)
            if (discussionQueues[workId]?.isNotEmpty() == true) {
                val next = discussionQueues[workId]?.firstOrNull()
                if (next != null) enqueueDiscussion(workId, next)
            }
        }
    }
    discussionJobs[workId] = job
}

private suspend fun HostRuntime.driveDiscussion(workId: String) {
    while (discussionQueues[workId]?.isNotEmpty() == true) {
        val triggers = discussionQueues[workId]?.toList().orEmpty()
        discussionQueues[workId]?.clear()
        val id = ids()
        val live = LiveDiscussion(id, triggers)
        discussions[workId] = live
        gate.withLock {
            appendWork(workId) { seq ->
                WorkEvent.DiscussionStarted(
                    id = id,
                    workId = workId,
                    seq = seq,
                    createdAt = clock.nowMillis(),
                    actor = WorkActor.SystemActor("host"),
                    triggerEventIds = triggers.ifEmpty { listOf(id) }
                )
            }
        }
        var failed = false
        var errorText: String? = null
        try {
            val members = agents.values.mapNotNull { record ->
                val binding = membershipOf(workId, record.profile.id).binding ?: return@mapNotNull null
                if (!binding.grants.canPost) return@mapNotNull null
                DiscussionMember(record.profile.id, record.profile.name)
            }
            runDiscussion(
                current = { !live.stopped && !live.superseded },
                responders = {
                    val events = store.readWorkEvents(NuumPaths.workTimelinePath(workId))
                    val messages = events.filterIsInstance<WorkEvent.ChatPosted>()
                        .filter { it.id in triggers || live.replies.any { reply -> reply.body == it.body } }
                        .map { MentionedMessage(it.body, it.mentionedAgentIds) }
                    discussionResponders(members, messages).map { it.id }
                },
                runMember = { agentId ->
                    val before = live.total
                    val context = RunContext.Work(
                        workId = workId,
                        bridgeId = ids(),
                        discussionId = id,
                        instruction = "Discuss the room. Use SendMessage for at most two short replies.",
                        membershipRevision = membershipOf(workId, agentId).revision
                    )
                    val submitted = scheduler.submit(
                        AgentScheduler.RunRequest(agentId, context, works[workId]?.profile?.projectRoot) { runId ->
                            live.runId = runId
                            beginTurn(agentId, runId, context)
                        }
                    )
                    val outcome = try {
                        submitted.started?.await()
                        submitted.completed.await()
                    } catch (_: Exception) {
                        RunOutcome.FAILED
                    }
                    if (outcome == RunOutcome.FAILED) failed = true
                    MemberTurn(live.total - before, outcome == RunOutcome.FAILED)
                }
            )
        } catch (error: Exception) {
            failed = true
            errorText = error.message
        } finally {
            discussions.remove(workId)
            val status = when {
                live.stopped -> DiscussionFinishStatus.CANCELLED
                failed && !live.superseded -> DiscussionFinishStatus.INTERRUPTED
                else -> DiscussionFinishStatus.COMPLETED
            }
            gate.withLock {
                appendWork(workId) { seq ->
                    WorkEvent.DiscussionFinished(
                        id = ids(),
                        workId = workId,
                        seq = seq,
                        createdAt = clock.nowMillis(),
                        actor = WorkActor.SystemActor("host"),
                        discussionId = id,
                        status = status,
                        error = errorText
                    )
                }
            }
        }
        yield()
    }
}

private fun interruptions(events: List<WorkEvent>): List<WorkInterruption> =
    events.filterIsInstance<WorkEvent.DiscussionFinished>()
        .filter { it.status == DiscussionFinishStatus.INTERRUPTED }
        .map { WorkInterruption(it.id, it.error ?: "Discussion interrupted", "discussion", null, null) }

private fun catalogEntry(input: WorkCatalogInput): PCatalog {
    val id = java.util.UUID.randomUUID().toString()
    return when (input) {
        is WorkCatalogInput.Skill -> PCatalog.Skill(id, input.name, input.description, true, input.manifestPath)
        is WorkCatalogInput.Cli -> PCatalog.Cli(id, input.name, input.description, true, input.executable, input.allowedSubcommands)
        is WorkCatalogInput.Knowledge -> {
            if (!input.readOnly) throw NuumException(KernelErrorCode.INVALID, "knowledge catalog entries are readOnly")
            PCatalog.Knowledge(id, input.name, input.description, true, input.roots, true)
        }
        is WorkCatalogInput.LocalTool -> PCatalog.LocalTool(id, input.name, input.description, true, input.toolNames)
    }
}

private fun WorkEvent.clientEvent(): String? = when (this) {
    is WorkEvent.ChatPosted -> clientEventId
    else -> null
}
