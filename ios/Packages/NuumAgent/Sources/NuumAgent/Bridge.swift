import Foundation
import NuumContracts
import NuumProtocol

func cJSON(_ value: NuumProtocol.JSONValue) -> NuumContracts.JSONValue {
    switch value {
    case .null:
        return NuumContracts.JSONValue.null
    case .bool(let flag):
        return .bool(flag)
    case .int(let number):
        return .int(number)
    case .double(let number):
        return .double(number)
    case .string(let text):
        return .string(text)
    case .array(let items):
        return .array(items.map(cJSON))
    case .object(let pairs):
        var object: [String: NuumContracts.JSONValue] = [:]
        for (key, item) in pairs { object[key] = cJSON(item) }
        return .object(object)
    }
}

func pJSON(_ value: NuumContracts.JSONValue) -> NuumProtocol.JSONValue {
    switch value {
    case .null:
        return NuumProtocol.JSONValue.null
    case .bool(let flag):
        return .bool(flag)
    case .int(let number):
        return .int(number)
    case .double(let number):
        return .double(number)
    case .string(let text):
        return .string(text)
    case .array(let items):
        return .array(items.map(pJSON))
    case .object(let object):
        return .object(object.keys.sorted().map { ($0, pJSON(object[$0] ?? .null)) })
    }
}

func cArgs(_ value: NuumProtocol.JSONValue) -> [String: NuumContracts.JSONValue] {
    guard case .object = value else { return [:] }
    if case .object(let object) = cJSON(value) { return object }
    return [:]
}

func pObject(_ args: [String: NuumContracts.JSONValue]) -> NuumProtocol.JSONValue {
    .object(args.keys.sorted().map { ($0, pJSON(args[$0] ?? .null)) })
}

func cProvider(_ value: NuumProtocol.ProviderId) -> NuumContracts.ProviderId { sameRaw(value) }
func pProvider(_ value: NuumContracts.ProviderId) -> NuumProtocol.ProviderId { sameRaw(value) }
func cModel(_ value: NuumProtocol.ModelRef) -> NuumContracts.ModelRef {
    NuumContracts.ModelRef(provider: cProvider(value.provider), model: value.model)
}
func pModel(_ value: NuumContracts.ModelRef) -> NuumProtocol.ModelRef {
    NuumProtocol.ModelRef(provider: pProvider(value.provider), model: value.model)
}
func cSecrets(_ value: NuumProtocol.Secrets) -> NuumContracts.Secrets {
    NuumContracts.Secrets(openaiApiKey: value.openaiApiKey, anthropicApiKey: value.anthropicApiKey, deepseekApiKey: value.deepseekApiKey)
}
func pSecrets(_ value: NuumContracts.Secrets) -> NuumProtocol.Secrets {
    NuumProtocol.Secrets(openaiApiKey: value.openaiApiKey, anthropicApiKey: value.anthropicApiKey, deepseekApiKey: value.deepseekApiKey)
}
func cPermission(_ value: NuumProtocol.ToolPermission) -> NuumContracts.ToolPermission { sameRaw(value) }
func pPermission(_ value: NuumContracts.ToolPermission) -> NuumProtocol.ToolPermission { sameRaw(value) }
func cTheme(_ value: NuumProtocol.ThemePreference) -> NuumContracts.ThemePreference { sameRaw(value) }
func pTheme(_ value: NuumContracts.ThemePreference) -> NuumProtocol.ThemePreference { sameRaw(value) }
func cLanguage(_ value: NuumProtocol.Language) -> NuumContracts.Language { sameRaw(value) }
func pLanguage(_ value: NuumContracts.Language) -> NuumProtocol.Language { sameRaw(value) }
func cAction(_ value: NuumProtocol.LocalToolAction) -> NuumContracts.LocalToolAction { sameRaw(value) }
func pAction(_ value: NuumContracts.LocalToolAction) -> NuumProtocol.LocalToolAction { sameRaw(value) }
func cRole(_ value: NuumProtocol.MessageRole) -> NuumContracts.MessageRole { sameRaw(value) }
func cStatus(_ value: NuumProtocol.AgentStatus) -> NuumContracts.AgentStatus { sameRaw(value) }
func cWorkKind(_ value: NuumProtocol.WorkKind) -> NuumContracts.WorkKind { sameRaw(value) }
func pWorkKind(_ value: NuumContracts.WorkKind) -> NuumProtocol.WorkKind { sameRaw(value) }
func cWorkRole(_ value: NuumProtocol.WorkRole) -> NuumContracts.WorkRole { sameRaw(value) }
func pWorkRole(_ value: NuumContracts.WorkRole) -> NuumProtocol.WorkRole { sameRaw(value) }
func cTaskState(_ value: NuumProtocol.WorkTaskState) -> NuumContracts.WorkTaskState { sameRaw(value) }
func pTaskState(_ value: NuumContracts.WorkTaskState) -> NuumProtocol.WorkTaskState { sameRaw(value) }
func cPriority(_ value: NuumProtocol.WorkTaskPriority) -> NuumContracts.WorkTaskPriority { sameRaw(value) }
func cCommandPermission(_ value: NuumProtocol.CommandPermission) -> NuumContracts.CommandPermission { sameRaw(value) }
func pCommandPermission(_ value: NuumContracts.CommandPermission) -> NuumProtocol.CommandPermission { sameRaw(value) }

