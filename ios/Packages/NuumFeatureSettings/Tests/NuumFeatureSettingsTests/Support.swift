import Foundation
import NuumContracts
@testable import NuumFeatureSettings

final class HoldGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private let enteredContinuation: AsyncStream<Void>.Continuation
    let entered: AsyncStream<Void>

    init() {
        let pair = AsyncStream<Void>.makeStream()
        entered = pair.stream
        enteredContinuation = pair.continuation
    }

    func enter() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            continuation = cont
            lock.unlock()
            enteredContinuation.yield(())
        }
    }

    func release() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume()
    }
}

final class MemorySecretStore: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Secrets()
    private var reads = 0

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }

    /// A read the settings UI is not allowed to make. `peek` does not count.
    func read() -> Secrets {
        lock.lock()
        defer { lock.unlock() }
        reads += 1
        return current
    }

    func write(_ secrets: Secrets) {
        lock.lock()
        current = secrets
        lock.unlock()
    }

    func peek() -> Secrets {
        lock.lock()
        defer { lock.unlock() }
        return current
    }
}

/// Records writes. Empty string deletes. Does not read the store back.
final class RecordingSecretWriter: SecretWriter, @unchecked Sendable {
    let store: MemorySecretStore
    private let lock = NSLock()
    private var recorded: [(ProviderId, String?)] = []
    var failure: Error?

    var writes: [(ProviderId, String?)] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    init(store: MemorySecretStore) {
        self.store = store
    }

    func write(provider: ProviderId, apiKey: String?) async throws {
        if let failure = remember(provider, apiKey) { throw failure }
        let kept = apiKey.flatMap { $0.isEmpty ? nil : $0 }
        var next = store.peek()
        switch provider {
        case .openai:
            next.openaiApiKey = kept
        case .anthropic:
            next.anthropicApiKey = kept
        case .deepseek:
            next.deepseekApiKey = kept
        }
        store.write(next)
    }

    private func remember(_ provider: ProviderId, _ apiKey: String?) -> Error? {
        lock.lock()
        defer { lock.unlock() }
        recorded.append((provider, apiKey))
        return failure
    }
}

final class FakeSettingsPort: SettingsPort, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: PublicSettings
    private var recorded: [SettingsPatch] = []
    var failLanguage = false
    var themeFailure: String?
    var modelFailure: String?
    var holdLanguage = false
    let languageHold = HoldGate()
    var getGate: HoldGate?
    let events: AsyncStream<HostEvent>
    private let eventsContinuation: AsyncStream<HostEvent>.Continuation

    init(initial: PublicSettings = sampleSettings()) {
        storage = initial
        let pair = AsyncStream<HostEvent>.makeStream()
        events = pair.stream
        eventsContinuation = pair.continuation
    }

    var current: PublicSettings {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var patches: [SettingsPatch] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func get() async throws -> PublicSettings {
        if let getGate {
            await getGate.enter()
        }
        return current
    }

    func set(_ patch: SettingsPatch) async throws -> PublicSettings {
        let decision = beginSet(patch)
        if patch.language != nil, decision.hold {
            await languageHold.enter()
        }
        if patch.language != nil, decision.failLanguage {
            throw NuumError(code: 1, message: "language failed")
        }
        if let themeFailure = decision.themeFailure, patch.theme != nil {
            throw NuumError(code: 1, message: themeFailure)
        }
        if let modelFailure = decision.modelFailure, patch.defaultModel != nil {
            throw NuumError(code: 1, message: modelFailure)
        }
        let published = finishSet(patch)
        eventsContinuation.yield(.settingsUpdated(published))
        return published
    }

    private struct SetDecision {
        var failLanguage: Bool
        var themeFailure: String?
        var modelFailure: String?
        var hold: Bool
    }

    private func beginSet(_ patch: SettingsPatch) -> SetDecision {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(patch)
        return SetDecision(
            failLanguage: failLanguage,
            themeFailure: themeFailure,
            modelFailure: modelFailure,
            hold: holdLanguage
        )
    }

    private func finishSet(_ patch: SettingsPatch) -> PublicSettings {
        lock.lock()
        defer { lock.unlock() }
        storage = PublicSettings(
            defaultToolPermission: patch.defaultToolPermission ?? storage.defaultToolPermission,
            defaultModel: patch.defaultModel ?? storage.defaultModel,
            theme: patch.theme ?? storage.theme,
            hasOpenaiKey: storage.hasOpenaiKey,
            hasAnthropicKey: storage.hasAnthropicKey,
            hasDeepseekKey: storage.hasDeepseekKey,
            language: patch.language ?? storage.language,
            sidebar: patch.sidebar ?? storage.sidebar
        )
        return storage
    }

    func emit(_ event: HostEvent) {
        eventsContinuation.yield(event)
    }
}

final class FakeClock: Clock, @unchecked Sendable {
    var now: Int64
    init(now: Int64 = 1_000_000) { self.now = now }
    func nowMillis() -> Int64 { now }
}

final class FakeProactivePort: ProactivePort, @unchecked Sendable {
    private let lock = NSLock()
    var snapshot: ProactiveSnapshot
    private var recordedConfigures: [ProactiveConfigureParams] = []
    private var recordedChecks: [String] = []
    var failConfigure = false
    var failCheck = false
    var onConfigure: (@Sendable () async -> Void)?
    let events: AsyncStream<HostEvent>
    private let eventsContinuation: AsyncStream<HostEvent>.Continuation

