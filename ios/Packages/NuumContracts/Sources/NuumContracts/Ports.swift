/// Direct model stream. Chunks are `text`, `thinking`, and `toolCall` only.
/// Thrown errors are `NuumError`. The message must not contain key material.
public protocol ModelPort: Sendable {
    func streamChat(_ request: NormalizedChatRequest) -> AsyncThrowingStream<NormalizedChunk, Error>
}

/// Kernel-facing tool boundary. The kernel keeps the approval loop and does not touch the filesystem.
public protocol ToolExecutor: Sendable {
    func bind(
        runId: String,
        roots: ToolRoots,
        permission: ToolPermission,
        approvals: [ToolApproval],
        refused: [ToolApproval]
    )
    func authorize(runId: String, action: LocalToolAction, target: String) async throws -> PermissionVerdict
    func grantOnce(runId: String, action: LocalToolAction, target: String)
    func refuse(runId: String, action: LocalToolAction, target: String)
    func setPermission(runId: String, permission: ToolPermission)
    func execute(runId: String, call: ToolCall) async throws -> ToolExecutionResult
    func release(runId: String)
}

extension ToolExecutor {
    public func bind(runId: String, roots: ToolRoots, permission: ToolPermission) {
        bind(runId: runId, roots: roots, permission: permission, approvals: [], refused: [])
    }
}

/// Host-facing file tools.
/// `shell`, `request_network`, and `external_operation` stay registered.
/// Executing them returns `UnimplementedToolMessage.iosClient`.
public protocol ToolBackend: ToolExecutor {
    func definitions() -> [ToolDefinition]
}

public protocol KernelPort: Sendable {
    var events: AsyncStream<KernelEvent> { get }
    func start(_ params: TurnStartParams) async throws
    func cancel(runId: String) async throws
    func approveTool(_ decision: TurnToolDecision) async throws
    func denyTool(_ decision: TurnToolDecision) async throws
    func provideContext(_ result: TurnContextResult) async throws
    func provideToolResult(_ result: TurnToolResult) async throws
    func summarize(_ params: SummarizeRunParams) async throws -> SummarizeRunResult
    func cancelSummary(runId: String) async throws
}

/// Keychain-backed secrets. One generic-password item (`KeychainSecretItem`), this device only.
/// Read and write failures throw `NuumError.secretReadFailed` or `NuumError.secretWriteFailed`.
/// A missing item is an empty `Secrets`, not an error. Do not write a secrets file.
public protocol SecretStore: Sendable {
    func read() async throws -> Secrets
    func write(_ secrets: Secrets) async throws
}

/// Settings screen only. An empty string or nil deletes that provider's key.
/// The method does not return the stored key.
public protocol SecretWriter: Sendable {
    func write(provider: ProviderId, apiKey: String?) async throws
}

public protocol Clock: Sendable {
    func nowMillis() -> Int64
}

/// Local client has a nil `userId`. Transcript records do not gain a user field.
public protocol IdentityContext: Sendable {
    var userId: String? { get }
}

/// Empty in this client. A later sync unit is an agent directory and a work timeline.
public protocol SyncPort: Sendable {
    func pushAgent(agentId: String) async throws
    func pullAgent(agentId: String) async throws
    func pushWork(workId: String) async throws
    func pullWork(workId: String) async throws
}

/// In-process turn lifetime. A later implementation must not push background policy into Host.
public protocol TurnSupervisor: Sendable {
    @discardableResult
    func launch(_ block: @escaping @Sendable () async -> Void) -> Task<Void, Never>
}

/// Unregistered in this client. `collect` returns context refs, never bodies or credentials.
public protocol ProactiveSource: Sendable {
    var id: String { get }
    func collect(agentId: String) async throws -> [String]
}

public protocol SettingsPort: Sendable {
    var events: AsyncStream<HostEvent> { get }
    func get() async throws -> PublicSettings
    func set(_ patch: SettingsPatch) async throws -> PublicSettings
}

public protocol AgentPort: Sendable {
    var events: AsyncStream<HostEvent> { get }
    func list() async throws -> [AgentView]
    func get(id: String) async throws -> AgentSnapshot
    func create(_ params: AgentCreateParams) async throws -> AgentView
    func update(_ params: AgentUpdateParams) async throws -> AgentView
    func delete(id: String) async throws
    func transcript(_ query: TranscriptQuery) async throws -> TranscriptPage
    func send(_ params: AgentSendParams) async throws -> SendResult
    func answerWidget(_ params: AgentAnswerWidgetParams) async throws -> SendResult
    func cancel(id: String) async throws
    func approve(id: String, toolCallId: String, resolution: ToolResolution) async throws
    func deny(id: String, toolCallId: String, resolution: ToolResolution) async throws
}

extension AgentPort {
    public func create() async throws -> AgentView {
        try await create(AgentCreateParams())
    }

    public func deny(id: String, toolCallId: String) async throws {
        try await deny(id: id, toolCallId: toolCallId, resolution: .deny)
    }
}

public protocol WorkPort: Sendable {
    var events: AsyncStream<HostEvent> { get }
    func create(_ params: WorkCreateParams) async throws -> WorkProfile
    func list() async throws -> [WorkListItem]
    func get(id: String) async throws -> WorkSnapshot
    func update(_ params: WorkUpdateParams) async throws -> WorkProfile
    func postMessage(_ params: WorkPostMessageParams) async throws -> WorkEvent
    func attachMember(_ params: WorkMemberAttachParams) async throws
    func detachMember(_ params: WorkMemberDetachParams) async throws
    func moveMember(_ params: WorkMemberMoveParams) async throws
    func continueDiscussion(_ params: WorkContinueParams) async throws
    func stopDiscussion(workId: String) async throws
    func taskTranscript(_ params: WorkTaskTranscriptParams) async throws -> TranscriptPage
    func transitionTask(_ params: WorkTaskTransitionParams) async throws -> WorkTaskView
    func dispatch(_ params: WorkDispatchParams) async throws
    func addCatalog(_ params: WorkCatalogAddParams) async throws -> WorkCatalog
    func removeCatalog(_ params: WorkCatalogRemoveParams) async throws -> WorkCatalog
}

public protocol ProactivePort: Sendable {
    var events: AsyncStream<HostEvent> { get }
    func get() async throws -> ProactiveSnapshot
    func configure(_ params: ProactiveConfigureParams) async throws -> ProactiveSnapshot
    func check(agentId: String) async throws -> ProactiveSnapshot
}

/// iOS file and share sheet. The implementation lives in the app, not in Host.
public protocol DesktopPort: Sendable {
    func pickDirectory() async throws -> String?
    func pickFiles() async throws -> [PickedFile]
    func openAttachment(path: String) async throws
    func share(path: String) async throws
}
