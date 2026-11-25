import Foundation
import NuumContracts
import NuumProtocol

extension HostRuntime {
    func readPublicSettings() async throws -> NuumContracts.PublicSettings {
        try await ensureLoaded()
        let secrets = pSecrets(try await secretStore.read())
        return cPublicSettings(settings.toPublic(secrets))
    }

    func applySettings(_ patch: SettingsPatch) async throws -> NuumContracts.PublicSettings {
        try await ensureLoaded()
        let sidebar = try patch.sidebar.map { raw -> NuumProtocol.SidebarOrganization in
            do {
                return try validateSidebar(pSidebar(raw))
            } catch let error as ProtocolParseException {
                throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: error.message)
            }
        }
        let next = NuumProtocol.Settings(
            defaultToolPermission: patch.defaultToolPermission.map(pPermission) ?? settings.defaultToolPermission,
            defaultModel: patch.defaultModel.map(pModel) ?? settings.defaultModel,
            theme: patch.theme.map(pTheme) ?? settings.theme,
            language: patch.language.map(pLanguage) ?? settings.language,
            sidebar: patch.sidebar != nil ? sidebar : settings.sidebar
        )
        settings = next
        try await writeDoc(store, NuumPaths.settingsPath(), next)
        let published = try await readPublicSettings()
        emit(.settingsUpdated(published))
        return published
    }

    func listAgents() async throws -> [NuumContracts.AgentView] {
        try await ensureLoaded()
        return agents.values.map { viewOf($0) }
    }

    func snapshot(_ id: String) async throws -> AgentSnapshot {
        try await ensureLoaded()
        let record = try requireAgent(id)
        let events = try await readTranscript(store, NuumPaths.transcriptPath(id))
        let live = liveParts[id].map { NuumProtocol.LiveAssistant(messageId: $0.messageId, parts: $0.parts) }
        let projection = projectAgent(events, live: live)
        return AgentSnapshot(
            view: viewOf(record),
            events: events.map(cTranscript),
            blocks: projection.blocks.map(cBlock),
            live: live.map { NuumContracts.LiveAssistant(messageId: $0.messageId, parts: $0.parts.map(cPart)) }
        )
    }

    func createAgent(_ params: AgentCreateParams) async throws -> NuumContracts.AgentView {
        try await ensureLoaded()
        return try await createAgentLocked(params)
    }

    func createAgentLocked(_ params: AgentCreateParams) async throws -> NuumContracts.AgentView {
        if agents.count >= maxAgents {
            throw NuumError(code: NuumContracts.KernelErrorCode.invalid, message: maxAgentsMessage)
        }
        let id = ids()
        let now = clock.nowMillis()
        let roll = rollAgentAvatar()
        let color = params.avatarColor.map { resolveAgentAvatarColor(agentId: id, requested: $0).id } ?? roll.color
        let tags = try params.tags.map { try normalizeAgentTags($0) } ?? []
        let profile = NuumProtocol.AgentProfile(
            id: id,
            name: params.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? NuumProtocol.defaultAgentName,
            description: params.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            createdAt: now,
            tags: tags,
            avatarColor: color,
            avatarShape: params.avatarShape ?? roll.shape,
            avatarMaterial: params.avatarMaterial ?? roll.material
        )
        let agentSettings = NuumProtocol.AgentSettings(
            model: params.model.map(pModel) ?? settings.defaultModel,
            workspace: params.workspace.map(pWorkspace)
        )
        let record = AgentRecord(profile: profile, settings: agentSettings, lastSeq: 0, lastActivityAt: now, readCursor: 0)
        agents[id] = record
        do {
            try await writeDoc(store, NuumPaths.profilePath(id), profile)
            try await writeDoc(store, NuumPaths.agentSettingsPath(id), agentSettings)
        } catch {
            agents.removeValue(forKey: id)
            throw error
        }
        let view = viewOf(record)
        emit(.agentUpdated(view))
        return view
    }

    func updateAgent(_ params: AgentUpdateParams) async throws -> NuumContracts.AgentView {
        try await ensureLoaded()
        let record = try requireAgent(params.id)
        let tags = try params.tags.map { try normalizeAgentTags($0) }
        record.profile.name = params.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? record.profile.name
        record.profile.description = params.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? record.profile.description
        if let tags { record.profile.tags = tags }
        if let color = params.avatarColor { record.profile.avatarColor = color }
        if let shape = params.avatarShape { record.profile.avatarShape = shape }
        if let material = params.avatarMaterial { record.profile.avatarMaterial = material }
        if let model = params.model { record.settings.model = pModel(model) }
        if let workspace = params.workspace { record.settings.workspace = pWorkspace(workspace) }
        if let execution = params.execution { record.settings.execution = pExecution(execution) }
        if let hidden = params.hiddenFromSidebar { record.settings.hiddenFromSidebar = hidden }
        try await writeDoc(store, NuumPaths.profilePath(params.id), record.profile)
        try await writeDoc(store, NuumPaths.agentSettingsPath(params.id), record.settings)
        let view = viewOf(record)
        emit(.agentUpdated(view))
        return view
    }

    func deleteAgent(_ id: String) async throws {
        try await ensureLoaded()
        try await cancelAgent(id)
        guard agents.removeValue(forKey: id) != nil else {
            throw NuumError(code: NuumContracts.HostErrorCode.agentNotFound, message: "Agent not found")
        }
        _ = wakes.drop(toId: id)
        try await store.delete(NuumPaths.agentDir(id))
    }

    func readTranscriptPage(_ query: TranscriptQuery) async throws -> TranscriptPage {
        try await ensureLoaded()
        _ = try requireAgent(query.id)
        let events = try await readTranscript(store, NuumPaths.transcriptPath(query.id))
        let filtered = events.filter { query.beforeSeq == nil || $0.seq < (query.beforeSeq ?? 0) }
        let slice = query.limit.map { Array(filtered.suffix($0)) } ?? filtered
        let next = slice.count < filtered.count ? slice.first?.seq : nil
        let last = events.map(\.seq).max() ?? 0
        agents[query.id]?.readCursor = last
        try await writeDoc(store, NuumPaths.readCursorPath(query.id), ReadCursor(seq: last))
        return TranscriptPage(id: query.id, entries: slice.map(cTranscript), nextBeforeSeq: next)
    }

    func requireAgent(_ id: String) throws -> AgentRecord {
        guard let record = agents[id] else {
            throw NuumError(code: NuumContracts.HostErrorCode.agentNotFound, message: "Agent not found")
        }
        return record
    }

    func viewOf(_ record: AgentRecord) -> NuumContracts.AgentView {
        let active = scheduler.activeRunFor(record.profile.id)
        let status: NuumProtocol.AgentStatus
        if active != nil {
            status = .running
        } else if errored.contains(record.profile.id) {
            status = .error
        } else {
            status = .idle
        }
        let runtime = NuumProtocol.AgentRuntime(
            status: status,
            unread: record.lastSeq > record.readCursor,
            lastActivityAt: record.lastActivityAt,
            activeRunId: active
        )
        return cAgentView(profile: record.profile, settings: record.settings, runtime: runtime, rooms: roomsFor(record.profile.id))
    }

    func roomsFor(_ agentId: String) -> [String: NuumProtocol.WorkMembership] {
        var rooms: [String: NuumProtocol.WorkMembership] = [:]
        for (workId, members) in memberships {
            guard let membership = members[agentId], membership.binding != nil else { continue }
            rooms[workId] = membership
        }
        return rooms
    }

    func membershipOf(_ workId: String, _ agentId: String) -> NuumProtocol.WorkMembership {
        memberships[workId]?[agentId] ?? NuumProtocol.WorkMembership(revision: 0, binding: nil)
    }

    func applyMembership(_ event: NuumProtocol.WorkEvent) {
        switch event {
        case .memberAttached(let attached):
            var members = memberships[attached.header.workId] ?? [:]
            members[attached.agentId] = NuumProtocol.WorkMembership(
                revision: attached.membershipRevision,
                binding: NuumProtocol.WorkBinding(
                    workId: attached.header.workId,
                    role: attached.role,
                    joinedAt: attached.header.createdAt,
                    grants: grantsFor(attached.role)
                )
            )
            memberships[attached.header.workId] = members
        case .memberDetached(let detached):
            var members = memberships[detached.header.workId] ?? [:]
            members[detached.agentId] = NuumProtocol.WorkMembership(revision: detached.membershipRevision, binding: nil)
            memberships[detached.header.workId] = members
        default:
            break
        }
    }

    func claimReceipts(_ agentId: String, _ events: [NuumProtocol.TranscriptEvent]) async throws {
        let path = "\(NuumPaths.agentDir(agentId))/execution-receipts.json"
        let receipts = try await readReceipts(store, path)
        if receipts.isEmpty { return }
        var current = events
        for receipt in receipts {
            let claimed = try claimExecutionResult(events: current, record: receipt, now: clock.nowMillis(), newId: ids)
            for event in claimed {
                try await appendTranscriptLine(store, NuumPaths.transcriptPath(agentId), event)
                current.append(event)
            }
        }
        try await store.writeTextAtomic(path, text: "[]\n")
        if let record = agents[agentId] {
            record.lastSeq = current.map(\.seq).max() ?? record.lastSeq
            record.lastActivityAt = current.map(\.createdAt).max() ?? record.lastActivityAt
        }
    }
}