func cSidebar(_ value: NuumProtocol.SidebarOrganization) -> NuumContracts.SidebarOrganization {
    NuumContracts.SidebarOrganization(
        pinnedAgentIds: value.pinnedAgentIds,
        sections: value.sections.map {
            NuumContracts.SidebarSection(id: $0.id, name: $0.name, agentIds: $0.agentIds, isCollapsed: $0.isCollapsed == true)
        }
    )
}

func pSidebar(_ value: NuumContracts.SidebarOrganization) -> NuumProtocol.SidebarOrganization {
    NuumProtocol.SidebarOrganization(
        pinnedAgentIds: value.pinnedAgentIds,
        sections: value.sections.map {
            NuumProtocol.SidebarSection(id: $0.id, name: $0.name, agentIds: $0.agentIds, isCollapsed: $0.isCollapsed)
        }
    )
}

func cSettings(_ value: NuumProtocol.Settings) -> NuumContracts.Settings {
    NuumContracts.Settings(
        defaultToolPermission: cPermission(value.defaultToolPermission),
        defaultModel: cModel(value.defaultModel),
        theme: cTheme(value.theme),
        language: value.language.map(cLanguage) ?? .zhCN,
        sidebar: value.sidebar.map(cSidebar)
    )
}

func pSettings(_ value: NuumContracts.Settings) -> NuumProtocol.Settings {
    NuumProtocol.Settings(
        defaultToolPermission: pPermission(value.defaultToolPermission),
        defaultModel: pModel(value.defaultModel),
        theme: pTheme(value.theme),
        language: pLanguage(value.language),
        sidebar: value.sidebar.map(pSidebar)
    )
}

func cPublicSettings(_ value: NuumProtocol.PublicSettings) -> NuumContracts.PublicSettings {
    NuumContracts.PublicSettings(
        defaultToolPermission: cPermission(value.defaultToolPermission),
        defaultModel: cModel(value.defaultModel),
        theme: cTheme(value.theme),
        hasOpenaiKey: value.hasOpenaiKey,
        hasAnthropicKey: value.hasAnthropicKey,
        hasDeepseekKey: value.hasDeepseekKey,
        language: value.language.map(cLanguage) ?? .zhCN,
        sidebar: value.sidebar.map(cSidebar)
    )
}

