package com.nuum.agent

import com.nuum.contracts.AgentCreateParams
import com.nuum.contracts.HostEvent
import com.nuum.contracts.NuumException
import com.nuum.contracts.NuumPaths
import com.nuum.protocol.CreateAgentParams as ModelCreateAgent
import com.nuum.protocol.DelegatedToolNames
import com.nuum.protocol.OutboundMessage
import com.nuum.protocol.ProfilePatch
import com.nuum.protocol.ProtocolParseException
import com.nuum.protocol.TranscriptEvent
import com.nuum.protocol.UpdateStateParams
import com.nuum.protocol.WakeSource
import com.nuum.protocol.WorkActor
import com.nuum.protocol.WorkEvent
import com.nuum.protocol.WorkKind
import com.nuum.protocol.WorkTask
import com.nuum.protocol.WorkTaskPriority
import com.nuum.protocol.WorkTaskState
import com.nuum.protocol.normalizeAgentTags
import com.nuum.protocol.parseCheckAgent
import com.nuum.protocol.parseClaimTask
import com.nuum.protocol.parseCreateAgent
import com.nuum.protocol.parseCreateTask
import com.nuum.protocol.parseDelegateWork
import com.nuum.protocol.parseHandoffTask
import com.nuum.protocol.parsePostToWork
import com.nuum.protocol.parseReadAgentTranscript
import com.nuum.protocol.parseReadTask
import com.nuum.protocol.parseReadWorkTimeline
import com.nuum.protocol.parseRunWorkCli
import com.nuum.protocol.parseSendMessage
import com.nuum.protocol.parseSendToAgent
import com.nuum.protocol.parseStopAgent
import com.nuum.protocol.parseUpdateAgent
import com.nuum.protocol.parseUpdateState
import com.nuum.protocol.parseWorkSendMessage
import com.nuum.protocol.toolArgumentError
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonObject

internal suspend fun HostRuntime.executeDelegated(
    agentId: String,
    name: String,
    args: JsonObject,
    context: RunContext,
    toolCallId: String
): DelegatedOutcome {
    val available = delegatedNames(context)
    if (name !in available) {
        return DelegatedOutcome(false, "$name is not available in this run.", false)
    }
    return try {
        val text = when (name) {
            DelegatedToolNames.sendMessage -> if (context is RunContext.Work) {
                sendWorkMessage(agentId, parseWorkSendMessage(args), context, toolCallId)
            } else {
                deliverSendMessage(agentId, parseSendMessage(args), toolCallId)
            }
            DelegatedToolNames.updateState -> updateOwnState(agentId, parseUpdateState(args))
            DelegatedToolNames.createAgent -> createTeammate(agentId, parseCreateAgent(args))
            DelegatedToolNames.updateAgent -> updateTeammate(agentId, parseUpdateAgent(args))
            DelegatedToolNames.sendToAgent -> sendToTeammate(agentId, parseSendToAgent(args))
            DelegatedToolNames.readAgentTranscript -> readTeammate(parseReadAgentTranscript(args))
            DelegatedToolNames.checkAgent -> checkTeammate(agentId, parseCheckAgent(args).agentId)
            DelegatedToolNames.stopAgent -> stopTeammate(parseStopAgent(args).agentId)
            DelegatedToolNames.createTask -> createCard(agentId, parseCreateTask(args), context)
            DelegatedToolNames.claimTask -> claimCard(agentId, parseClaimTask(args), context)
            DelegatedToolNames.readTask -> readCard(parseReadTask(args).taskId, context)
            DelegatedToolNames.postToWork -> postProgress(agentId, parsePostToWork(args).message, context)
            DelegatedToolNames.handoffTask -> handoff(agentId, parseHandoffTask(args), context)
            DelegatedToolNames.readWorkTimeline -> readTimeline(parseReadWorkTimeline(args).limit, context)
            DelegatedToolNames.runWorkCli -> {
                parseRunWorkCli(args)
                return DelegatedOutcome(false, RUN_WORK_CLI_UNIMPLEMENTED, false)
            }
            DelegatedToolNames.delegateWork -> delegateCard(agentId, parseDelegateWork(args), context, toolCallId)
            else -> return DelegatedOutcome(false, "Unknown delegated tool: $name", false)
        }
        val endTurn = context is RunContext.Work && name == DelegatedToolNames.sendMessage &&
            (isPass(args["content"]?.toString()?.trim('"') ?: "") || discussionBudget(context))
        DelegatedOutcome(true, text, endTurn)
    } catch (error: ProtocolParseException) {
        DelegatedOutcome(false, toolArgumentError(name, error), false)
    }
}

