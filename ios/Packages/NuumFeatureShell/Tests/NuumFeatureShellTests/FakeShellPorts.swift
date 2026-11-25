import Foundation
import NuumContracts
@testable import NuumFeatureShell

final class FakeShellState: @unchecked Sendable {
    var agents: [AgentView]
    var works: [WorkListItem]
    var settings: PublicSettings
    var created: [AgentCreateParams] = []
    var updates: [AgentUpdateParams] = []
    var sidebarSets = 0
    var sends = 0
    var attaches: [WorkMemberAttachParams] = []
    var moves: [WorkMemberMoveParams] = []
    var transcripts: [String: [TranscriptEvent]] = [:]
    var pickedDirectory: String?
    var openedPaths: [String] = []
    var openError: NuumError?

    init(agents: [AgentView], works: [WorkListItem], settings: PublicSettings) {
        self.agents = agents
        self.works = works
        self.settings = settings
    }
}

final class EventStream: @unchecked Sendable {
    let stream: AsyncStream<HostEvent>
    let continuation: AsyncStream<HostEvent>.Continuation

    init() {
        var captured: AsyncStream<HostEvent>.Continuation?
        stream = AsyncStream { captured = $0 }
        continuation = captured!
    }
}

@MainActor
final class FakeShellPorts {
    let state: FakeShellState
    let agentEvents = EventStream()
    let settingsEvents = EventStream()
    let workEvents = EventStream()
    let ports: ShellPorts

    init(
        agents: [AgentView] = [],
        works: [WorkListItem] = [],
        sidebar: SidebarOrganization? = nil,
        language: Language = .en
    ) {
        state = FakeShellState(
            agents: agents,
            works: works,
            settings: PublicSettings(
                defaultToolPermission: .ask,
                defaultModel: ModelRef(provider: .deepseek, model: defaultModelID(for: .deepseek)),
                theme: .dark,
                hasOpenaiKey: false,
                hasAnthropicKey: false,
                hasDeepseekKey: false,
                language: language,
                sidebar: sidebar
            )
        )
        let state = state
        let agentEvents = agentEvents
        let settingsEvents = settingsEvents
        let workEvents = workEvents
        ports = ShellPorts(
            agents: FakeAgentPort(state: state, events: agentEvents),
            settings: FakeSettingsPort(state: state, events: settingsEvents),
            desktop: FakeDesktopPort(state: state),
            work: FakeWorkPort(state: state, events: workEvents)
        )
    }
}

final class FakeAgentPort: AgentPort, @unchecked Sendable {
    let state: FakeShellState
    let eventStream: EventStream
    var events: AsyncStream<HostEvent> { eventStream.stream }

    init(state: FakeShellState, events: EventStream) {
        self.state = state
        eventStream = events
    }

    func list() async throws -> [AgentView] {
        return state.agents
    }

    func get(id: String) async throws -> AgentSnapshot {
        guard let view = state.agents.first(where: { $0.profile.id == id }) else {
            throw NuumError(code: HostErrorCode.agentNotFound, message: "Missing agent")
        }
        return AgentSnapshot(view: view, events: [], blocks: [], live: nil)
    }

    func create(_ params: AgentCreateParams) async throws -> AgentView {
        state.created.append(params)
        let view = shellAgent(id: "created-\(state.created.count)", name: params.name ?? "Nunu", description: params.description ?? "")
        var profile = view.profile
        profile.avatarColor = params.avatarColor
        profile.avatarShape = params.avatarShape
        profile.avatarMaterial = params.avatarMaterial
        let created = AgentView(profile: profile, settings: view.settings, runtime: view.runtime)
        state.agents.append(created)
        return created
    }

    func update(_ params: AgentUpdateParams) async throws -> AgentView {
        state.updates.append(params)
        guard let index = state.agents.firstIndex(where: { $0.profile.id == params.id }) else {
            throw NuumError(code: HostErrorCode.agentNotFound, message: "Missing agent")
        }
        let current = state.agents[index]
        var profile = current.profile
        if let name = params.name { profile.name = name }
        if let description = params.description { profile.description = description }
        if let tags = params.tags { profile.tags = tags }
        var settings = current.settings
        if let execution = params.execution { settings.execution = execution }
        if let workspace = params.workspace { settings.workspace = workspace }
        let view = AgentView(profile: profile, settings: settings, runtime: current.runtime, roomMemberships: current.roomMemberships)
        state.agents[index] = view
        return view
    }

    func delete(id: String) async throws {
        throw NuumError(code: HostErrorCode.agentNotFound, message: "shell fixture")
    }

    func transcript(_ query: TranscriptQuery) async throws -> TranscriptPage {
        return TranscriptPage(id: query.id, entries: state.transcripts[query.id] ?? [])
    }

    func send(_ params: AgentSendParams) async throws -> SendResult {
        state.sends += 1
        throw NuumError(code: HostErrorCode.agentNotFound, message: "shell fixture")
    }