func cWorkspace(_ value: NuumProtocol.WorkspaceSettings) -> NuumContracts.WorkspaceSettings {
    NuumContracts.WorkspaceSettings(projectRoot: value.projectRoot, toolPermission: value.toolPermission.map(cPermission))
}

func pWorkspace(_ value: NuumContracts.WorkspaceSettings) -> NuumProtocol.WorkspaceSettings {
    NuumProtocol.WorkspaceSettings(projectRoot: value.projectRoot, toolPermission: value.toolPermission.map(pPermission))
}

func cExecution(_ value: NuumProtocol.ExecutionPreferences) -> NuumContracts.ExecutionPreferences {
    NuumContracts.ExecutionPreferences(
        workspaceId: value.workspaceId,
        commands: cCommandPermission(value.commands),
        commandGrants: value.commandGrants.map { NuumContracts.CommandGrant(workspaceId: $0.workspaceId, command: $0.command) },
        networkGrants: value.networkGrants.map { NuumContracts.NetworkGrant(workspaceId: $0.workspaceId, target: $0.target) }
    )
}

func pExecution(_ value: NuumContracts.ExecutionPreferences) -> NuumProtocol.ExecutionPreferences {
    NuumProtocol.ExecutionPreferences(
        workspaceId: value.workspaceId,
        commands: pCommandPermission(value.commands),
        commandGrants: value.commandGrants.map { NuumProtocol.CommandGrant(workspaceId: $0.workspaceId, command: $0.command) },
        networkGrants: value.networkGrants.map { NuumProtocol.NetworkGrant(workspaceId: $0.workspaceId, target: $0.target) }
    )
}

func cPolicy(_ value: NuumProtocol.ProactivePolicy) -> NuumContracts.ProactivePolicy {
    NuumContracts.ProactivePolicy(
        revision: value.revision,
        isDefault: value.isDefault,
        enabled: value.enabled,
        pausedUntil: value.pausedUntil,
        sourceIds: value.sourceIds,
        intervalMs: value.intervalMs
    )
}

func pPolicy(_ value: NuumContracts.ProactivePolicy) -> NuumProtocol.ProactivePolicy {
    NuumProtocol.ProactivePolicy(
        revision: value.revision,
        isDefault: value.isDefault,
        enabled: value.enabled,
        pausedUntil: value.pausedUntil,
        sourceIds: value.sourceIds,
        intervalMs: value.intervalMs
    )
}

func cMembership(_ value: NuumProtocol.WorkMembership) -> NuumContracts.WorkMembership {
    NuumContracts.WorkMembership(
        revision: value.revision,
        binding: value.binding.map { binding in
            NuumContracts.WorkBinding(
                workId: binding.workId,
                role: cWorkRole(binding.role),
                joinedAt: binding.joinedAt,
                grants: NuumContracts.WorkGrants(
                    canPost: binding.grants.canPost,
                    canManageOwnTasks: binding.grants.canManageOwnTasks,
                    canAssignTasks: binding.grants.canAssignTasks,
                    canEditCatalog: binding.grants.canEditCatalog
                )
            )
        }
    )
}

func cProfile(_ value: NuumProtocol.AgentProfile) -> NuumContracts.AgentProfile {
    NuumContracts.AgentProfile(
        id: value.id,
        name: value.name,
        description: value.description,
        createdAt: value.createdAt,
        tags: value.tags ?? [],
        avatarColor: value.avatarColor,
        avatarShape: value.avatarShape,
        avatarMaterial: value.avatarMaterial
    )
}

func cAgentSettings(_ value: NuumProtocol.AgentSettings, room: NuumContracts.WorkMembership? = nil) -> NuumContracts.AgentSettings {
    NuumContracts.AgentSettings(
        model: cModel(value.model),
        execution: value.execution.map(cExecution),
        workspace: value.workspace.map(cWorkspace),
        hiddenFromSidebar: value.hiddenFromSidebar == true,
        proactive: value.proactive.map(cPolicy),
        workMembership: room ?? value.workMembership.map(cMembership)
    )
}