private fun HostRuntime.delegatedNames(context: RunContext): Set<String> = when (context) {
    is RunContext.Direct -> setOf(
        DelegatedToolNames.sendMessage,
        DelegatedToolNames.updateState,
        DelegatedToolNames.createAgent,
        DelegatedToolNames.updateAgent,
        DelegatedToolNames.sendToAgent,
        DelegatedToolNames.readAgentTranscript,
        DelegatedToolNames.checkAgent,
        DelegatedToolNames.stopAgent
    )
    is RunContext.Work -> setOf(
        DelegatedToolNames.sendMessage,
        DelegatedToolNames.createTask,
        DelegatedToolNames.claimTask,
        DelegatedToolNames.readTask,
        DelegatedToolNames.readWorkTimeline,
        DelegatedToolNames.runWorkCli,
        DelegatedToolNames.delegateWork
    )
}

private fun HostRuntime.discussionBudget(context: RunContext.Work): Boolean {
    val bridge = context.bridgeId ?: return false
    val live = discussions[context.workId] ?: return false
    return (live.perExecution[bridge] ?: 0) >= discussionLimits.perTurn || live.total >= discussionLimits.messages
}

private suspend fun HostRuntime.deliverSendMessage(agentId: String, payload: OutboundMessage, toolCallId: String): String {
    val event = gate.withLock {
        requireAgent(agentId)
        appendTranscript(agentId) { seq ->
            TranscriptEvent.Message(
                id = ids(),
                seq = seq,
                createdAt = clock.nowMillis(),
                assistantId = liveParts[agentId]?.messageId,
                toolCallId = toolCallId,
                payload = payload
            )
        }
    }
    emit(HostEvent.AgentMessageCompleted(agentId, event.toContract()))
    return when (payload) {
        is OutboundMessage.Text -> "Delivered. (id: ${event.id})"
        is OutboundMessage.Attachment -> "Delivered ${payload.path}. (id: ${event.id})"
        is OutboundMessage.LegacyWidget -> "Delivered the ${payload.widget} widget."
        is OutboundMessage.Widget -> "Question delivered. (id: ${event.id}) Stop after this; the user's selection arrives as their next message."
    }
}

private suspend fun HostRuntime.sendWorkMessage(
    agentId: String,
    params: com.nuum.protocol.WorkSendMessageParams,
    context: RunContext.Work,
    toolCallId: String
): String {
    if (isPass(params.content)) return "Passed."
    val live = discussions[context.workId]
    val bridge = context.bridgeId
    if (live != null && bridge != null && (live.perExecution[bridge] ?: 0) >= discussionLimits.perTurn) {
        return "Discussion message budget reached. Stop this turn."
    }
    if (live != null && live.total >= discussionLimits.messages) {
        return "Discussion message budget reached. Stop this turn."
    }
    gate.withLock {
        appendWork(context.workId) { seq ->
            WorkEvent.ChatPosted(
                id = ids(),
                workId = context.workId,
                seq = seq,
                createdAt = clock.nowMillis(),
                actor = WorkActor.Agent(agentId),
                messageId = ids(),
                body = params.content,
                mentionedAgentIds = emptyList(),
                taskId = context.taskId,
                clientEventId = toolCallId
            )
        }
    }
    if (live != null && bridge != null) {
        live.total += 1
        live.perExecution[bridge] = (live.perExecution[bridge] ?: 0) + 1
        live.replies += MentionedMessage(params.content, emptyList())
    }
    params.cardAction?.let { action ->
        val to = if (action.status == "blocked") WorkTaskState.BLOCKED else WorkTaskState.REVIEW
        transitionCard(context.workId, context.taskId, to, action.blockerReason, TaskActorRole.WORKER)
    }
    return "Delivered to the room."
}

