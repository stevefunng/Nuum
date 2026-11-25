import Foundation
import NuumContracts
import NuumProtocol

/// Host for the iOS client. Scheduling, wakes, prompts, memory, compaction,
/// transcript projection, delegated tools, room limits, and proactive snapshots
/// live here. Model calls go through `KernelPort`. Secrets are read from
/// `SecretStore` at the start of a turn and are not written to a file.
///
/// Status is derived from the in-memory scheduler. A new instance is idle even
/// when the transcript holds an unfinished wake.
public actor HostRuntime {
    public nonisolated let store: any AgentStore
    public nonisolated let kernel: any KernelPort
    public nonisolated let secretStore: any SecretStore
    public nonisolated let tools: any ToolBackend
    public nonisolated let clock: any Clock
    public nonisolated let supervisor: any TurnSupervisor
    public nonisolated let nuumRoot: String
    public nonisolated let osLabel: String
    public nonisolated let timeZone: String
    public nonisolated let contextWindowTokens: Int
    public nonisolated let deniedRoots: [String]
    public nonisolated let ids: @Sendable () -> String
    nonisolated let eventBus: HostEventBus

    let scheduler: AgentScheduler
    let wakes: WakeQueue
    var agents: [String: AgentRecord] = [:]
    var works: [String: WorkRecord] = [:]
    var memberships: [String: [String: NuumProtocol.WorkMembership]] = [:]
    var discussions: [String: LiveDiscussion] = [:]
    var discussionQueues: [String: [String]] = [:]
    var discussionJobs: [String: Task<Void, Never>] = [:]
    var errored = Set<String>()
    var liveParts: [String: LiveBuffer] = [:]
    var pendingApprovals: [String: NuumProtocol.ToolApproval] = [:]
    var pendingImages: [String: [NuumProtocol.ModelImage]] = [:]
    var settings: NuumProtocol.Settings
    var loaded = false
    var loadTask: Task<Void, Error>?
    var collector: Task<Void, Never>?

    public nonisolated var settingsPort: any SettingsPort { SettingsFacade(host: self) }
    public nonisolated var agentPort: any AgentPort { AgentFacade(host: self) }
    public nonisolated var workPort: any WorkPort { WorkFacade(host: self) }
    public nonisolated var proactivePort: any ProactivePort { ProactiveFacade(host: self) }

    public init(
        store: any AgentStore,
        kernel: any KernelPort,
        secretStore: any SecretStore,
        tools: any ToolBackend,
        clock: any Clock,
        supervisor: any TurnSupervisor,
        nuumRoot: String,
        osLabel: String,
        timeZone: String = "UTC",
        contextWindowTokens: Int = defaultContextWindow,
        deniedRoots: [String] = [],
        ids: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.store = store
        self.kernel = kernel
        self.secretStore = secretStore
        self.tools = tools
        self.clock = clock
        self.supervisor = supervisor
        self.nuumRoot = nuumRoot
        self.osLabel = osLabel
        self.timeZone = timeZone
        self.contextWindowTokens = contextWindowTokens
        self.deniedRoots = deniedRoots
        self.ids = ids
        self.eventBus = HostEventBus()
        self.scheduler = AgentScheduler(supervisor: supervisor, newRunId: ids)
        self.wakes = WakeQueue(now: { clock.nowMillis() })
        self.settings = NuumProtocol.defaultSettings
    }

    public func start() async throws {
        try await ensureLoaded()
        if collector == nil {
            let stream = kernel.events
            collector = Task {
                for await event in stream {
                    await self.onKernel(event)
                }
            }
        }
    }

    public func close() {
        collector?.cancel()
        collector = nil
        scheduler.close()
        discussionJobs.values.forEach { $0.cancel() }
        discussionJobs.removeAll()
    }

    func emit(_ event: HostEvent) {
        eventBus.emit(event)
    }

    func ensureLoaded() async throws {
        if loaded { return }
        if loadTask == nil {
            loadTask = Task { try await self.loadBody() }
        }
        try await loadTask?.value
        loaded = true
    }

    private func loadBody() async throws {
        settings = try await readDoc(store, NuumPaths.settingsPath(), as: NuumProtocol.Settings.self) ?? NuumProtocol.defaultSettings
        if try await store.exists("agents") {
            for id in try await store.list("agents") {
                guard let profile = try await readDoc(store, NuumPaths.profilePath(id), as: NuumProtocol.AgentProfile.self) else { continue }
                let agentSettings = try await readDoc(store, NuumPaths.agentSettingsPath(id), as: NuumProtocol.AgentSettings.self)
                    ?? NuumProtocol.AgentSettings(model: settings.defaultModel)
                let events = try await readTranscript(store, NuumPaths.transcriptPath(id))
                let cursor = try await readDoc(store, NuumPaths.readCursorPath(id), as: ReadCursor.self)?.seq ?? 0
                agents[id] = AgentRecord(
                    profile: profile,
                    settings: agentSettings,
                    lastSeq: events.map(\.seq).max() ?? 0,
                    lastActivityAt: events.map(\.createdAt).max() ?? profile.createdAt,
                    readCursor: cursor
                )
                if let wake = pendingWake(events) {
                    wakes.enqueue(toId: id, wake: wake)
                }
                try await claimReceipts(id, events)
            }
        }
        if try await store.exists("works") {
            for id in try await store.list("works") {
                guard let profile = try await readDoc(store, NuumPaths.workProfilePath(id), as: NuumProtocol.WorkProfile.self) else { continue }
                let events = try await readWorkEvents(store, NuumPaths.workTimelinePath(id))
                for event in events { applyMembership(event) }
                works[id] = WorkRecord(
                    profile: profile,
                    lastSeq: events.map(\.header.seq).max() ?? 0,
                    lastActivityAt: max(profile.createdAt, events.map(\.header.createdAt).max() ?? 0)
                )
            }
        }
    }
}