func cRuntime(_ value: NuumProtocol.AgentRuntime) -> NuumContracts.AgentRuntime {
    NuumContracts.AgentRuntime(
        status: cStatus(value.status),
        unread: value.unread,
        lastActivityAt: value.lastActivityAt,
        activeRunId: value.activeRunId
    )
}

func cAgentView(
    profile: NuumProtocol.AgentProfile,
    settings: NuumProtocol.AgentSettings,
    runtime: NuumProtocol.AgentRuntime,
    rooms: [String: NuumProtocol.WorkMembership]
) -> NuumContracts.AgentView {
    NuumContracts.AgentView(
        profile: cProfile(profile),
        settings: cAgentSettings(settings),
        runtime: cRuntime(runtime),
        roomMemberships: rooms.mapValues(cMembership)
    )
}

func cMessage(_ value: NuumProtocol.ChatMessage) -> NuumContracts.ChatMessage {
    NuumContracts.ChatMessage(
        id: value.id,
        role: cRole(value.role),
        content: value.content,
        seq: value.seq,
        createdAt: value.createdAt,
        images: value.images?.map { NuumContracts.ModelImage(mimeType: $0.mimeType, data: $0.data) },
        thinking: value.thinking,
        toolCalls: value.toolCalls?.map { NuumContracts.ToolCall(id: $0.id, name: $0.name, arguments: cArgs($0.arguments)) },
        toolCallId: value.toolCallId,
        name: value.name
    )
}

func cToolDefinition(_ value: NuumProtocol.ToolDefinition) -> NuumContracts.ToolDefinition {
    NuumContracts.ToolDefinition(
        name: value.name,
        description: value.description,
        inputSchema: cArgs(value.inputSchema),
        mutating: value.mutating,
        action: value.action.map(cAction)
    )
}

func cApproval(_ value: NuumProtocol.ToolApproval) -> NuumContracts.ToolApproval {
    NuumContracts.ToolApproval(action: cAction(value.action), target: value.target)
}

func cTranscript(_ value: NuumProtocol.TranscriptEvent) -> NuumContracts.TranscriptEvent {
    switch value {
    case .user(let id, let seq, let createdAt, let text, let attachments, let widgetAnswerTo):
        return .user(NuumContracts.UserTranscript(
            id: id,
            seq: seq,
            createdAt: createdAt,
            text: text,
            attachments: (attachments ?? []).map {
                NuumContracts.UserAttachment(name: $0.name, path: $0.path, mimeType: $0.mimeType, size: $0.size, text: $0.text)
            },
            widgetAnswerTo: widgetAnswerTo
        ))
    case .wake(let id, let seq, let createdAt, let source, let text, let hops):
        return .wake(NuumContracts.WakeTranscript(id: id, seq: seq, createdAt: createdAt, source: cWake(source), text: text, hops: hops))
    case .assistant(let id, let seq, let createdAt, let parts):
        return .assistant(NuumContracts.AssistantTranscript(id: id, seq: seq, createdAt: createdAt, parts: parts.map(cPart)))
    case .tool(let id, let seq, let createdAt, let assistantId, let toolCallId, _, _, let name, let content, let ok, let spillPath):
        return .tool(NuumContracts.ToolTranscript(
            id: id, seq: seq, createdAt: createdAt, toolCallId: toolCallId, name: name, content: content,
            assistantId: assistantId, ok: ok, spillPath: spillPath
        ))
    case .message(let id, let seq, let createdAt, let assistantId, let toolCallId, let payload):
        return .message(NuumContracts.MessageTranscript(
            id: id, seq: seq, createdAt: createdAt, payload: cOutbound(payload), assistantId: assistantId, toolCallId: toolCallId
        ))
    case .compact(let id, let seq, let createdAt, let epoch, let throughSeq, let tailFromSeq, let summary, _, _):
        return .compact(NuumContracts.CompactTranscript(
            id: id, seq: seq, createdAt: createdAt, epoch: epoch, throughSeq: throughSeq, tailFromSeq: tailFromSeq, summary: summary
        ))
    case .profile(let id, let seq, let createdAt, let patch):
        return .profile(NuumContracts.ProfileTranscript(
            id: id, seq: seq, createdAt: createdAt, name: patch.name, description: patch.description, tags: patch.tags
        ))
    }
}

