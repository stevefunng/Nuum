import Foundation
import NuumContracts
import NuumProtocol

extension HostRuntime {
    /// Snapshot only. No sources are registered and there is no one-second tick.
    /// `actionsAvailable` is always false.
    func proactiveSnapshot() async throws -> NuumContracts.ProactiveSnapshot {
        try await ensureLoaded()
        let agentsWithPolicy = agents.values.filter { $0.settings.proactive != nil }
        var loaded: [NuumProtocol.ProactiveAgentSnapshot] = []
        for record in agentsWithPolicy {
            let policy = record.settings.proactive ?? NuumProtocol.ProactivePolicy(revision: 0)
            loaded.append(NuumProtocol.ProactiveAgentSnapshot(
                agentId: record.profile.id,
                name: record.profile.name,
                policy: policy,
                state: proactiveState(record.profile.id, policy),
                activity: try await readActivity(record.profile.id)
            ))
        }
        let defaultId = agentsWithPolicy.first { $0.settings.proactive?.isDefault == true }?.profile.id
        let snapshot = try NuumProtocol.ProactiveSnapshot(
            defaultAgentId: defaultId,
            agents: loaded,
            availableSourceIds: [],
            actionsAvailable: false
        )
        return cProactive(snapshot)
    }

    func configureProactive(_ params: NuumContracts.ProactiveConfigureParams) async throws -> NuumContracts.ProactiveSnapshot {
        try await ensureLoaded()
        let protocolParams = NuumProtocol.ProactiveConfigureParams(
            expectedRevision: params.expectedRevision,
            agentId: params.agentId,
            enabled: params.enabled,
            pausedUntil: params.resume ? nil : params.pausedUntil,
            sourceIds: params.sourceIds,
            intervalMs: params.intervalMs
        )
        do {
            try validateProactiveConfigure(protocolParams)
        } catch let error as ProtocolParseException {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: error.message)
        }
        if let source = params.sourceIds?.first, !params.sourceIds!.isEmpty {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: "Unknown proactive source: \(source)")
        }
        var record = params.agentId.flatMap { agents[$0] } ?? agents.values.first { $0.settings.proactive?.isDefault == true }
        if record == nil {
            if params.expectedRevision != 0 {
                throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: "Proactive policy revision conflict")
            }
            let created = try await createAgentLocked(AgentCreateParams(name: "Nunu", tags: ["proactive"]))
            record = try requireAgent(created.profile.id)
            record?.settings.proactive = NuumProtocol.ProactivePolicy(revision: 0, isDefault: true)
        }
        guard let record else {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: "Proactive policy revision conflict")
        }
        let previous = record.settings.proactive ?? NuumProtocol.ProactivePolicy(revision: 0)
        if previous.revision != params.expectedRevision {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: "Proactive policy revision conflict")
        }
        let policy = NuumProtocol.ProactivePolicy(
            revision: previous.revision + 1,
            isDefault: previous.isDefault || params.agentId == nil,
            enabled: params.enabled ?? previous.enabled,
            pausedUntil: {
                if params.enabled == false { return nil }
                if params.resume { return nil }
                if let paused = params.pausedUntil { return paused }
                return previous.pausedUntil
            }(),
            sourceIds: params.sourceIds ?? previous.sourceIds,
            intervalMs: params.intervalMs ?? previous.intervalMs
        )
        do {
            try validateProactivePolicy(policy)
        } catch let error as ProtocolParseException {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: error.message)
        }
        record.settings.proactive = policy
        try await writeDoc(store, NuumPaths.agentSettingsPath(record.profile.id), record.settings)
        let pausedUntil = policy.pausedUntil
        let kind: ProactiveActivityKind = if !policy.enabled {
            .disabled
        } else if !previous.enabled {
            .enabled
        } else if let pausedUntil, pausedUntil > clock.nowMillis() {
            .paused
        } else if previous.pausedUntil != nil {
            .resumed
        } else {
            .configured
        }
        try await recordActivity(record.profile.id, kind)
        emit(.agentUpdated(viewOf(record)))
        let snapshot = try await proactiveSnapshot()
        emit(.proactiveUpdated(snapshot))
        return snapshot
    }

    func checkProactive(_ agentId: String) async throws -> NuumContracts.ProactiveSnapshot {
        try await ensureLoaded()
        guard let record = agents[agentId] else {
            throw NuumError(code: NuumContracts.HostErrorCode.agentNotFound, message: "Agent not found")
        }
        guard let policy = record.settings.proactive, policy.enabled else {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: "Proactive mode disabled")
        }
        if let pausedUntil = policy.pausedUntil, pausedUntil > clock.nowMillis() {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: "Proactive mode paused")
        }
        try await recordActivity(agentId, .waitingContext)
        let snapshot = try await proactiveSnapshot()
        emit(.proactiveUpdated(snapshot))
        return snapshot
    }

    private func proactiveState(_ agentId: String, _ policy: NuumProtocol.ProactivePolicy) -> ProactiveAgentState {
        _ = agentId
        if !policy.enabled { return .disabled }
        if let pausedUntil = policy.pausedUntil, pausedUntil > clock.nowMillis() { return .paused }
        return .waitingContext
    }

    private func readActivity(_ agentId: String) async throws -> [NuumProtocol.ProactiveActivity] {
        let path = "\(NuumPaths.agentDir(agentId))/proactive-activity.json"
        guard let text = try await store.readText(path)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return []
        }
        guard let value = try? ProtocolJSON.parse(text), case .array(let items) = value else { return [] }
        return items.compactMap { try? NuumProtocol.ProactiveActivity(protocolJSON: $0) }
    }

    private func recordActivity(_ agentId: String, _ kind: ProactiveActivityKind) async throws {
        let prior = try await readActivity(agentId)
        let next = [NuumProtocol.ProactiveActivity(id: ids(), at: clock.nowMillis(), kind: kind)] + prior
        let path = "\(NuumPaths.agentDir(agentId))/proactive-activity.json"
        let encoded = ProtocolJSON.stringify(.array(next.prefix(50).map(\.protocolJSON)))
        try await store.writeTextAtomic(path, text: encoded + "\n")
    }
}