extension NuumProtocol.Settings {
    func toPublic(_ secrets: NuumProtocol.Secrets) -> NuumProtocol.PublicSettings {
        NuumProtocol.PublicSettings(
            defaultToolPermission: defaultToolPermission,
            defaultModel: defaultModel,
            theme: theme,
            hasOpenaiKey: !(secretForProvider(secrets, .openai) ?? "").isEmpty,
            hasAnthropicKey: !(secretForProvider(secrets, .anthropic) ?? "").isEmpty,
            hasDeepseekKey: !(secretForProvider(secrets, .deepseek) ?? "").isEmpty,
            language: language,
            sidebar: sidebar
        )
    }
}

func grantsFor(_ role: NuumProtocol.WorkRole) -> NuumProtocol.WorkGrants {
    switch role {
    case .coordinator: NuumProtocol.WorkGrants(canPost: true, canManageOwnTasks: true, canAssignTasks: true, canEditCatalog: true)
    case .worker: NuumProtocol.WorkGrants(canPost: true, canManageOwnTasks: true, canAssignTasks: false, canEditCatalog: false)
    case .observer: NuumProtocol.WorkGrants(canPost: false, canManageOwnTasks: false, canAssignTasks: false, canEditCatalog: false)
    }
}

func deriveName(_ content: String) -> String {
    let line = content.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if line.isEmpty { return NuumProtocol.defaultAgentName }
    if line.count <= 42 { return line }
    return String(line.prefix(41)) + "…"
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