func cPart(_ value: NuumProtocol.AssistantPart) -> NuumContracts.AssistantPart {
    switch value {
    case .thinking(let text): .thinking(NuumContracts.ThinkingPart(text: text))
    case .text(let text): .text(NuumContracts.TextPart(text: text))
    case .toolCall(let id, let executionId, let name, let arguments):
        .toolCall(NuumContracts.ToolCallPart(id: id, name: name, arguments: cArgs(arguments), executionId: executionId))
    }
}

func cWake(_ value: NuumProtocol.WakeSource) -> NuumContracts.WakeSource {
    switch value {
    case .agent(let fromId, let fromName, let priority):
        .agent(NuumContracts.AgentWakeSource(fromId: fromId, fromName: fromName, priority: priority == true))
    case .work(let workId, let workName, let bridgeId, let taskId, _):
        .work(NuumContracts.WorkWakeSource(workId: workId, workName: workName, bridgeId: bridgeId, taskId: taskId))
    case .routine(let routineId, let routineName):
        .routine(NuumContracts.RoutineWakeSource(routineId: routineId, routineName: routineName))
    }
}

func cOutbound(_ value: NuumProtocol.OutboundMessage) -> NuumContracts.OutboundMessage {
    switch value {
    case .text(let content, let images):
        .text(NuumContracts.TextOutbound(
            content: content,
            images: (images ?? []).map { NuumContracts.OutboundImage(path: $0.path, alt: $0.alt) }
        ))
    case .attachment(let path, let caption):
        .attachment(NuumContracts.AttachmentOutbound(path: path, caption: caption))
    case .widget(let widget):
        .widget(NuumContracts.WidgetPayload(
            prompt: widget.prompt,
            options: widget.options.map {
                NuumContracts.WidgetOption(label: $0.label, value: $0.value, description: $0.description, style: $0.style?.rawValue)
            },
            helpText: widget.helpText,
            allowCustom: widget.allowCustom == true
        ))
    case .legacyWidget(let widget, let props):
        .legacyWidget(NuumContracts.LegacyWidgetOutbound(widget: widget, props: props.map(cArgs) ?? [:]))
    }
}

func cBlock(_ value: NuumProtocol.ViewBlock) -> NuumContracts.ViewBlock {
    switch value {
    case .user(let id, let text, let attachments, let widgetAnswerTo):
        .user(NuumContracts.UserBlock(
            id: id,
            text: text,
            attachments: (attachments ?? []).map {
                NuumContracts.UserAttachment(name: $0.name, path: $0.path, mimeType: $0.mimeType, size: $0.size, text: $0.text)
            },
            widgetAnswerTo: widgetAnswerTo
        ))
    case .assistant(let id, let thinking, let tools, let live):
        .assistant(NuumContracts.AssistantBlock(
            id: id,
            thinking: thinking,
            tools: tools.map {
                NuumContracts.ToolView(id: $0.id, name: $0.name, arguments: cArgs($0.arguments), output: $0.output, status: $0.status.rawValue)
            },
            live: live == true
        ))
    case .message(let id, let payload):
        .message(NuumContracts.MessageBlock(id: id, payload: cOutbound(payload)))
    case .peer(let id, let direction, let agentId, let agentName, let text, let priority):
        .peer(NuumContracts.PeerBlock(
            id: id, direction: direction.rawValue, agentId: agentId, agentName: agentName, text: text, priority: priority
        ))
    case .notice(let id, let kind, let text):
        .notice(NuumContracts.NoticeBlock(id: id, kind: kind.rawValue, text: text))
    }
}

