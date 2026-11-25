import Foundation
import NuumContracts

/// Ports this screen is allowed to call. Concrete host types stay outside this package.
public struct WorkPorts: Sendable {
    public var work: any WorkPort
    public var agent: any AgentPort
    public var desktop: any DesktopPort

    public init(work: any WorkPort, agent: any AgentPort, desktop: any DesktopPort) {
        self.work = work
        self.agent = agent
        self.desktop = desktop
    }
}

actor WorkStore {
    let workId: String
    let ports: WorkPorts
    private(set) var state = WorkUiState()

    init(workId: String, ports: WorkPorts) {
        self.workId = workId
        self.ports = ports
    }

    func setAcceptsModelRequests(_ value: Bool) {
        state.acceptsModelRequests = value
    }

    func reload() async {
        do {
            let snapshot = try await ports.work.get(id: workId)
            state.loading = false
            state.snapshot = snapshot
        } catch is CancellationError {
            return
        } catch {
            state.loading = false
            state.notice = workNotice(from: error)
        }
    }

    func upgrade() async {
        await run {
            _ = try await ports.work.update(WorkUpdateParams(id: workId, kind: .work))
            await reload()
        }
    }

    func post(body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state.acceptsModelRequests else { return }
        await run {
            _ = try await ports.work.postMessage(WorkPostMessageParams(
                workId: workId,
                body: trimmed,
                mentionedAgentIds: [],
                clientEventId: UUID().uuidString
            ))
            await reload()
        }
    }

    func continueDiscussion(eventId: String, inputAfterSeq: Int? = nil) async {
        guard state.acceptsModelRequests else { return }
        await run {
            try await ports.work.continueDiscussion(WorkContinueParams(
                workId: workId,
                eventId: eventId,
                inputAfterSeq: inputAfterSeq
            ))
            await reload()
        }
    }

    func stopDiscussion() async {
        await run {
            try await ports.work.stopDiscussion(workId: workId)
            await reload()
        }
    }

    func detach(agentId: String, revision: Int) async {
        await run {
            try await ports.work.detachMember(WorkMemberDetachParams(
                workId: workId,
                agentId: agentId,
                expectedRevision: revision
            ))
            await reload()
        }
    }

    func attach(agentId: String) async {
        await run {
            let view = try await ports.agent.get(id: agentId).view
            let membership = view.roomMemberships[workId]
            if membership?.binding != nil { return }
            try await ports.work.attachMember(WorkMemberAttachParams(
                workId: workId,
                agentId: agentId,
                expectedRevision: membership?.revision ?? 0,
                role: .worker
            ))
            await reload()
        }
    }

    func transition(task: WorkTask, to: WorkTaskState) async throws {
        let view = try await ports.work.transitionTask(WorkTaskTransitionParams(
            workId: workId,
            taskId: task.id,
            to: to,
            expectedRevision: task.revision,
            blocker: blockerForTransition(task: task, to: to)
        ))
        if var snapshot = state.snapshot {
            snapshot.tasks = snapshot.tasks.map { $0.task.id == view.task.id ? view : $0 }
            state.snapshot = snapshot
        }
    }

    func dispatch(agentId: String, taskId: String, instruction: String) async throws {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state.acceptsModelRequests else { return }
        try await ports.work.dispatch(WorkDispatchParams(
            workId: workId,
            agentId: agentId,
            instruction: trimmed,
            taskId: taskId
        ))
        await reload()
    }

    func loadTrace(taskId: String, sessionId: String?, beforeSeq: Int?) async throws -> TranscriptPage {
        try await ports.work.taskTranscript(WorkTaskTranscriptParams(
            workId: workId,
            taskId: taskId,
            sessionId: sessionId,
            beforeSeq: beforeSeq
        ))
    }

    func addCatalog(_ entry: WorkCatalogInput) async throws {
        let revision = state.snapshot?.catalog.revision ?? 0
        let catalog = try await ports.work.addCatalog(WorkCatalogAddParams(
            workId: workId,
            expectedRevision: revision,
            entry: entry
        ))
        if var snapshot = state.snapshot {
            snapshot.catalog = catalog
            state.snapshot = snapshot
        }
    }

    func removeCatalog(entryId: String) async {
        await run {
            let revision = state.snapshot?.catalog.revision ?? 0
            let catalog = try await ports.work.removeCatalog(WorkCatalogRemoveParams(
                workId: workId,
                entryId: entryId,
                expectedRevision: revision
            ))
            if var snapshot = state.snapshot {
                snapshot.catalog = catalog
                state.snapshot = snapshot
            }
        }
    }

    func decide(approval: PendingApproval, resolution: ToolResolution) async {
        guard approvalResolutions.contains(resolution) else { return }
        do {
            if resolution == .deny {
                try await ports.agent.deny(id: approval.agentId, toolCallId: approval.toolCallId, resolution: .deny)
            } else {
                try await ports.agent.approve(id: approval.agentId, toolCallId: approval.toolCallId, resolution: resolution)
            }
            state.approvals.removeAll { $0.agentId == approval.agentId && $0.toolCallId == approval.toolCallId }
        } catch is CancellationError {
            return
        } catch {
            let notice = workNotice(from: error)
            if let index = state.approvals.firstIndex(where: { $0.id == approval.id }) {
                state.approvals[index].failureMessage = notice.message
            }
        }
    }

    func pickDirectory() async -> DirectoryPick {
        do {
            guard let path = try await ports.desktop.pickDirectory() else { return .cancelled }
            return .path(path)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(workNotice(from: error))
        }
    }

    func create(name: String, kind: WorkKind) async throws -> WorkProfile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try await ports.work.create(WorkCreateParams(name: trimmed, kind: kind))
    }

    func apply(_ event: HostEvent) async {
        switch event {
        case .workUpdated(let profile):
            guard profile.id == workId else { return }
            await reload()
        case .workEventAppended(let appended):
            guard appended.workId == workId else { return }
            await reload()
        case .workCatalogUpdated(let updated):
            guard updated.workId == workId else { return }
            await reload()
        case .agentToolPending(let pending):
            onPending(pending)
        case .agentToolStarted(let started):
            clearApproval(agentId: started.agentId, toolCallId: started.toolCallId)
        case .agentToolCompleted(let completed):
            clearApproval(agentId: completed.agentId, toolCallId: completed.toolCallId)
        case .agentEnded(let ended):
            clearAgent(ended.agentId)
        case .agentError(let failed):
            clearAgent(failed.agentId)
        case .agentUpdated(let agent):
            updateMember(agent)
        default:
            break
        }
    }

    private func run(_ body: () async throws -> Void) async {
        state.notice = nil
        do {
            try await body()
        } catch is CancellationError {
            return
        } catch {
            state.notice = workNotice(from: error)
        }
    }

    private func onPending(_ event: AgentToolPendingEvent) {
        let members = state.snapshot?.members ?? []
        guard members.contains(where: { $0.profile.id == event.agentId }) else { return }
        let approval = PendingApproval(
            agentId: event.agentId,
            toolCallId: event.toolCallId,
            action: event.action,
            target: event.target,
            justification: event.justification,
            allowAlways: event.allowAlways != false,
            details: event.details,
            failureMessage: nil
        )
        state.approvals.removeAll { $0.id == approval.id }
        state.approvals.append(approval)
    }

    private func clearApproval(agentId: String, toolCallId: String) {
        state.approvals.removeAll { $0.agentId == agentId && $0.toolCallId == toolCallId }
    }

    private func clearAgent(_ agentId: String) {
        state.approvals.removeAll { $0.agentId == agentId }
    }

    private func updateMember(_ agent: AgentView) {
        guard var snapshot = state.snapshot else { return }
        guard snapshot.members.contains(where: { $0.profile.id == agent.profile.id }) else { return }
        snapshot.members = snapshot.members.map { $0.profile.id == agent.profile.id ? agent : $0 }
        state.snapshot = snapshot
    }
}