private suspend fun HostRuntime.updateOwnState(agentId: String, params: UpdateStateParams): String = when (params) {
    is UpdateStateParams.Profile -> gate.withLock {
        if (params.name == null && params.description == null && params.tags == null) {
            "Nothing to change: pass name, tags or description."
        } else {
            val record = requireAgent(agentId)
            record.profile = record.profile.copy(
                name = params.name?.trim() ?: record.profile.name,
                description = params.description?.trim() ?: record.profile.description,
                tags = params.tags ?: record.profile.tags
            )
            store.writeDoc(NuumPaths.profilePath(agentId), com.nuum.protocol.AgentProfile.serializer(), record.profile)
            val event = appendTranscript(agentId) { seq ->
                TranscriptEvent.Profile(
                    id = ids(),
                    seq = seq,
                    createdAt = clock.nowMillis(),
                    patch = ProfilePatch(params.name?.trim(), params.description?.trim(), params.tags)
                )
            }
            emit(HostEvent.AgentMessageCompleted(agentId, event.toContract()))
            emit(HostEvent.AgentUpdated(viewOf(record)))
            "Profile updated. You are now \"${record.profile.name}\"."
        }
    }
    is UpdateStateParams.Memory -> {
        if (params.action != "write" && params.action != "forget") {
            throw ProtocolParseException(emptyList())
        }
        val memory = MemoryStore(store, NuumPaths.memoryDir(agentId), clock)
        val tier = when (params.tier) {
            "profile" -> MemoryTier.PROFILE
            "note" -> MemoryTier.NOTE
            else -> MemoryTier.LOG
        }
        val message = if (params.action == "forget") {
            val removed = memory.forget(params.fact).removed
            if (removed == 0) "Nothing matched that, so nothing was removed."
            else "Forgotten ($removed ${if (removed == 1) "entry" else "entries"} removed)."
        } else {
            val written = memory.write(params.fact, tier).written
            if (!written) "Already recorded — nothing to do."
            else "Recorded to ${if (tier == MemoryTier.PROFILE) "your standing facts" else "your log"}."
        }
        if (!message.startsWith("Already") && !message.startsWith("Nothing matched")) bumpMemory(agentId)
        message
    }
}

private suspend fun HostRuntime.bumpMemory(agentId: String) {
    val cache = store.readDoc(NuumPaths.promptCachePath(agentId), PromptCache.serializer()) ?: PromptCache()
    store.writeDoc(NuumPaths.promptCachePath(agentId), PromptCache.serializer(), cache.copy(epoch = cache.epoch + 1, memory = null))
}

private suspend fun HostRuntime.createTeammate(agentId: String, params: ModelCreateAgent): String {
    val runId = scheduler.activeRunFor(agentId)
    if (!wakes.claimCreate(runId)) {
        return "Refused: you have already created an agent this turn. Use it, or ask the user before creating more."
    }
    if (agents.size >= MAX_AGENTS) return MAX_AGENTS_MESSAGE
    val view = createAgent(AgentCreateParams(name = params.name, description = params.description))
    val created = view.profile.id
    val firstMessage = params.firstMessage
    if (firstMessage.isNullOrBlank()) {
        return "Created \"${view.profile.name}\" (id $created). It has no instructions yet — use SendToAgent to give it work."
    }
    val delivered = sendToTeammate(agentId, com.nuum.protocol.SendToAgentParams(created, firstMessage, null))
    return "Created \"${view.profile.name}\" (id $created). $delivered"
}

private suspend fun HostRuntime.updateTeammate(agentId: String, params: com.nuum.protocol.UpdateAgentParams): String {
    if (params.agentId == agentId) return "That is you. Use update_state target=profile to change your own profile."
    return gate.withLock {
        val target = agents[params.agentId] ?: return@withLock "No agent with id ${params.agentId}."
        if (params.name == null && params.description == null && params.tags == null) {
            return@withLock "Nothing to change: pass name, tags or description."
        }
        target.profile = target.profile.copy(
            name = params.name?.trim() ?: target.profile.name,
            description = params.description?.trim() ?: target.profile.description,
            tags = params.tags?.let { normalizeAgentTags(it) } ?: target.profile.tags
        )
        store.writeDoc(NuumPaths.profilePath(params.agentId), com.nuum.protocol.AgentProfile.serializer(), target.profile)
        val event = appendTranscript(params.agentId) { seq ->
            TranscriptEvent.Profile(ids(), seq, clock.nowMillis(), ProfilePatch(params.name, params.description, params.tags))
        }
        emit(HostEvent.AgentMessageCompleted(params.agentId, event.toContract()))
        emit(HostEvent.AgentUpdated(viewOf(target)))
        "Updated \"${target.profile.name}\"."
    }
}

