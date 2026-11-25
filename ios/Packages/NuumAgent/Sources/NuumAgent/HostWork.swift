import Foundation
import NuumContracts
import NuumProtocol

extension HostRuntime {
    func createWork(_ params: WorkCreateParams) async throws -> NuumContracts.WorkProfile {
        try await ensureLoaded()
        let name = params.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: "Work name is required")
        }
        let id = ids()
        let workspaceId = ids()
        let root: String?
        if nuumRoot.isEmpty {
            root = nil
        } else {
            let path = rooted(nuumRoot, NuumPaths.managedWorkspaceDir(workspaceId))
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            root = path
        }
        let profile = NuumProtocol.WorkProfile(
            id: id,
            name: name,
            description: "",
            projectRoot: root,
            createdAt: clock.nowMillis(),
            kind: params.kind.map(pWorkKind) ?? .work,
            workspaceId: workspaceId
        )
        try await writeDoc(store, NuumPaths.workProfilePath(id), profile)
        try await writeDoc(store, NuumPaths.workCatalogPath(id), emptyWorkCatalog)
        works[id] = WorkRecord(profile: profile, lastSeq: 0, lastActivityAt: profile.createdAt)
        let view = cWorkProfile(profile)
        emit(.workUpdated(view))
        return view
    }

    func listWorkItems() async throws -> [NuumContracts.WorkListItem] {
        try await ensureLoaded()
        var items: [NuumContracts.WorkListItem] = []
        for record in works.values {
            let preview = try await readWorkEvents(store, NuumPaths.workTimelinePath(record.profile.id)).compactMap { event -> String? in
                if case .chatPosted(let posted) = event { return posted.body }
                return nil
            }.last
            items.append(NuumContracts.WorkListItem(profile: cWorkProfile(record.profile), lastActivityAt: record.lastActivityAt, preview: preview))
        }
        return items
    }

    func workSnapshot(_ id: String) async throws -> WorkSnapshot {
        try await ensureLoaded()
        guard let record = works[id] else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Work not found")
        }
        let events = try await readWorkEvents(store, NuumPaths.workTimelinePath(id))
        let catalog = try await readDoc(store, NuumPaths.workCatalogPath(id), as: NuumProtocol.WorkCatalog.self) ?? emptyWorkCatalog
        let members = agents.values.filter { membershipOf(id, $0.profile.id).binding != nil }.map { viewOf($0) }
        let tasks = foldTasks(events)
        let mapped = events.compactMap(cWorkEvent)
        let chat = mapped.filter { if case .chatPosted = $0.body { return true }; return false }
        let live = discussions[id]
        return WorkSnapshot(
            discussionRunning: live != nil && live?.stopped != true,
            interruptions: interruptions(events),
            throughSeq: events.map(\.header.seq).max() ?? 0,
            profile: cWorkProfile(record.profile),
            members: members,
            catalog: cCatalog(catalog),
            events: mapped,
            tasks: tasks.map { task in
                WorkTaskView(task: cTask(task), allowedTransitions: allowedTaskTransitions(task.state, .user).map(cTaskState))
            },
            chat: chat
        )
    }

    func updateWork(_ params: WorkUpdateParams) async throws -> NuumContracts.WorkProfile {
        try await ensureLoaded()
        guard let record = works[params.id] else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Work not found")
        }
        if let kind = params.kind { record.profile.kind = pWorkKind(kind) }
        if let name = params.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            record.profile.name = name
        }
        try await writeDoc(store, NuumPaths.workProfilePath(params.id), record.profile)
        let view = cWorkProfile(record.profile)
        emit(.workUpdated(view))
        return view
    }

    func postWorkMessage(_ params: WorkPostMessageParams) async throws -> NuumContracts.WorkEvent {
        try await ensureLoaded()
        guard works[params.workId] != nil else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Work not found")
        }
        let body = params.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: "Message body is required")
        }
        let timeline = try await readWorkEvents(store, NuumPaths.workTimelinePath(params.workId))
        if let inputAfter = params.inputAfterSeq, inputAfter > (timeline.map(\.header.seq).max() ?? 0) {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: "Invalid room history start sequence")
        }
        if let clientEventId = params.clientEventId,
           let previous = timeline.first(where: { $0.header.clientEventId == clientEventId }),
           let mapped = cWorkEvent(previous) {
            enqueueDiscussion(params.workId, previous.header.id)
            return mapped
        }
        let event = try await appendWorkEvent(params.workId) { seq in
            .chatPosted(NuumProtocol.WorkEvent.ChatPosted(
                header: workHeader(
                    id: ids(),
                    workId: params.workId,
                    seq: seq,
                    createdAt: clock.nowMillis(),
                    actor: .user(id: "local-user"),
                    clientEventId: params.clientEventId
                ),
                messageId: ids(),
                body: body,
                mentionedAgentIds: params.mentionedAgentIds,
                inputAfterSeq: params.inputAfterSeq
            ))
        }
        enqueueDiscussion(params.workId, event.header.id)
        guard let mapped = cWorkEvent(event) else {
            throw NuumError(code: NuumContracts.KernelErrorCode.internal, message: "Work event could not be projected")
        }
        return mapped
    }

    func attach(_ params: WorkMemberAttachParams) async throws {
        try await ensureLoaded()
        guard works[params.workId] != nil else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Work not found")
        }
        _ = try requireAgent(params.agentId)
        let current = membershipOf(params.workId, params.agentId)
        if current.revision != params.expectedRevision {
            throw NuumError(code: NuumContracts.HostErrorCode.workConflict, message: "Membership revision conflict")
        }
        let now = clock.nowMillis()
        _ = try await appendWorkEvent(params.workId) { seq in
            .memberAttached(NuumProtocol.WorkEvent.MemberAttached(
                header: workHeader(id: ids(), workId: params.workId, seq: seq, createdAt: now, actor: .user(id: "local-user")),
                membershipOperationId: ids(),
                agentId: params.agentId,
                role: pWorkRole(params.role),
                membershipRevision: current.revision + 1
            ))
        }
    }

    func detach(_ params: WorkMemberDetachParams) async throws {
        try await ensureLoaded()
        guard works[params.workId] != nil else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Work not found")
        }
        let current = membershipOf(params.workId, params.agentId)
        if current.revision != params.expectedRevision {
            throw NuumError(code: NuumContracts.HostErrorCode.workConflict, message: "Membership revision conflict")
        }
        let now = clock.nowMillis()
        _ = try await appendWorkEvent(params.workId) { seq in
            .memberDetached(NuumProtocol.WorkEvent.MemberDetached(
                header: workHeader(id: ids(), workId: params.workId, seq: seq, createdAt: now, actor: .user(id: "local-user")),
                membershipOperationId: ids(),
                agentId: params.agentId,
                membershipRevision: current.revision + 1
            ))
        }
    }

    func move(_ params: WorkMemberMoveParams) async throws {
        _ = params
        throw NuumError(
            code: NuumContracts.HostErrorCode.workConflict,
            message: "Rooms now have independent membership. Attach to the new room, then explicitly remove from the old room."
        )
    }

    func continueRoom(_ params: WorkContinueParams) async throws {
        try await ensureLoaded()
        guard works[params.workId] != nil else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Work not found")
        }
        enqueueDiscussion(params.workId, params.eventId)
    }

    func stopRoom(_ workId: String) async throws {
        try await ensureLoaded()
        guard works[workId] != nil else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Work not found")
        }
        discussions[workId]?.stopped = true
        discussionQueues.removeValue(forKey: workId)
        for id in agents.keys {
            guard let run = scheduler.activeRunFor(id), let context = scheduler.contextFor(run) else { continue }
            if case .work(let activeWork, _, _, _, _, _, _) = context, activeWork == workId {
                _ = scheduler.cancelAgent(id)
                try await kernel.cancel(runId: run)
            }
        }
    }

    func readTaskTranscript(_ params: WorkTaskTranscriptParams) async throws -> TranscriptPage {
        try await ensureLoaded()
        guard works[params.workId] != nil else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Work not found")
        }
        guard let task = try await tasksOf(params.workId).first(where: { $0.id == params.taskId }) else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Card not found")
        }
        let events: [NuumProtocol.TranscriptEvent]
        if let owner = task.ownerAgentId {
            let session = cardSession(
                workId: params.workId,
                taskId: params.taskId,
                agentId: owner,
                membershipRevision: membershipOf(params.workId, owner).revision
            )
            events = try await readTranscript(store, "\(cardSessionDir(session))/transcript.jsonl")
        } else {
            events = []
        }
        let filtered = events.filter { params.beforeSeq == nil || $0.seq < (params.beforeSeq ?? 0) }
        return TranscriptPage(id: params.taskId, entries: filtered.map(cTranscript), nextBeforeSeq: nil)
    }

    func transition(_ params: WorkTaskTransitionParams) async throws -> WorkTaskView {
        try await ensureLoaded()
        guard works[params.workId] != nil else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Work not found")
        }
        guard let task = try await tasksOf(params.workId).first(where: { $0.id == params.taskId }) else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Card not found")
        }
        if task.revision != params.expectedRevision {
            throw NuumError(code: NuumContracts.HostErrorCode.workConflict, message: "Card revision conflict")
        }
        if params.to == .blocked && (params.blocker?.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: "A blocked card needs a reason.")
        }
        do {
            let next = try await transitionCard(params.workId, params.taskId, pTaskState(params.to), params.blocker?.reason, .user)
            return WorkTaskView(task: cTask(next), allowedTransitions: allowedTaskTransitions(next.state, .user).map(cTaskState))
        } catch let error as TaskTransitionError {
            throw NuumError(code: NuumContracts.HostErrorCode.workConflict, message: error.description)
        }
    }

    func dispatchWork(_ params: WorkDispatchParams) async throws {
        try await ensureLoaded()
        guard works[params.workId] != nil else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Work not found")
        }
        _ = try requireAgent(params.agentId)
        let membership = membershipOf(params.workId, params.agentId)
        if membership.binding?.grants.canPost != true {
            throw NuumError(code: NuumContracts.HostErrorCode.workForbidden, message: "Agent cannot execute in this room")
        }
        let context = RunContext.work(
            workId: params.workId,
            bridgeId: ids(),
            taskId: params.taskId,
            membershipRevision: membership.revision,
            instruction: params.instruction
        )
        let now = clock.nowMillis()
        _ = try await appendWorkEvent(params.workId) { seq in
            .workRequested(NuumProtocol.WorkEvent.WorkRequested(
                header: workHeader(id: ids(), workId: params.workId, seq: seq, createdAt: now, actor: .user(id: "local-user")),
                agentId: params.agentId,
                instruction: params.instruction,
                membershipRevision: membership.revision,
                taskId: params.taskId
            ))
        }
        _ = scheduler.submit(AgentScheduler.RunRequest(
            agentId: params.agentId,
            context: context,
            projectRoot: works[params.workId]?.profile.projectRoot
        ) { runId in
            try await self.beginTurn(params.agentId, runId, context)
        })
    }

    func addCatalogEntry(_ params: WorkCatalogAddParams) async throws -> NuumContracts.WorkCatalog {
        try await ensureLoaded()
        guard works[params.workId] != nil else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Work not found")
        }
        let current = try await readDoc(store, NuumPaths.workCatalogPath(params.workId), as: NuumProtocol.WorkCatalog.self) ?? emptyWorkCatalog
        if current.revision != params.expectedRevision {
            throw NuumError(code: NuumContracts.HostErrorCode.workConflict, message: "Catalog revision conflict")
        }
        let entry = try catalogEntry(params.entry)
        var next = current
        next.revision += 1
        next.entries.append(entry)
        try await writeDoc(store, NuumPaths.workCatalogPath(params.workId), next)
        let view = cCatalog(next)
        emit(.workCatalogUpdated(WorkCatalogUpdatedEvent(workId: params.workId, catalog: view)))
        return view
    }

    func removeCatalogEntry(_ params: WorkCatalogRemoveParams) async throws -> NuumContracts.WorkCatalog {
        try await ensureLoaded()
        guard works[params.workId] != nil else {
            throw NuumError(code: NuumContracts.HostErrorCode.workNotFound, message: "Work not found")
        }
        let current = try await readDoc(store, NuumPaths.workCatalogPath(params.workId), as: NuumProtocol.WorkCatalog.self) ?? emptyWorkCatalog
        if current.revision != params.expectedRevision {
            throw NuumError(code: NuumContracts.HostErrorCode.workConflict, message: "Catalog revision conflict")
        }
        var next = current
        next.revision += 1
        next.entries.removeAll { catalogEntryID($0) == params.entryId }
        try await writeDoc(store, NuumPaths.workCatalogPath(params.workId), next)
        let view = cCatalog(next)
        emit(.workCatalogUpdated(WorkCatalogUpdatedEvent(workId: params.workId, catalog: view)))
        return view
    }

    func appendWorkEvent(_ workId: String, _ build: (Int) -> NuumProtocol.WorkEvent) async throws -> NuumProtocol.WorkEvent {
        let path = NuumPaths.workTimelinePath(workId)
        let existing = try await readWorkEvents(store, path)
        let event = build((existing.map(\.header.seq).max() ?? 0) + 1)
        try await appendWorkLine(store, path, event)
        applyMembership(event)
        if let record = works[workId] {
            record.lastSeq = event.header.seq
            record.lastActivityAt = max(record.lastActivityAt, event.header.createdAt)
        }
        if let mapped = cWorkEvent(event) {
            emit(.workEventAppended(WorkEventAppendedEvent(workId: workId, event: mapped)))
        }
        return event
    }

    func enqueueDiscussion(_ workId: String, _ eventId: String) {
        var queue = discussionQueues[workId] ?? []
        if !queue.contains(eventId) { queue.append(eventId) }
        discussionQueues[workId] = queue
        discussions[workId]?.superseded = true
        if discussionJobs[workId] != nil { return }
        let job = supervisor.launch {
            await self.runDiscussionJob(workId)
        }
        discussionJobs[workId] = job
    }

    func runDiscussionJob(_ workId: String) async {
        await driveDiscussion(workId)
        discussionJobs[workId] = nil
        if let next = discussionQueues[workId]?.first {
            enqueueDiscussion(workId, next)
        }
    }
}

