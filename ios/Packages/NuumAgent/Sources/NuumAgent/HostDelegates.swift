import Foundation
import NuumContracts
import NuumProtocol

extension HostRuntime {
    func executeDelegated(
        _ agentId: String,
        _ name: String,
        _ args: NuumProtocol.JSONValue,
        _ context: RunContext,
        _ toolCallId: String
    ) async throws -> DelegatedOutcome {
        if !delegatedNames(context).contains(name) {
            return DelegatedOutcome(ok: false, output: "\(name) is not available in this run.", endTurn: false)
        }
        do {
            let text: String
            switch name {
            case DelegatedToolNames.sendMessage:
                if case .work = context {
                    text = try await sendWorkMessage(agentId, parseWorkSendMessage(args), context, toolCallId)
                } else {
                    text = try await deliverSendMessage(agentId, parseSendMessage(args), toolCallId)
                }
            case DelegatedToolNames.updateState:
                text = try await updateOwnState(agentId, parseUpdateState(args))
            case DelegatedToolNames.createAgent:
                text = try await createTeammate(agentId, parseCreateAgent(args))
            case DelegatedToolNames.updateAgent:
                text = try await updateTeammate(agentId, parseUpdateAgent(args))
            case DelegatedToolNames.sendToAgent:
                text = try await sendToTeammate(agentId, parseSendToAgent(args))
            case DelegatedToolNames.readAgentTranscript:
                text = try await readTeammate(parseReadAgentTranscript(args))
            case DelegatedToolNames.checkAgent:
                text = try checkTeammate(agentId, parseCheckAgent(args).agentId)
            case DelegatedToolNames.stopAgent:
                text = try await stopTeammate(parseStopAgent(args).agentId)
            case DelegatedToolNames.createTask:
                text = try await createCard(agentId, parseCreateTask(args), context)
            case DelegatedToolNames.claimTask:
                text = try await claimCard(agentId, parseClaimTask(args), context)
            case DelegatedToolNames.readTask:
                text = try await readCard(parseReadTask(args).taskId, context)
            case DelegatedToolNames.postToWork:
                text = try await postProgress(agentId, parsePostToWork(args).message, context)
            case DelegatedToolNames.handoffTask:
                text = try await handoff(agentId, parseHandoffTask(args), context)
            case DelegatedToolNames.readWorkTimeline:
                text = try await readTimeline(parseReadWorkTimeline(args).limit, context)
            case DelegatedToolNames.runWorkCli:
                _ = try parseRunWorkCli(args)
                return DelegatedOutcome(ok: false, output: runWorkCLIUnimplemented, endTurn: false)
            case DelegatedToolNames.delegateWork:
                text = try await delegateCard(agentId, parseDelegateWork(args), context, toolCallId)
            default:
                return DelegatedOutcome(ok: false, output: "Unknown delegated tool: \(name)", endTurn: false)
            }
            let content = field(args, "content")?.stringValue ?? ""
            let endTurn: Bool
            if case .work = context, name == DelegatedToolNames.sendMessage {
                endTurn = isPass(content) || discussionBudget(context)
            } else {
                endTurn = false
            }
            return DelegatedOutcome(ok: true, output: text, endTurn: endTurn)
        } catch let error as ProtocolParseException {
            return DelegatedOutcome(ok: false, output: toolArgumentError(toolName: name, error: error), endTurn: false)
        }
    }

    func transitionCard(
        _ workId: String,
        _ taskId: String?,
        _ to: NuumProtocol.WorkTaskState,
        _ blockerReason: String?,
        _ role: TaskActorRole
    ) async throws -> NuumProtocol.WorkTask {
        guard let task = try await tasksOf(workId).first(where: { $0.id == taskId }) else {
            throw TaskTransitionError("No card.")
        }
        if to == .blocked && (blockerReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TaskTransitionError("A blocked card needs a reason.")
        }
        try assertTaskTransition(from: task.state, to: to, role: role)
        let now = clock.nowMillis()
        var next = task
        next.state = to
        next.revision += 1
        next.updatedAt = now
        next.blocker = to == .blocked ? NuumProtocol.WorkTaskBlocker(reason: blockerReason ?? "", createdAt: now) : nil
        _ = try await appendWorkEvent(workId) { seq in
            .taskTransitioned(NuumProtocol.WorkEvent.TaskTransitioned(
                header: workHeader(id: ids(), workId: workId, seq: seq, createdAt: now, actor: .user(id: "local-user")),
                taskId: task.id,
                from: task.state,
                to: to,
                revision: next.revision,
                blocker: (blockerReason ?? "").isEmpty ? nil : NuumProtocol.WorkTransitionBlocker(reason: blockerReason ?? "")
            ))
        }
        return next
    }