func cWorkProfile(_ value: NuumProtocol.WorkProfile) -> NuumContracts.WorkProfile {
    NuumContracts.WorkProfile(
        id: value.id,
        name: value.name,
        description: value.description,
        projectRoot: value.projectRoot,
        createdAt: value.createdAt,
        kind: value.kind.map(cWorkKind),
        avatar: value.avatar,
        workspaceId: value.workspaceId
    )
}

func cTask(_ value: NuumProtocol.WorkTask) -> NuumContracts.WorkTask {
    NuumContracts.WorkTask(
        id: value.id,
        title: value.title,
        description: value.description,
        acceptanceCriteria: value.acceptanceCriteria,
        state: cTaskState(value.state),
        assigneeIds: value.assigneeIds,
        dependencyIds: value.dependencyIds,
        priority: cPriority(value.priority),
        revision: value.revision,
        deliverables: value.deliverables.map {
            NuumContracts.WorkDeliverable(id: $0.id, name: $0.name, uri: $0.uri, createdAt: $0.createdAt, mimeType: $0.mimeType)
        },
        createdAt: value.createdAt,
        updatedAt: value.updatedAt,
        ownerAgentId: value.ownerAgentId,
        blocker: value.blocker.map {
            NuumContracts.WorkBlocker(reason: $0.reason, ownerId: $0.ownerId, resumeCondition: $0.resumeCondition, createdAt: $0.createdAt)
        }
    )
}

func cCatalog(_ value: NuumProtocol.WorkCatalog) -> NuumContracts.WorkCatalog {
    NuumContracts.WorkCatalog(revision: value.revision, entries: value.entries.compactMap(cCatalogEntry))
}

func cCatalogEntry(_ value: NuumProtocol.WorkCatalogEntry) -> NuumContracts.WorkCatalogEntry? {
    switch value {
    case .skill(let id, let name, let description, let enabled, let manifestPath):
        .skill(NuumContracts.SkillCatalogEntry(id: id, name: name, description: description, enabled: enabled, manifestPath: manifestPath))
    case .cli(let id, let name, let description, let enabled, let executable, let allowedSubcommands):
        .cli(NuumContracts.CliCatalogEntry(
            id: id, name: name, description: description, enabled: enabled, executable: executable, allowedSubcommands: allowedSubcommands
        ))
    case .knowledge(let id, let name, let description, let enabled, let roots, let readOnly):
        .knowledge(NuumContracts.KnowledgeCatalogEntry(
            id: id, name: name, description: description, enabled: enabled, roots: roots, readOnly: readOnly
        ))
    case .localTool(let id, let name, let description, let enabled, let toolNames):
        .localTool(NuumContracts.LocalToolCatalogEntry(id: id, name: name, description: description, enabled: enabled, toolNames: toolNames))
    }
}

func catalogEntryID(_ value: NuumProtocol.WorkCatalogEntry) -> String {
    switch value {
    case .skill(let id, _, _, _, _): id
    case .cli(let id, _, _, _, _, _): id
    case .knowledge(let id, _, _, _, _, _): id
    case .localTool(let id, _, _, _, _): id
    }
}

