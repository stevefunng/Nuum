import Foundation
import NuumContracts
@testable import NuumFeatureWork

final class FakeWorkPort: WorkPort, @unchecked Sendable {
    let events: AsyncStream<HostEvent>
    private let continuation: AsyncStream<HostEvent>.Continuation
    private var snapshot: WorkSnapshot
    private(set) var updates: [WorkUpdateParams] = []
    private(set) var posts: [WorkPostMessageParams] = []
    private(set) var transitions: [WorkTaskTransitionParams] = []
    private(set) var catalogAdds: [WorkCatalogAddParams] = []
    private(set) var creates: [WorkCreateParams] = []
    private(set) var continues: [WorkContinueParams] = []
    private(set) var stops: [String] = []
    private(set) var dispatches: [WorkDispatchParams] = []
    private(set) var attaches: [WorkMemberAttachParams] = []
    var catalogError: NuumError?

    init(snapshot: WorkSnapshot) {
        let pair = AsyncStream<HostEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
        self.snapshot = snapshot
    }

    func yield(_ event: HostEvent) { continuation.yield(event) }

    func create(_ params: WorkCreateParams) async throws -> WorkProfile {
        creates.append(params)
        return WorkProfile(id: "created", name: params.name, description: "", projectRoot: nil, createdAt: 0, kind: params.kind)
    }

    func list() async throws -> [WorkListItem] { [] }

    func get(id: String) async throws -> WorkSnapshot {
        snapshot
    }

    func update(_ params: WorkUpdateParams) async throws -> WorkProfile {
        updates.append(params)
        snapshot.profile.kind = params.kind ?? snapshot.profile.kind
        if let name = params.name { snapshot.profile.name = name }
        return snapshot.profile
    }

    func postMessage(_ params: WorkPostMessageParams) async throws -> WorkEvent {
        posts.append(params)
        let event = WorkEvent(
            type: "chat.posted",
            id: "posted",
            workId: params.workId,
            seq: snapshot.chat.count + 1,
            createdAt: 0,
            actor: .user(UserActor(id: "local-user")),
            body: .chatPosted(ChatPostedBody(messageId: "m", body: params.body, mentionedAgentIds: params.mentionedAgentIds))
        )
        snapshot.chat.append(event)
        return event
    }

    func attachMember(_ params: WorkMemberAttachParams) async throws {
        attaches.append(params)
    }

    func detachMember(_ params: WorkMemberDetachParams) async throws {}

    func moveMember(_ params: WorkMemberMoveParams) async throws {}

    func continueDiscussion(_ params: WorkContinueParams) async throws {
        continues.append(params)
    }

    func stopDiscussion(workId: String) async throws {
        stops.append(workId)
    }

    func taskTranscript(_ params: WorkTaskTranscriptParams) async throws -> TranscriptPage {
        TranscriptPage(id: params.sessionId ?? params.taskId, entries: [], nextBeforeSeq: nil)
    }

    func transitionTask(_ params: WorkTaskTransitionParams) async throws -> WorkTaskView {
        transitions.append(params)
        let task = snapshot.tasks.first { $0.task.id == params.taskId }?.task
        var next = task ?? WorkTask(
            id: params.taskId, title: "", description: "", acceptanceCriteria: [], state: params.to,
            assigneeIds: [], dependencyIds: [], priority: .normal, revision: params.expectedRevision + 1,
            deliverables: [], createdAt: 0, updatedAt: 0
        )
        next.state = params.to
        next.revision = params.expectedRevision + 1
        next.blocker = params.blocker
        let view = WorkTaskView(task: next, allowedTransitions: [])
        if let index = snapshot.tasks.firstIndex(where: { $0.task.id == params.taskId }) {
            snapshot.tasks[index] = view
        }
        return view
    }

    func dispatch(_ params: WorkDispatchParams) async throws {
        dispatches.append(params)
    }

    func addCatalog(_ params: WorkCatalogAddParams) async throws -> WorkCatalog {
        if let catalogError { throw catalogError }
        catalogAdds.append(params)
        let entry = storedEntry(params.entry)
        let catalog = WorkCatalog(revision: params.expectedRevision + 1, entries: snapshot.catalog.entries + [entry])
        snapshot.catalog = catalog
        return catalog
    }

    func removeCatalog(_ params: WorkCatalogRemoveParams) async throws -> WorkCatalog {
        let catalog = WorkCatalog(revision: params.expectedRevision + 1, entries: snapshot.catalog.entries.filter { $0.id != params.entryId })
        snapshot.catalog = catalog
        return catalog
    }

    private func storedEntry(_ input: WorkCatalogInput) -> WorkCatalogEntry {
        switch input {
        case .skill(let skill):
            .skill(SkillCatalogEntry(id: "s", name: skill.name, description: skill.description, enabled: true, manifestPath: skill.manifestPath))
        case .cli(let cli):
            .cli(CliCatalogEntry(id: "c", name: cli.name, description: cli.description, enabled: true, executable: cli.executable, allowedSubcommands: cli.allowedSubcommands))
        case .knowledge(let knowledge):
            .knowledge(KnowledgeCatalogEntry(id: "k", name: knowledge.name, description: knowledge.description, enabled: true, roots: knowledge.roots, readOnly: knowledge.readOnly))
        case .localTool(let tool):
            .localTool(LocalToolCatalogEntry(id: "t", name: tool.name, description: tool.description, enabled: true, toolNames: tool.toolNames))
        }
    }
}