    func tasksOf(_ workId: String) async throws -> [NuumProtocol.WorkTask] {
        foldTasks(try await readWorkEvents(store, NuumPaths.workTimelinePath(workId)))
    }
}

extension HostRuntime {
    private func delegatedNames(_ context: RunContext) -> Set<String> {
        switch context {
        case .direct:
            [
                DelegatedToolNames.sendMessage, DelegatedToolNames.updateState, DelegatedToolNames.createAgent,
                DelegatedToolNames.updateAgent, DelegatedToolNames.sendToAgent, DelegatedToolNames.readAgentTranscript,
                DelegatedToolNames.checkAgent, DelegatedToolNames.stopAgent,
            ]
        case .work:
            [
                DelegatedToolNames.sendMessage, DelegatedToolNames.createTask, DelegatedToolNames.claimTask,
                DelegatedToolNames.readTask, DelegatedToolNames.readWorkTimeline, DelegatedToolNames.runWorkCli,
                DelegatedToolNames.delegateWork,
            ]
        }
    }

    private func discussionBudget(_ context: RunContext) -> Bool {
        guard case .work(let workId, let bridgeId, _, _, _, _, _) = context, let bridgeId, let live = discussions[workId] else {
            return false
        }
        return (live.perExecution[bridgeId] ?? 0) >= discussionLimits.perTurn || live.total >= discussionLimits.messages
    }

    private func deliverSendMessage(_ agentId: String, _ payload: NuumProtocol.OutboundMessage, _ toolCallId: String) async throws -> String {
        _ = try requireAgent(agentId)
        let event = try await appendTranscriptEvent(agentId) { seq in
            .message(
                id: ids(),
                seq: seq,
                createdAt: clock.nowMillis(),
                assistantId: liveParts[agentId]?.messageId,
                toolCallId: toolCallId,
                payload: payload
            )
        }
        emit(.agentMessageCompleted(AgentMessageCompletedEvent(agentId: agentId, event: cTranscript(event))))
        switch payload {
        case .text:
            return "Delivered. (id: \(event.id))"
        case .attachment(let path, _):
            return "Delivered \(path). (id: \(event.id))"
        case .legacyWidget(let widget, _):
            return "Delivered the \(widget) widget."
        case .widget:
            return "Question delivered. (id: \(event.id)) Stop after this; the user's selection arrives as their next message."
        }
    }

    private func sendWorkMessage(
        _ agentId: String,
        _ params: WorkSendMessageParams,
        _ context: RunContext,
        _ toolCallId: String
    ) async throws -> String {
        guard case .work(let workId, let bridgeId, let taskId, _, _, _, _) = context else {
            return "SendMessage is only available with a run."
        }
        if isPass(params.content) { return "Passed." }
        if let live = discussions[workId], let bridgeId, (live.perExecution[bridgeId] ?? 0) >= discussionLimits.perTurn {
            return "Discussion message budget reached. Stop this turn."
        }
        if let live = discussions[workId], live.total >= discussionLimits.messages {
            return "Discussion message budget reached. Stop this turn."
        }
        let now = clock.nowMillis()
        _ = try await appendWorkEvent(workId) { seq in
            .chatPosted(NuumProtocol.WorkEvent.ChatPosted(
                header: workHeader(id: ids(), workId: workId, seq: seq, createdAt: now, actor: .agent(id: agentId), clientEventId: toolCallId),
                messageId: ids(),
                body: params.content,
                mentionedAgentIds: [],
                taskId: taskId
            ))
        }
        if let live = discussions[workId], let bridgeId {
            live.total += 1
            live.perExecution[bridgeId] = (live.perExecution[bridgeId] ?? 0) + 1
            live.replies.append(MentionedMessage(body: params.content, mentionedAgentIds: []))
        }
        if let action = params.cardAction {
            let to: NuumProtocol.WorkTaskState = action.status == "blocked" ? .blocked : .review
            _ = try await transitionCard(workId, taskId, to, action.blockerReason, .worker)
        }
        return "Delivered to the room."
    }