    init(snapshot: ProactiveSnapshot) {
        self.snapshot = snapshot
        let pair = AsyncStream<HostEvent>.makeStream()
        events = pair.stream
        eventsContinuation = pair.continuation
    }

    var configures: [ProactiveConfigureParams] {
        lock.lock()
        defer { lock.unlock() }
        return recordedConfigures
    }

    var checks: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedChecks
    }

    func get() async throws -> ProactiveSnapshot { snapshot }

    func configure(_ params: ProactiveConfigureParams) async throws -> ProactiveSnapshot {
        let (fail, hook) = beginConfigure(params)
        if let hook { await hook() }
        if fail {
            throw NuumError(code: 1, message: "Proactive policy revision conflict")
        }
        let next = applyConfigure(snapshot, params)
        snapshot = next
        eventsContinuation.yield(.proactiveUpdated(next))
        return next
    }

    func check(agentId: String) async throws -> ProactiveSnapshot {
        let fail = beginCheck(agentId)
        if fail {
            throw NuumError(code: 1, message: "check failed")
        }
        return snapshot
    }

    private func beginConfigure(_ params: ProactiveConfigureParams) -> (Bool, (@Sendable () async -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        recordedConfigures.append(params)
        return (failConfigure, onConfigure)
    }

    private func beginCheck(_ agentId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        recordedChecks.append(agentId)
        return failCheck
    }

    func emit(_ event: HostEvent) {
        eventsContinuation.yield(event)
    }
}

func sampleSettings(
    permission: ToolPermission = .ask,
    model: ModelRef = ModelRef(provider: .deepseek, model: DeepSeekModelID.reasoner),
    theme: ThemePreference = .dark,
    language: Language = .en,
    hasKeys: Bool = false
) -> PublicSettings {
    PublicSettings(
        defaultToolPermission: permission,
        defaultModel: model,
        theme: theme,
        hasOpenaiKey: hasKeys,
        hasAnthropicKey: hasKeys,
        hasDeepseekKey: hasKeys,
        language: language
    )
}

func makeSettings(
    _ initial: PublicSettings = sampleSettings()
) async -> (SettingsModel, FakeSettingsPort, RecordingSecretWriter, MemorySecretStore) {
    let store = MemorySecretStore()
    let writer = RecordingSecretWriter(store: store)
    let port = FakeSettingsPort(initial: initial)
    let model = SettingsModel(settings: port, secrets: writer)
    await model.refresh()
    return (model, port, writer, store)
}

func proactiveAgent(
    enabled: Bool = false,
    state: String = "disabled",
    pausedUntil: Int64? = nil,
    revision: Int = 4,
    name: String = "Mika",
    activity: [ProactiveActivity] = []
) -> ProactiveAgentSnapshot {
    ProactiveAgentSnapshot(
        agentId: "agent-1",
        name: name,
        policy: ProactivePolicy(
            revision: revision,
            isDefault: true,
            enabled: enabled,
            pausedUntil: pausedUntil
        ),
        state: state,
        activity: activity
    )
}

func proactiveSnapshot(
    agent: ProactiveAgentSnapshot? = nil,
    actionsAvailable: Bool = false,
    sources: [String] = [],
    defaultAgentId: String? = "agent-1"
) -> ProactiveSnapshot {
    ProactiveSnapshot(
        defaultAgentId: agent == nil ? nil : defaultAgentId,
        agents: agent.map { [$0] } ?? [],
        availableSourceIds: sources,
        actionsAvailable: actionsAvailable
    )
}

func applyConfigure(_ snapshot: ProactiveSnapshot, _ params: ProactiveConfigureParams) -> ProactiveSnapshot {
    let agents = snapshot.agents.map { agent -> ProactiveAgentSnapshot in
        if let id = params.agentId, agent.agentId != id { return agent }
        let enabled = params.enabled ?? agent.policy.enabled
        let pausedUntil: Int64? = if params.resume || params.enabled == false {
            nil
        } else if let paused = params.pausedUntil {
            paused
        } else {
            agent.policy.pausedUntil
        }
        let state = if !enabled {
            "disabled"
        } else if pausedUntil != nil {
            "paused"
        } else {
            "waiting-context"
        }
        var policy = agent.policy
        policy.enabled = enabled
        policy.pausedUntil = pausedUntil
        policy.revision += 1
        return ProactiveAgentSnapshot(
            agentId: agent.agentId,
            name: agent.name,
            policy: policy,
            state: state,
            activity: agent.activity
        )
    }
    return ProactiveSnapshot(
        defaultAgentId: snapshot.defaultAgentId,
        agents: agents,
        availableSourceIds: snapshot.availableSourceIds,
        actionsAvailable: snapshot.actionsAvailable
    )
}

func makeProactive(
    _ snapshot: ProactiveSnapshot,
    clock: FakeClock = FakeClock()
) async -> (ProactiveModel, FakeProactivePort, FakeSettingsPort, FakeClock) {
    let proactive = FakeProactivePort(snapshot: snapshot)
    let settings = FakeSettingsPort()
    let model = ProactiveModel(settings: settings, proactive: proactive, clock: clock)
    await model.refresh()
    return (model, proactive, settings, clock)
}

func containedStrings(_ value: Any, depth: Int = 0) -> [String] {
    if depth > 6 { return [] }
    var found: [String] = []
    if let string = value as? String {
        found.append(string)
    }
    for child in Mirror(reflecting: value).children {
        found.append(contentsOf: containedStrings(child.value, depth: depth + 1))
    }
    return found
}