final class AgentRecord: @unchecked Sendable {
    var profile: NuumProtocol.AgentProfile
    var settings: NuumProtocol.AgentSettings
    var lastSeq: Int
    var lastActivityAt: Int64
    var readCursor: Int

    init(profile: NuumProtocol.AgentProfile, settings: NuumProtocol.AgentSettings, lastSeq: Int, lastActivityAt: Int64, readCursor: Int) {
        self.profile = profile
        self.settings = settings
        self.lastSeq = lastSeq
        self.lastActivityAt = lastActivityAt
        self.readCursor = readCursor
    }
}

final class WorkRecord: @unchecked Sendable {
    var profile: NuumProtocol.WorkProfile
    var lastSeq: Int
    var lastActivityAt: Int64

    init(profile: NuumProtocol.WorkProfile, lastSeq: Int, lastActivityAt: Int64) {
        self.profile = profile
        self.lastSeq = lastSeq
        self.lastActivityAt = lastActivityAt
    }
}

final class LiveDiscussion: @unchecked Sendable {
    let id: String
    let triggers: [String]
    var stopped = false
    var superseded = false
    var total = 0
    var perExecution: [String: Int] = [:]
    var replies: [MentionedMessage] = []
    var runId: String?

    init(id: String, triggers: [String]) {
        self.id = id
        self.triggers = triggers
    }
}

struct LiveBuffer: Sendable {
    var messageId: String
    var parts: [NuumProtocol.AssistantPart]
}

struct BuiltPrompt: Sendable {
    var text: String
    var notices: [String]
}

struct DelegatedOutcome: Sendable, Equatable {
    var ok: Bool
    var output: String
    var endTurn: Bool
}

private struct SettingsFacade: SettingsPort {
    let host: HostRuntime
    var events: AsyncStream<HostEvent> { host.eventBus.stream() }
    func get() async throws -> NuumContracts.PublicSettings { try await host.readPublicSettings() }
    func set(_ patch: NuumContracts.SettingsPatch) async throws -> NuumContracts.PublicSettings { try await host.applySettings(patch) }
}