    private func updateOwnState(_ agentId: String, _ params: UpdateStateParams) async throws -> String {
        switch params {
        case .profile(_, let name, let description, let tags):
            if name == nil && description == nil && tags == nil {
                return "Nothing to change: pass name, tags or description."
            }
            let record = try requireAgent(agentId)
            if let name { record.profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let description { record.profile.description = description.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let tags { record.profile.tags = tags }
            try await writeDoc(store, NuumPaths.profilePath(agentId), record.profile)
            let event = try await appendTranscriptEvent(agentId) { seq in
                .profile(
                    id: ids(),
                    seq: seq,
                    createdAt: clock.nowMillis(),
                    patch: ProfilePatch(name: name?.trimmingCharacters(in: .whitespacesAndNewlines), description: description?.trimmingCharacters(in: .whitespacesAndNewlines), tags: tags)
                )
            }
            emit(.agentMessageCompleted(AgentMessageCompletedEvent(agentId: agentId, event: cTranscript(event))))
            emit(.agentUpdated(viewOf(record)))
            return "Profile updated. You are now \"\(record.profile.name)\"."
        case .memory(let action, let fact, let tierName):
            if action != "write" && action != "forget" {
                throw ProtocolParseException([])
            }
            let memory = MemoryStore(store: store, memoryDir: NuumPaths.memoryDir(agentId), clock: clock)
            let tier: MemoryTier = switch tierName {
            case "profile": .profile
            case "note": .note
            default: .log
            }
            let message: String
            if action == "forget" {
                let removed = try await memory.forget(fact: fact).removed
                message = removed == 0 ? "Nothing matched that, so nothing was removed." : "Forgotten (\(removed) \(removed == 1 ? "entry" : "entries") removed)."
            } else {
                let written = try await memory.write(fact: fact, tier: tier).written
                message = written
                    ? "Recorded to \(tier == .profile ? "your standing facts" : "your log")."
                    : "Already recorded — nothing to do."
            }
            if !message.hasPrefix("Already") && !message.hasPrefix("Nothing matched") {
                try await bumpMemory(agentId)
            }
            return message
        }
    }

    private func bumpMemory(_ agentId: String) async throws {
        let cache = try await readDoc(store, NuumPaths.promptCachePath(agentId), as: PromptCache.self) ?? PromptCache()
        var next = cache
        next.epoch += 1
        next.memory = nil
        try await writeDoc(store, NuumPaths.promptCachePath(agentId), next)
    }

    private func createTeammate(_ agentId: String, _ params: NuumProtocol.CreateAgentParams) async throws -> String {
        let runId = scheduler.activeRunFor(agentId)
        if !wakes.claimCreate(runId) {
            return "Refused: you have already created an agent this turn. Use it, or ask the user before creating more."
        }
        if agents.count >= maxAgents { return maxAgentsMessage }
        let view = try await createAgent(AgentCreateParams(name: params.name, description: params.description))
        let created = view.profile.id
        guard let firstMessage = params.firstMessage, !firstMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Created \"\(view.profile.name)\" (id \(created)). It has no instructions yet — use SendToAgent to give it work."
        }
        let delivered = try await sendToTeammate(agentId, NuumProtocol.SendToAgentParams(agentId: created, message: firstMessage, priority: nil))
        return "Created \"\(view.profile.name)\" (id \(created)). \(delivered)"
    }

    private func updateTeammate(_ agentId: String, _ params: UpdateAgentParams) async throws -> String {
        if params.agentId == agentId { return "That is you. Use update_state target=profile to change your own profile." }
        guard let target = agents[params.agentId] else { return "No agent with id \(params.agentId)." }
        if params.name == nil && params.description == nil && params.tags == nil {
            return "Nothing to change: pass name, tags or description."
        }
        if let name = params.name { target.profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let description = params.description { target.profile.description = description.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let tags = params.tags { target.profile.tags = try normalizeAgentTags(tags) }
        try await writeDoc(store, NuumPaths.profilePath(params.agentId), target.profile)
        let event = try await appendTranscriptEvent(params.agentId) { seq in
            .profile(id: ids(), seq: seq, createdAt: clock.nowMillis(), patch: ProfilePatch(name: params.name, description: params.description, tags: params.tags))
        }
        emit(.agentMessageCompleted(AgentMessageCompletedEvent(agentId: params.agentId, event: cTranscript(event))))
        emit(.agentUpdated(viewOf(target)))
        return "Updated \"\(target.profile.name)\"."
    }

    private func sendToTeammate(_ agentId: String, _ params: NuumProtocol.SendToAgentParams) async throws -> String {
        let from = agents[agentId]
        guard let target = agents[params.agentId] else { return "No agent with id \(params.agentId)." }
        let hops = currentHops(try await readTranscript(store, NuumPaths.transcriptPath(agentId))) + 1
        if case .refused(let reason) = wakes.check(fromId: agentId, toId: params.agentId, hops: hops) {
            return reason
        }
        let fromName = from?.profile.name ?? "another agent"
        let event = try await appendTranscriptEvent(params.agentId) { seq in
            .wake(
                id: ids(),
                seq: seq,
                createdAt: clock.nowMillis(),
                source: .agent(fromId: agentId, fromName: fromName, priority: params.priority),
                text: params.message,
                hops: hops
            )
        }
        emit(.agentMessageCompleted(AgentMessageCompletedEvent(agentId: params.agentId, event: cTranscript(event))))
        let wake = QueuedWake(fromId: agentId, fromName: fromName, text: params.message, hops: hops)
        if params.priority == true && scheduler.isBusy(params.agentId) {
            try await cancelAgent(params.agentId)
            wakes.enqueue(toId: params.agentId, wake: wake)
            return "Sent to \(target.profile.name) as priority. It is dropping what it was doing to take this."
        }
        if scheduler.isBusy(params.agentId) {
            wakes.enqueue(toId: params.agentId, wake: wake)
            return "Sent to \(target.profile.name). It is busy, so this is queued behind what it is doing."
        }
        let submitted = scheduler.submit(AgentScheduler.RunRequest(
            agentId: params.agentId,
            context: .direct,
            projectRoot: target.settings.workspace?.projectRoot
        ) { runId in
            try await self.beginTurn(params.agentId, runId, .direct)
        })
        do {
            if let started = submitted.started { try await started.wait() }
            return "Sent to \(target.profile.name)."
        } catch let error as NuumError {
            return "Delivered to \(target.profile.name), but it could not start: \(error.message). It will pick the message up next time it runs."
        }
    }

    private func readTeammate(_ params: ReadAgentTranscriptParams) async throws -> String {
        guard let target = agents[params.agentId] else { return "No agent with id \(params.agentId)." }
        let events = try await readTranscript(store, NuumPaths.transcriptPath(params.agentId))
        if events.isEmpty { return "\"\(target.profile.name)\" has not said anything yet." }
        let limit = params.limit ?? 40
        let lines = events.suffix(limit).compactMap { event -> String? in
            switch event {
            case .user(_, _, _, let text, _, _): "user: \(text)"
            case .message(_, _, _, _, _, let payload): "message: \(describeOutbound(payload))"
            case .wake(_, _, _, _, let text, _): "wake: \(text)"
            default: nil
            }
        }
        if lines.isEmpty { return "\"\(target.profile.name)\" has no user-visible updates yet." }
        return (["Last \(lines.count) updates from \"\(target.profile.name)\":", ""] + lines).joined(separator: "\n")
    }

    private func checkTeammate(_ selfId: String, _ agentId: String) -> String {
        if selfId == agentId { return "That is you — you already know what you are doing." }
        guard let target = agents[agentId] else { return "No agent with id \(agentId)." }
        return "\(target.profile.name) is \(scheduler.isBusy(agentId) ? "running" : "idle")."
    }

    private func stopTeammate(_ agentId: String) async throws -> String {
        if agents[agentId] == nil { return "No agent with id \(agentId)." }
        try await cancelAgent(agentId)
        return "Stopped."
    }

    private func createCard(_ agentId: String, _ params: CreateTaskParams, _ context: RunContext) async throws -> String {
        guard case .work(let workId, _, _, _, _, _, _) = context else { return "CreateTask is only available during a Work run." }
        guard let profile = works[workId]?.profile else { return "Work not found." }
        if profile.kind == .room { return "Enable the task board before creating cards." }
        let now = clock.nowMillis()
        let task = NuumProtocol.WorkTask(
            id: ids(),
            title: params.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: params.description,
            acceptanceCriteria: params.acceptanceCriteria,
            state: .ready,
            assigneeIds: params.assigneeIds,
            dependencyIds: [],
            priority: .normal,
            revision: 1,
            deliverables: [],
            createdAt: now,
            updatedAt: now,
            ownerAgentId: agentId
        )
        _ = try await appendWorkEvent(workId) { seq in
            .taskCreated(NuumProtocol.WorkEvent.TaskCreated(
                header: workHeader(id: ids(), workId: workId, seq: seq, createdAt: now, actor: .agent(id: agentId)),
                task: task
            ))
        }
        return "Created card \"\(task.title)\" (id \(task.id), revision \(task.revision))."
    }

    private func claimCard(_ agentId: String, _ params: ClaimTaskParams, _ context: RunContext) async throws -> String {
        guard case .work(let workId, _, _, _, _, _, _) = context else { return "ClaimTask is only available during a Work run." }
        guard let task = try await tasksOf(workId).first(where: { $0.id == params.taskId }) else { return "No card \(params.taskId)." }
        if task.revision != params.expectedRevision { return "Card revision conflict." }
        if task.state == .blocked { return "Blocked cards require human confirmation." }
        if task.state != .ready && task.state != .proposed { return "That card cannot be claimed from \(task.state.rawValue)." }
        let now = clock.nowMillis()
        let revision = task.revision + 1
        _ = try await appendWorkEvent(workId) { seq in
            .taskTransitioned(NuumProtocol.WorkEvent.TaskTransitioned(
                header: workHeader(id: ids(), workId: workId, seq: seq, createdAt: now, actor: .agent(id: agentId)),
                taskId: task.id,
                from: task.state,
                to: .inProgress,
                revision: revision
            ))
        }
        return "Claimed \(task.id) at revision \(revision)."
    }

    private func readCard(_ taskId: String?, _ context: RunContext) async throws -> String {
        guard case .work(let workId, _, _, _, _, _, _) = context else { return "ReadTask is only available during a Work run." }
        let tasks = try await tasksOf(workId)
        let chosen = taskId.map { id in tasks.filter { $0.id == id } } ?? tasks
        if chosen.isEmpty { return "No matching card." }
        return chosen.map { "\($0.id) \($0.state.rawValue) rev \($0.revision): \($0.title)" }.joined(separator: "\n")
    }

    private func postProgress(_ agentId: String, _ message: String, _ context: RunContext) async throws -> String {
        guard case .work(let workId, _, let taskId, _, _, _, _) = context else { return "PostToWork is only available during a Work run." }
        let now = clock.nowMillis()
        _ = try await appendWorkEvent(workId) { seq in
            .chatPosted(NuumProtocol.WorkEvent.ChatPosted(
                header: workHeader(id: ids(), workId: workId, seq: seq, createdAt: now, actor: .agent(id: agentId)),
                messageId: ids(),
                body: message,
                mentionedAgentIds: [],
                taskId: taskId
            ))
        }
        return "Posted."
    }

    private func handoff(_ agentId: String, _ params: HandoffTaskParams, _ context: RunContext) async throws -> String {
        guard case .work(let workId, _, let taskId, _, _, _, _) = context else { return "HandoffTask is only available during a Work run." }
        let to: NuumProtocol.WorkTaskState = switch params.status {
        case "blocked": .blocked
        case "done": .done
        default: .review
        }
        let role = roleOf(membershipOf(workId, agentId).binding?.role ?? .worker)
        do {
            _ = try await transitionCard(workId, taskId, to, params.blockerReason, role)
            _ = try await postProgress(agentId, params.summary, context)
            return "Handed off as \(params.status)."
        } catch let error as TaskTransitionError {
            return error.description
        }
    }

    private func readTimeline(_ limit: Int, _ context: RunContext) async throws -> String {
        guard case .work(let workId, _, _, _, _, _, _) = context else { return "ReadWorkTimeline is only available during a Work run." }
        let events = try await readWorkEvents(store, NuumPaths.workTimelinePath(workId)).suffix(limit)
        if events.isEmpty { return "The timeline is empty." }
        return events.map { "#\($0.header.seq) \(workEventName($0))" }.joined(separator: "\n")
    }

    private func delegateCard(
        _ agentId: String,
        _ params: DelegateWorkParams,
        _ context: RunContext,
        _ toolCallId: String
    ) async throws -> String {
        guard case .work(let workId, _, let taskId, _, _, _, _) = context else { return "DelegateWork is only available during a Work run." }
        if agents[params.agentId] == nil { return "No agent with id \(params.agentId)." }
        let now = clock.nowMillis()
        let revision = membershipOf(workId, params.agentId).revision
        let childTask = params.taskId ?? taskId
        _ = try await appendWorkEvent(workId) { seq in
            .workRequested(NuumProtocol.WorkEvent.WorkRequested(
                header: workHeader(id: ids(), workId: workId, seq: seq, createdAt: now, actor: .agent(id: agentId), clientEventId: toolCallId),
                agentId: params.agentId,
                instruction: params.instruction,
                membershipRevision: revision,
                taskId: childTask
            ))
        }
        let child = RunContext.work(
            workId: workId,
            bridgeId: ids(),
            taskId: childTask,
            membershipRevision: revision,
            instruction: params.instruction
        )
        _ = scheduler.submit(AgentScheduler.RunRequest(
            agentId: params.agentId,
            context: child,
            projectRoot: works[workId]?.profile.projectRoot
        ) { runId in
            try await self.beginTurn(params.agentId, runId, child)
        })
        return "Worker dispatched. The card owner is unchanged; the worker result will return to the owner’s card session. Stop and wait if you have no independent work."
    }
}

func foldTasks(_ events: [NuumProtocol.WorkEvent]) -> [NuumProtocol.WorkTask] {
    var tasks: [String: NuumProtocol.WorkTask] = [:]
    var order: [String] = []
    for event in events {
        switch event {
        case .taskCreated(let created):
            if tasks[created.task.id] == nil { order.append(created.task.id) }
            tasks[created.task.id] = created.task
        case .taskTransitioned(let transition):
            guard var current = tasks[transition.taskId] else { continue }
            current.state = transition.to
            current.revision = transition.revision
            current.updatedAt = transition.header.createdAt
            current.blocker = transition.blocker.map {
                NuumProtocol.WorkTaskBlocker(reason: $0.reason, createdAt: transition.header.createdAt, ownerId: $0.ownerId, resumeCondition: $0.resumeCondition)
            }
            tasks[transition.taskId] = current
        default:
            break
        }
    }
    return order.compactMap { tasks[$0] }
}

func workHeader(
    id: String,
    workId: String,
    seq: Int,
    createdAt: Int64,
    actor: NuumProtocol.WorkActor,
    clientEventId: String? = nil
) -> NuumProtocol.WorkEventHeader {
    NuumProtocol.WorkEventHeader(id: id, workId: workId, seq: seq, createdAt: createdAt, actor: actor, clientEventId: clientEventId)
}

func workEventName(_ event: NuumProtocol.WorkEvent) -> String {
    switch event {
    case .chatPosted: "ChatPosted"
    case .taskCreated: "TaskCreated"
    case .taskClaimed: "TaskClaimed"
    case .taskAssigned: "TaskAssigned"
    case .taskDelegated: "TaskDelegated"
    case .taskTransitioned: "TaskTransitioned"
    case .taskProgressed: "TaskProgressed"
    case .taskHandedOff: "TaskHandedOff"
    case .historyImported: "HistoryImported"
    case .workRequested: "WorkRequested"
    case .executionStarted: "ExecutionStarted"
    case .executionFinished: "ExecutionFinished"
    case .discussionStarted: "DiscussionStarted"
    case .discussionFinished: "DiscussionFinished"
    case .dispatchRequested: "DispatchRequested"
    case .dispatchAcknowledged: "DispatchAcknowledged"
    case .dispatchFinished: "DispatchFinished"
    case .memberAttached: "MemberAttached"
    case .memberDetached: "MemberDetached"
    }
}

private func describeOutbound(_ payload: NuumProtocol.OutboundMessage) -> String {
    switch payload {
    case .text(let content, _): content
    case .attachment(let path, _): path
    case .widget(let widget): widget.prompt
    case .legacyWidget(let widget, _): widget
    }
}