private suspend fun HostRuntime.sendToTeammate(agentId: String, params: com.nuum.protocol.SendToAgentParams): String {
    val from = agents[agentId]
    val target = agents[params.agentId] ?: return "No agent with id ${params.agentId}."
    val hops = currentHops(store.readTranscript(NuumPaths.transcriptPath(agentId))) + 1
    when (val verdict = wakes.check(agentId, params.agentId, hops)) {
        is WakeVerdict.Refused -> return verdict.reason
        WakeVerdict.Allowed -> Unit
    }
    val fromName = from?.profile?.name ?: "another agent"
    gate.withLock {
        val event = appendTranscript(params.agentId) { seq ->
            TranscriptEvent.Wake(
                id = ids(),
                seq = seq,
                createdAt = clock.nowMillis(),
                source = WakeSource.Agent(agentId, fromName, params.priority),
                text = params.message,
                hops = hops
            )
        }
        emit(HostEvent.AgentMessageCompleted(params.agentId, event.toContract()))
    }
    val wake = QueuedWake(agentId, fromName, params.message, hops)
    if (params.priority == true && scheduler.isBusy(params.agentId)) {
        cancelAgent(params.agentId)
        wakes.enqueue(params.agentId, wake)
        return "Sent to ${target.profile.name} as priority. It is dropping what it was doing to take this."
    }
    if (scheduler.isBusy(params.agentId)) {
        wakes.enqueue(params.agentId, wake)
        return "Sent to ${target.profile.name}. It is busy, so this is queued behind what it is doing."
    }
    val submitted = scheduler.submit(
        AgentScheduler.RunRequest(params.agentId, RunContext.Direct, target.settings.workspace?.projectRoot) { runId ->
            beginTurn(params.agentId, runId, RunContext.Direct)
        }
    )
    return try {
        submitted.started?.await()
        "Sent to ${target.profile.name}."
    } catch (error: NuumException) {
        "Delivered to ${target.profile.name}, but it could not start: ${error.message}. It will pick the message up next time it runs."
    }
}

private suspend fun HostRuntime.readTeammate(params: com.nuum.protocol.ReadAgentTranscriptParams): String {
    val target = agents[params.agentId] ?: return "No agent with id ${params.agentId}."
    val events = store.readTranscript(NuumPaths.transcriptPath(params.agentId))
    if (events.isEmpty()) return "\"${target.profile.name}\" has not said anything yet."
    val limit = params.limit ?: 40
    val lines = events.takeLast(limit).mapNotNull { event ->
        when (event) {
            is TranscriptEvent.User -> "user: ${event.text}"
            is TranscriptEvent.Message -> "message: ${event.payload}"
            is TranscriptEvent.Wake -> "wake: ${event.text}"
            else -> null
        }
    }
    if (lines.isEmpty()) return "\"${target.profile.name}\" has no user-visible updates yet."
    return (listOf("Last ${lines.size} updates from \"${target.profile.name}\":", "") + lines).joinToString("\n")
}

private fun HostRuntime.checkTeammate(self: String, agentId: String): String {
    if (self == agentId) return "That is you — you already know what you are doing."
    val target = agents[agentId] ?: return "No agent with id $agentId."
    val running = scheduler.isBusy(agentId)
    return "${target.profile.name} is ${if (running) "running" else "idle"}."
}

private suspend fun HostRuntime.stopTeammate(agentId: String): String {
    if (agents[agentId] == null) return "No agent with id $agentId."
    cancelAgent(agentId)
    return "Stopped."
}