final class FakeAgentPort: AgentPort, @unchecked Sendable {
    let events: AsyncStream<HostEvent>
    private var agents: [String: AgentView]
    private(set) var approvals: [ToolResolution] = []
    private(set) var denies: [String] = []
    var denyError: NuumError?

    init(agents: [AgentView] = []) {
        events = AsyncStream { _ in }
        self.agents = Dictionary(uniqueKeysWithValues: agents.map { ($0.profile.id, $0) })
    }

    func list() async throws -> [AgentView] { Array(agents.values) }

    func get(id: String) async throws -> AgentSnapshot {
        guard let view = agents[id] else {
            throw NuumError(code: HostErrorCode.agentNotFound, message: "Agent not found")
        }
        return AgentSnapshot(view: view, events: [], blocks: [], live: nil)
    }

    func create(_ params: AgentCreateParams) async throws -> AgentView { throw unused }
    func update(_ params: AgentUpdateParams) async throws -> AgentView { throw unused }
    func delete(id: String) async throws { throw unused }
    func transcript(_ query: TranscriptQuery) async throws -> TranscriptPage { throw unused }
    func send(_ params: AgentSendParams) async throws -> SendResult { throw unused }
    func answerWidget(_ params: AgentAnswerWidgetParams) async throws -> SendResult { throw unused }
    func cancel(id: String) async throws { throw unused }

    func approve(id: String, toolCallId: String, resolution: ToolResolution) async throws {
        approvals.append(resolution)
    }

    func deny(id: String, toolCallId: String, resolution: ToolResolution) async throws {
        if let denyError { throw denyError }
        denies.append(toolCallId)
    }

    private var unused: NuumError { NuumError(code: HostErrorCode.agentNotFound, message: "not used") }
}

final class FakeDesktopPort: DesktopPort, @unchecked Sendable {
    var directory: String? = "/skills/review"
    private(set) var picks = 0

    func pickDirectory() async throws -> String? {
        picks += 1
        return directory
    }

    func pickFiles() async throws -> [PickedFile] { [] }
    func openAttachment(path: String) async throws {}
    func share(path: String) async throws {}
}

func makeSnapshot(
    kind: WorkKind?,
    name: String = "NunuBar · Launch",
    tasks: [WorkTaskView] = [],
    members: [AgentView] = [],
    chat: [WorkEvent] = [],
    interruptions: [WorkInterruption] = [],
    discussionRunning: Bool = false,
    events: [WorkEvent] = []
) -> WorkSnapshot {
    WorkSnapshot(
        discussionRunning: discussionRunning,
        interruptions: interruptions,
        throughSeq: 0,
        profile: WorkProfile(id: "work-1", name: name, description: "", projectRoot: nil, createdAt: 0, kind: kind),
        members: members,
        catalog: WorkCatalog(revision: 3, entries: []),
        events: events,
        tasks: tasks,
        chat: chat
    )
}

func makeAgent(
    id: String = "ada",
    name: String = "Ada",
    status: AgentStatus = .idle,
    activeRunId: String? = nil,
    canManage: Bool = false,
    workId: String = "work-1",
    revision: Int = 2,
    bound: Bool = true
) -> AgentView {
    let grants = WorkGrants(canPost: true, canManageOwnTasks: canManage, canAssignTasks: false, canEditCatalog: false)
    let binding = bound ? WorkBinding(workId: workId, role: .worker, joinedAt: 0, grants: grants) : nil
    let membership = WorkMembership(revision: revision, binding: binding)
    return AgentView(
        profile: AgentProfile(id: id, name: name, description: "", createdAt: 0),
        settings: AgentSettings(model: ModelRef(provider: .deepseek, model: "deepseek-chat"), workMembership: membership),
        runtime: AgentRuntime(status: status, unread: false, lastActivityAt: 0, activeRunId: activeRunId),
        roomMemberships: [workId: membership]
    )
}

func makeTask(
    state: WorkTaskState,
    blocker: WorkBlocker? = nil,
    revision: Int = 4,
    title: String = "Write spec"
) -> WorkTask {
    WorkTask(
        id: "task-1",
        title: title,
        description: "Details",
        acceptanceCriteria: ["Ships"],
        state: state,
        assigneeIds: [],
        dependencyIds: [],
        priority: .normal,
        revision: revision,
        deliverables: [],
        createdAt: 0,
        updatedAt: 1,
        ownerAgentId: nil,
        blocker: blocker
    )
}

func chatEvent(_ seq: Int) -> WorkEvent {
    WorkEvent(
        type: "chat.posted",
        id: "e\(seq)",
        workId: "work-1",
        seq: seq,
        createdAt: 0,
        actor: .user(UserActor(id: "local-user")),
        body: .chatPosted(ChatPostedBody(messageId: "m\(seq)", body: "hi", mentionedAgentIds: []))
    )
}