    func answerWidget(_ params: AgentAnswerWidgetParams) async throws -> SendResult {
        throw NuumError(code: HostErrorCode.agentNotFound, message: "shell fixture")
    }

    func cancel(id: String) async throws {
        throw NuumError(code: HostErrorCode.agentNotFound, message: "shell fixture")
    }

    func approve(id: String, toolCallId: String, resolution: ToolResolution) async throws {}

    func deny(id: String, toolCallId: String, resolution: ToolResolution) async throws {}
}

final class FakeSettingsPort: SettingsPort, @unchecked Sendable {
    let state: FakeShellState
    let eventStream: EventStream
    var events: AsyncStream<HostEvent> { eventStream.stream }

    init(state: FakeShellState, events: EventStream) {
        self.state = state
        eventStream = events
    }

    func get() async throws -> PublicSettings {
        return state.settings
    }

    func set(_ patch: SettingsPatch) async throws -> PublicSettings {
        if patch.sidebar != nil { state.sidebarSets += 1 }
        var settings = state.settings
        if let sidebar = patch.sidebar { settings.sidebar = sidebar }
        if let theme = patch.theme { settings.theme = theme }
        if let language = patch.language { settings.language = language }
        state.settings = settings
        return settings
    }
}

final class FakeDesktopPort: DesktopPort, @unchecked Sendable {
    let state: FakeShellState

    init(state: FakeShellState) { self.state = state }

    func pickDirectory() async throws -> String? {
        return state.pickedDirectory
    }

    func pickFiles() async throws -> [PickedFile] { [] }

    func openAttachment(path: String) async throws {
        state.openedPaths.append(path)
        if let openError = state.openError { throw openError }
    }

    func share(path: String) async throws {}
}

final class FakeWorkPort: WorkPort, @unchecked Sendable {
    let state: FakeShellState
    let eventStream: EventStream
    var events: AsyncStream<HostEvent> { eventStream.stream }

    init(state: FakeShellState, events: EventStream) {
        self.state = state
        eventStream = events
    }

    func create(_ params: WorkCreateParams) async throws -> WorkProfile { throw fixture }
    func list() async throws -> [WorkListItem] {
        return state.works
    }
    func get(id: String) async throws -> WorkSnapshot { throw fixture }
    func update(_ params: WorkUpdateParams) async throws -> WorkProfile { throw fixture }
    func postMessage(_ params: WorkPostMessageParams) async throws -> WorkEvent { throw fixture }
    func attachMember(_ params: WorkMemberAttachParams) async throws {
        state.attaches.append(params)
    }
    func detachMember(_ params: WorkMemberDetachParams) async throws { throw fixture }
    func moveMember(_ params: WorkMemberMoveParams) async throws {
        state.moves.append(params)
    }
    func continueDiscussion(_ params: WorkContinueParams) async throws { throw fixture }
    func stopDiscussion(workId: String) async throws { throw fixture }
    func taskTranscript(_ params: WorkTaskTranscriptParams) async throws -> TranscriptPage { throw fixture }
    func transitionTask(_ params: WorkTaskTransitionParams) async throws -> WorkTaskView { throw fixture }
    func dispatch(_ params: WorkDispatchParams) async throws { throw fixture }
    func addCatalog(_ params: WorkCatalogAddParams) async throws -> WorkCatalog { throw fixture }
    func removeCatalog(_ params: WorkCatalogRemoveParams) async throws -> WorkCatalog { throw fixture }
}

private let fixture = NuumError(code: HostErrorCode.workNotFound, message: "shell fixture")

func shellAgent(
    id: String,
    name: String,
    description: String = "",
    hidden: Bool = false,
    status: AgentStatus = .idle,
    activity: Int64 = 1_700_000_000_000
) -> AgentView {
    AgentView(
        profile: AgentProfile(id: id, name: name, description: description, createdAt: activity),
        settings: AgentSettings(
            model: ModelRef(provider: .deepseek, model: "deepseek-chat"),
            hiddenFromSidebar: hidden
        ),
        runtime: AgentRuntime(status: status, unread: false, lastActivityAt: activity)
    )
}

@MainActor
func makeSession(
    fake: FakeShellPorts,
    clipboard: any AgentIDClipboard = AcceptingClipboard(),
    roller: AnyAppearanceRoller = AnyAppearanceRoller(SystemRandomNumberGenerator()),
    suite: String = "nuum-ui-test-\(UUID().uuidString)"
) -> ShellSession {
    ShellSession(
        ports: fake.ports,
        preferences: ShellPreferenceStore(suiteName: suite),
        clipboard: clipboard,
        roller: roller
    )
}

final class RecordingClipboard: AgentIDClipboard, @unchecked Sendable {
    var copied: String?
    var ok = true
    func copy(_ text: String) -> Bool {
        copied = text
        return ok
    }
}