func cWorkEvent(_ value: NuumProtocol.WorkEvent) -> NuumContracts.WorkEvent? {
    let header = value.header
    let body: NuumContracts.WorkEventBody
    let type: String
    switch value {
    case .chatPosted(let event):
        type = "chat.posted"
        body = .chatPosted(NuumContracts.ChatPostedBody(
            messageId: event.messageId, body: event.body, mentionedAgentIds: event.mentionedAgentIds,
            inputAfterSeq: event.inputAfterSeq, sourceSessionId: event.sourceSessionId, taskId: event.taskId
        ))
    case .taskCreated(let event):
        type = "task.created"
        body = .taskCreated(cTask(event.task))
    case .taskTransitioned(let event):
        type = "task.transitioned"
        body = .taskTransitioned(NuumContracts.TaskTransitionedBody(
            taskId: event.taskId,
            from: cTaskState(event.from),
            to: cTaskState(event.to),
            revision: event.revision,
            blocker: event.blocker.map {
                NuumContracts.WorkBlocker(reason: $0.reason, ownerId: $0.ownerId, resumeCondition: $0.resumeCondition, createdAt: header.createdAt)
            }
        ))
    case .memberAttached(let event):
        type = "member.attached"
        body = .memberAttached(NuumContracts.MemberAttachedBody(
            membershipOperationId: event.membershipOperationId,
            agentId: event.agentId,
            role: cWorkRole(event.role),
            membershipRevision: event.membershipRevision
        ))
    case .memberDetached(let event):
        type = "member.detached"
        body = .memberDetached(NuumContracts.MemberDetachedBody(
            membershipOperationId: event.membershipOperationId,
            agentId: event.agentId,
            membershipRevision: event.membershipRevision
        ))
    case .discussionStarted(let event):
        type = "discussion.started"
        body = .discussionStarted(NuumContracts.DiscussionStartedBody(triggerEventIds: event.triggerEventIds))
    case .discussionFinished(let event):
        type = "discussion.finished"
        body = .discussionFinished(NuumContracts.DiscussionFinishedBody(
            discussionId: event.discussionId, status: event.status.rawValue, error: event.error
        ))
    case .workRequested(let event):
        type = "work.requested"
        body = .workRequested(NuumContracts.WorkRequestedBody(
            agentId: event.agentId, instruction: event.instruction, membershipRevision: event.membershipRevision,
            taskId: event.taskId, inputAfterSeq: event.inputAfterSeq
        ))
    case .executionFinished(let event):
        type = "execution.finished"
        body = .executionFinished(NuumContracts.ExecutionFinishedBody(
            executionId: event.executionId, sourceEventId: event.sourceEventId, agentId: event.agentId,
            status: event.status.rawValue, taskId: event.taskId, error: event.error
        ))
    default:
        return nil
    }
    return NuumContracts.WorkEvent(
        type: type,
        id: header.id,
        workId: header.workId,
        seq: header.seq,
        createdAt: header.createdAt,
        actor: cActor(header.actor),
        body: body,
        causationId: header.causationId,
        correlationId: header.correlationId,
        clientEventId: header.clientEventId
    )
}

func cActor(_ value: NuumProtocol.WorkActor) -> NuumContracts.WorkActor {
    switch value {
    case .user(let id): .user(NuumContracts.UserActor(id: id))
    case .agent(let id): .agent(NuumContracts.AgentActor(id: id))
    case .system(let id): .system(NuumContracts.SystemActor(id: id))
    }
}

func cProactive(_ value: NuumProtocol.ProactiveSnapshot) -> NuumContracts.ProactiveSnapshot {
    NuumContracts.ProactiveSnapshot(
        defaultAgentId: value.defaultAgentId,
        agents: value.agents.map { agent in
            NuumContracts.ProactiveAgentSnapshot(
                agentId: agent.agentId,
                name: agent.name,
                policy: cPolicy(agent.policy),
                state: agent.state.rawValue,
                activity: agent.activity.map {
                    NuumContracts.ProactiveActivity(id: $0.id, at: $0.at, kind: $0.kind.rawValue, contextRefs: $0.contextRefs)
                }
            )
        },
        availableSourceIds: value.availableSourceIds,
        actionsAvailable: false
    )
}

private func sameRaw<Source: RawRepresentable, Target: RawRepresentable>(_ value: Source) -> Target
where Source.RawValue == String, Target.RawValue == String {
    guard let mapped = Target(rawValue: value.rawValue) else {
        preconditionFailure("Missing \(Target.self) case for \(value.rawValue)")
    }
    return mapped
}