private suspend fun HostRuntime.createCard(
    agentId: String,
    params: com.nuum.protocol.CreateTaskParams,
    context: RunContext
): String {
    val work = context as? RunContext.Work ?: return "CreateTask is only available during a Work run."
    val profile = works[work.workId]?.profile ?: return "Work not found."
    if (profile.kind == WorkKind.ROOM) return "Enable the task board before creating cards."
    val now = clock.nowMillis()
    val task = WorkTask(
        id = ids(),
        title = params.title.trim(),
        description = params.description,
        acceptanceCriteria = params.acceptanceCriteria,
        state = WorkTaskState.READY,
        ownerAgentId = agentId,
        assigneeIds = params.assigneeIds,
        dependencyIds = emptyList(),
        priority = WorkTaskPriority.NORMAL,
        revision = 1,
        deliverables = emptyList(),
        createdAt = now,
        updatedAt = now
    )
    gate.withLock {
        appendWork(work.workId) { seq ->
            WorkEvent.TaskCreated(ids(), work.workId, seq, now, WorkActor.Agent(agentId), task)
        }
    }
    return "Created card \"${task.title}\" (id ${task.id}, revision ${task.revision})."
}

private suspend fun HostRuntime.claimCard(
    agentId: String,
    params: com.nuum.protocol.ClaimTaskParams,
    context: RunContext
): String {
    val work = context as? RunContext.Work ?: return "ClaimTask is only available during a Work run."
    val task = tasksOf(work.workId).find { it.id == params.taskId } ?: return "No card ${params.taskId}."
    if (task.revision != params.expectedRevision) return "Card revision conflict."
    if (task.state == WorkTaskState.BLOCKED) return "Blocked cards require human confirmation."
    if (task.state != WorkTaskState.READY && task.state != WorkTaskState.PROPOSED) return "That card cannot be claimed from ${task.state}."
    val now = clock.nowMillis()
    val next = task.copy(
        state = WorkTaskState.IN_PROGRESS,
        assigneeIds = (task.assigneeIds + agentId).distinct(),
        revision = task.revision + 1,
        updatedAt = now
    )
    gate.withLock {
        appendWork(work.workId) { seq ->
            WorkEvent.TaskTransitioned(
                id = ids(),
                workId = work.workId,
                seq = seq,
                createdAt = now,
                actor = WorkActor.Agent(agentId),
                taskId = task.id,
                from = task.state,
                to = WorkTaskState.IN_PROGRESS,
                revision = next.revision
            )
        }
    }
    return "Claimed ${task.id} at revision ${next.revision}."
}

private suspend fun HostRuntime.readCard(taskId: String?, context: RunContext): String {
    val work = context as? RunContext.Work ?: return "ReadTask is only available during a Work run."
    val tasks = tasksOf(work.workId)
    val chosen = if (taskId == null) tasks else tasks.filter { it.id == taskId }
    if (chosen.isEmpty()) return "No matching card."
    return chosen.joinToString("\n") { "${it.id} ${it.state} rev ${it.revision}: ${it.title}" }
}

private suspend fun HostRuntime.postProgress(agentId: String, message: String, context: RunContext): String {
    val work = context as? RunContext.Work ?: return "PostToWork is only available during a Work run."
    gate.withLock {
        appendWork(work.workId) { seq ->
            WorkEvent.ChatPosted(
                id = ids(),
                workId = work.workId,
                seq = seq,
                createdAt = clock.nowMillis(),
                actor = WorkActor.Agent(agentId),
                messageId = ids(),
                body = message,
                mentionedAgentIds = emptyList(),
                taskId = work.taskId
            )
        }
    }
    return "Posted."
}

private suspend fun HostRuntime.handoff(
    agentId: String,
    params: com.nuum.protocol.HandoffTaskParams,
    context: RunContext
): String {
    val work = context as? RunContext.Work ?: return "HandoffTask is only available during a Work run."
    val to = when (params.status) {
        "blocked" -> WorkTaskState.BLOCKED
        "done" -> WorkTaskState.DONE
        else -> WorkTaskState.REVIEW
    }
    val role = roleOf(membershipOf(work.workId, agentId).binding?.role ?: com.nuum.protocol.WorkRole.WORKER)
    return try {
        transitionCard(work.workId, work.taskId, to, params.blockerReason, role)
        postProgress(agentId, params.summary, context)
        "Handed off as ${params.status}."
    } catch (error: IllegalArgumentException) {
        error.message ?: "Transition refused."
    }
}

