import Foundation
import NuumContracts

enum ProactivePause {
    static let thirtyMinutes: Int64 = 1_800_000
    static let oneHour: Int64 = 3_600_000
}

struct ProactiveUiState: Equatable, Sendable {
    var snapshot: ProactiveSnapshot?
    var loading = true
    var busy = false
    var failed = false
    var language: Language?
    var theme: ThemePreference?
}

/// Proactive panel. `actionsAvailable` is read from the snapshot.
/// Check setup calls `ProactivePort.check` and does not start a model turn.
actor ProactiveModel {
    private(set) var state: ProactiveUiState
    nonisolated let updates: AsyncStream<ProactiveUiState>
    private let updateContinuation: AsyncStream<ProactiveUiState>.Continuation
    private let settings: any SettingsPort
    private let proactive: any ProactivePort
    private let clock: any Clock
    private let settingsEvents: AsyncStream<HostEvent>
    private let proactiveEvents: AsyncStream<HostEvent>
    private var pending: PendingCall?
    private var suppressEvents = false

    init(settings: any SettingsPort, proactive: any ProactivePort, clock: any Clock) {
        self.settings = settings
        self.proactive = proactive
        self.clock = clock
        self.settingsEvents = settings.events
        self.proactiveEvents = proactive.events
        let initial = ProactiveUiState()
        self.state = initial
        let pair = AsyncStream<ProactiveUiState>.makeStream(bufferingPolicy: .bufferingNewest(32))
        self.updates = pair.stream
        self.updateContinuation = pair.continuation
        pair.continuation.yield(initial)
    }

    func snapshot() -> ProactiveUiState { state }

    func run() async {
        await refreshSettings()
        await refresh()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.watchSettings() }
            group.addTask { await self.watchProactive() }
            await group.waitForAll()
        }
    }

    func refresh() async {
        do {
            let snapshot = try await proactive.get()
            mutate {
                $0.snapshot = snapshot
                $0.loading = false
                $0.failed = false
            }
        } catch is CancellationError {
            return
        } catch {
            mutate {
                $0.loading = false
                $0.failed = true
            }
        }
    }

    func refreshSettings() async {
        do {
            let settings = try await settings.get()
            mutate {
                $0.language = settings.language
                $0.theme = settings.theme
            }
        } catch is CancellationError {
            return
        } catch {
            // The panel still renders. Copy stays on the system language.
        }
    }

    func accept(_ event: HostEvent) {
        guard !suppressEvents else { return }
        switch event {
        case .settingsUpdated(let settings):
            mutate {
                $0.language = settings.language
                $0.theme = settings.theme
            }
        case .proactiveUpdated(let snapshot):
            guard let snapshot else { return }
            mutate {
                $0.snapshot = snapshot
                $0.loading = false
            }
        default:
            break
        }
    }

    /// Flips `enabled`, clears `pausedUntil`, and sends `resume` with the current revision.
    func toggle() async {
        guard let agent = companion(), !state.busy else { return }
        await send(ProactiveConfigureParams(
            expectedRevision: agent.policy.revision,
            agentId: agent.agentId,
            enabled: !agent.policy.enabled,
            pausedUntil: nil,
            resume: true
        ))
    }

    func resume() async {
        guard let agent = companion(), !state.busy else { return }
        await send(ProactiveConfigureParams(
            expectedRevision: agent.policy.revision,
            agentId: agent.agentId,
            pausedUntil: nil,
            resume: true
        ))
    }

    func pause(_ durationMs: Int64) async {
        guard let agent = companion(), !state.busy, agent.policy.enabled else { return }
        await send(ProactiveConfigureParams(
            expectedRevision: agent.policy.revision,
            agentId: agent.agentId,
            pausedUntil: clock.nowMillis() + durationMs
        ))
    }

    func check() async {
        guard let agent = companion() else { return }
        guard !state.busy, state.snapshot != nil else { return }
        guard agent.policy.enabled, agent.state != "paused", agent.state != "checking" else { return }
        await performCheck(agent.agentId)
    }

    func retry() async {
        switch pending {
        case .configure(let params):
            await send(params)
        case .check(let agentId):
            await performCheck(agentId)
        case nil:
            await refresh()
            await refreshSettings()
        }
    }

    private func send(_ params: ProactiveConfigureParams) async {
        pending = .configure(params)
        suppressEvents = true
        mutate {
            $0.busy = true
            $0.failed = false
        }
        do {
            let snapshot = try await proactive.configure(params)
            mutate {
                $0.snapshot = snapshot
                $0.loading = false
                $0.busy = false
                $0.failed = false
            }
        } catch is CancellationError {
            mutate { $0.busy = false }
        } catch {
            mutate {
                $0.busy = false
                $0.failed = true
            }
        }
        suppressEvents = false
    }

    private func performCheck(_ agentId: String) async {
        pending = .check(agentId)
        suppressEvents = true
        mutate {
            $0.busy = true
            $0.failed = false
        }
        do {
            let snapshot = try await proactive.check(agentId: agentId)
            mutate {
                $0.snapshot = snapshot
                $0.loading = false
                $0.busy = false
                $0.failed = false
            }
        } catch is CancellationError {
            mutate { $0.busy = false }
        } catch {
            mutate {
                $0.busy = false
                $0.failed = true
            }
        }
        suppressEvents = false
    }

    private func watchSettings() async {
        for await event in settingsEvents {
            accept(event)
        }
    }

    private func watchProactive() async {
        for await event in proactiveEvents {
            if case .proactiveUpdated(nil) = event, !suppressEvents {
                await refresh()
            } else {
                accept(event)
            }
        }
    }

    private func companion() -> ProactiveAgentSnapshot? {
        proactiveCompanion(state.snapshot)
    }

    private func mutate(_ body: (inout ProactiveUiState) -> Void) {
        body(&state)
        updateContinuation.yield(state)
    }

    private enum PendingCall {
        case configure(ProactiveConfigureParams)
        case check(String)
    }
}