private struct AgentFacade: AgentPort {
    let host: HostRuntime
    var events: AsyncStream<HostEvent> { host.eventBus.stream() }
    func list() async throws -> [NuumContracts.AgentView] { try await host.listAgents() }
    func get(id: String) async throws -> AgentSnapshot { try await host.snapshot(id) }
    func create(_ params: AgentCreateParams) async throws -> NuumContracts.AgentView { try await host.createAgent(params) }
    func update(_ params: AgentUpdateParams) async throws -> NuumContracts.AgentView { try await host.updateAgent(params) }
    func delete(id: String) async throws { try await host.deleteAgent(id) }
    func transcript(_ query: TranscriptQuery) async throws -> TranscriptPage { try await host.readTranscriptPage(query) }
    func send(_ params: AgentSendParams) async throws -> SendResult { try await host.performSend(params) }
    func answerWidget(_ params: AgentAnswerWidgetParams) async throws -> SendResult {
        try await host.performSend(AgentSendParams(id: params.id, content: params.value), widgetAnswerTo: params.messageId)
    }
    func cancel(id: String) async throws { try await host.cancelAgent(id) }
    func approve(id: String, toolCallId: String, resolution: NuumContracts.ToolResolution) async throws {
        try await host.resolveTool(id, toolCallId, resolution, allow: true)
    }
    func deny(id: String, toolCallId: String, resolution: NuumContracts.ToolResolution) async throws {
        try await host.resolveTool(id, toolCallId, resolution, allow: false)
    }
}

private struct WorkFacade: WorkPort {
    let host: HostRuntime
    var events: AsyncStream<HostEvent> { host.eventBus.stream() }
    func create(_ params: WorkCreateParams) async throws -> NuumContracts.WorkProfile { try await host.createWork(params) }
    func list() async throws -> [NuumContracts.WorkListItem] { try await host.listWorkItems() }
    func get(id: String) async throws -> WorkSnapshot { try await host.workSnapshot(id) }
    func update(_ params: WorkUpdateParams) async throws -> NuumContracts.WorkProfile { try await host.updateWork(params) }
    func postMessage(_ params: WorkPostMessageParams) async throws -> NuumContracts.WorkEvent { try await host.postWorkMessage(params) }
    func attachMember(_ params: WorkMemberAttachParams) async throws { try await host.attach(params) }
    func detachMember(_ params: WorkMemberDetachParams) async throws { try await host.detach(params) }
    func moveMember(_ params: WorkMemberMoveParams) async throws { try await host.move(params) }
    func continueDiscussion(_ params: WorkContinueParams) async throws { try await host.continueRoom(params) }
    func stopDiscussion(workId: String) async throws { try await host.stopRoom(workId) }
    func taskTranscript(_ params: WorkTaskTranscriptParams) async throws -> TranscriptPage { try await host.readTaskTranscript(params) }
    func transitionTask(_ params: WorkTaskTransitionParams) async throws -> WorkTaskView { try await host.transition(params) }
    func dispatch(_ params: WorkDispatchParams) async throws { try await host.dispatchWork(params) }
    func addCatalog(_ params: WorkCatalogAddParams) async throws -> NuumContracts.WorkCatalog { try await host.addCatalogEntry(params) }
    func removeCatalog(_ params: WorkCatalogRemoveParams) async throws -> NuumContracts.WorkCatalog { try await host.removeCatalogEntry(params) }
}

private struct ProactiveFacade: ProactivePort {
    let host: HostRuntime
    var events: AsyncStream<HostEvent> { host.eventBus.stream() }
    func get() async throws -> NuumContracts.ProactiveSnapshot { try await host.proactiveSnapshot() }
    func configure(_ params: NuumContracts.ProactiveConfigureParams) async throws -> NuumContracts.ProactiveSnapshot {
        try await host.configureProactive(params)
    }
    func check(agentId: String) async throws -> NuumContracts.ProactiveSnapshot { try await host.checkProactive(agentId) }
}