private suspend fun HostRuntime.readTimeline(limit: Int, context: RunContext): String {
    val work = context as? RunContext.Work ?: return "ReadWorkTimeline is only available during a Work run."
    val events = store.readWorkEvents(NuumPaths.workTimelinePath(work.workId)).takeLast(limit)
    if (events.isEmpty()) return "The timeline is empty."
    return events.joinToString("\n") { "#${it.seq} ${it::class.simpleName}" }
}

private suspend fun HostRuntime.delegateCard(
    agentId: String,
    params: com.nuum.protocol.DelegateWorkParams,
    context: RunContext,
    toolCallId: String
): String {
    val work = context as? RunContext.Work ?: return "DelegateWork is only available during a Work run."
    if (agents[params.agentId] == null) return "No agent with id ${params.agentId}."
    gate.withLock {
        appendWork(work.workId) { seq ->
            WorkEvent.WorkRequested(
                id = ids(),
                workId = work.workId,
                seq = seq,
                createdAt = clock.nowMillis(),
                actor = WorkActor.Agent(agentId),
                agentId = params.agentId,
                taskId = params.taskId ?: work.taskId,
                instruction = params.instruction,
                membershipRevision = membershipOf(work.workId, params.agentId).revision,
                clientEventId = toolCallId
            )
        }
    }
    val child = RunContext.Work(
        work.workId,
        bridgeId = ids(),
        taskId = params.taskId ?: work.taskId,
        instruction = params.instruction,
        membershipRevision = membershipOf(work.workId, params.agentId).revision
    )
    scheduler.submit(
        AgentScheduler.RunRequest(params.agentId, child, works[work.workId]?.profile?.projectRoot) { runId ->
            beginTurn(params.agentId, runId, child)
        }
    )
    return "Worker dispatched. The card owner is unchanged; the worker result will return to the owner’s card session. Stop and wait if you have no independent work."
}

internal suspend fun HostRuntime.transitionCard(
    workId: String,
    taskId: String?,
    to: WorkTaskState,
    blockerReason: String?,
    role: TaskActorRole
): WorkTask {
    val task = tasksOf(workId).find { it.id == taskId } ?: throw IllegalArgumentException("No card.")
    if (to == WorkTaskState.BLOCKED && blockerReason.isNullOrBlank()) {
        throw IllegalArgumentException("A blocked card needs a reason.")
    }
    assertTaskTransition(task.state, to, role)
    val now = clock.nowMillis()
    val next = task.copy(
        state = to,
        revision = task.revision + 1,
        updatedAt = now,
        blocker = if (to == WorkTaskState.BLOCKED) {
            com.nuum.protocol.WorkTaskBlocker(blockerReason!!, null, null, now)
        } else {
            null
        }
    )
    gate.withLock {
        appendWork(workId) { seq ->
            WorkEvent.TaskTransitioned(
                id = ids(),
                workId = workId,
                seq = seq,
                createdAt = now,
                actor = WorkActor.User("local-user"),
                taskId = task.id,
                from = task.state,
                to = to,
                revision = next.revision,
                blocker = if (blockerReason.isNullOrBlank()) null else com.nuum.protocol.WorkTransitionBlocker(blockerReason)
            )
        }
    }
    return next
}

internal suspend fun HostRuntime.tasksOf(workId: String): List<WorkTask> = foldTasks(store.readWorkEvents(NuumPaths.workTimelinePath(workId)))

internal fun foldTasks(events: List<WorkEvent>): List<WorkTask> {
    val tasks = linkedMapOf<String, WorkTask>()
    for (event in events) {
        when (event) {
            is WorkEvent.TaskCreated -> tasks[event.task.id] = event.task
            is WorkEvent.TaskTransitioned -> {
                val current = tasks[event.taskId] ?: continue
                tasks[event.taskId] = current.copy(
                    state = event.to,
                    revision = event.revision,
                    updatedAt = event.createdAt,
                    blocker = event.blocker?.let {
                        com.nuum.protocol.WorkTaskBlocker(it.reason, it.ownerId, it.resumeCondition, event.createdAt)
                    }
                )
            }
            else -> Unit
        }
    }
    return tasks.values.toList()
}

internal data class DelegatedOutcome(val ok: Boolean, val output: String, val endTurn: Boolean)