extension HostRuntime {
    private func driveDiscussion(_ workId: String) async {
        while discussionQueues[workId]?.isEmpty == false {
            let triggers = discussionQueues[workId] ?? []
            discussionQueues[workId] = []
            let id = ids()
            let live = LiveDiscussion(id: id, triggers: triggers)
            discussions[workId] = live
            let now = clock.nowMillis()
            _ = try? await appendWorkEvent(workId) { seq in
                .discussionStarted(NuumProtocol.WorkEvent.DiscussionStarted(
                    header: workHeader(id: id, workId: workId, seq: seq, createdAt: now, actor: .system(id: "host")),
                    triggerEventIds: triggers.isEmpty ? [id] : triggers
                ))
            }
            let flag = DiscussionFlag()
            do {
                let members = agents.values.compactMap { record -> DiscussionMember? in
                    guard let binding = membershipOf(workId, record.profile.id).binding, binding.grants.canPost else { return nil }
                    return DiscussionMember(id: record.profile.id, name: record.profile.name)
                }
                let store = self.store
                try await runDiscussion(
                    current: { !live.stopped && !live.superseded },
                    responders: {
                        let events = try await readWorkEvents(store, NuumPaths.workTimelinePath(workId))
                        let messages = events.compactMap { event -> MentionedMessage? in
                            guard case .chatPosted(let posted) = event else { return nil }
                            let mentioned = triggers.contains(posted.header.id) || live.replies.contains { $0.body == posted.body }
                            guard mentioned else { return nil }
                            return MentionedMessage(body: posted.body, mentionedAgentIds: posted.mentionedAgentIds)
                        }
                        return try discussionResponders(members, messages).map(\.id)
                    },
                    runMember: { agentId in
                        let before = live.total
                        let revision = await self.membershipOf(workId, agentId).revision
                        let project = await self.works[workId]?.profile.projectRoot
                        let context = RunContext.work(
                            workId: workId,
                            bridgeId: self.ids(),
                            discussionId: id,
                            membershipRevision: revision,
                            instruction: "Discuss the room. Use SendMessage for at most two short replies."
                        )
                        let scheduler = await self.scheduler
                        let submitted = scheduler.submit(AgentScheduler.RunRequest(
                            agentId: agentId,
                            context: context,
                            projectRoot: project
                        ) { runId in
                            live.runId = runId
                            try await self.beginTurn(agentId, runId, context)
                        })
                        let outcome: RunOutcome
                        do {
                            if let started = submitted.started { try await started.wait() }
                            outcome = try await submitted.completed.wait()
                        } catch {
                            outcome = .failed
                        }
                        if outcome == .failed { flag.failed = true }
                        return MemberTurn(messages: live.total - before, failed: outcome == .failed)
                    }
                )
            } catch {
                flag.failed = true
                flag.errorText = error.messageText
            }
            discussions.removeValue(forKey: workId)
            let status: DiscussionFinishStatus = if live.stopped {
                .cancelled
            } else if flag.failed && !live.superseded {
                .interrupted
            } else {
                .completed
            }
            _ = try? await appendWorkEvent(workId) { seq in
                .discussionFinished(NuumProtocol.WorkEvent.DiscussionFinished(
                    header: workHeader(id: ids(), workId: workId, seq: seq, createdAt: clock.nowMillis(), actor: .system(id: "host")),
                    discussionId: id,
                    status: status,
                    error: flag.errorText
                ))
            }
            await Task.yield()
        }
    }
}

private final class DiscussionFlag: @unchecked Sendable {
    var failed = false
    var errorText: String?
}

private func interruptions(_ events: [NuumProtocol.WorkEvent]) -> [WorkInterruption] {
    events.compactMap { event in
        guard case .discussionFinished(let finished) = event, finished.status == .interrupted else { return nil }
        return WorkInterruption(eventId: finished.header.id, error: finished.error ?? "Discussion interrupted", kind: "discussion")
    }
}

private func catalogEntry(_ input: NuumContracts.WorkCatalogInput) throws -> NuumProtocol.WorkCatalogEntry {
    let id = UUID().uuidString
    switch input {
    case .skill(let skill):
        return .skill(id: id, name: skill.name, description: skill.description, enabled: true, manifestPath: skill.manifestPath)
    case .cli(let cli):
        return .cli(
            id: id, name: cli.name, description: cli.description, enabled: true,
            executable: cli.executable, allowedSubcommands: cli.allowedSubcommands
        )
    case .knowledge(let knowledge):
        if !knowledge.readOnly {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: "knowledge catalog entries are readOnly")
        }
        return .knowledge(id: id, name: knowledge.name, description: knowledge.description, enabled: true, roots: knowledge.roots, readOnly: true)
    case .localTool(let tool):
        return .localTool(id: id, name: tool.name, description: tool.description, enabled: true, toolNames: tool.toolNames)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
