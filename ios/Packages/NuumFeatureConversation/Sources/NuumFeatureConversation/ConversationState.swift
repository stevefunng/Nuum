import Foundation
import NuumContracts

struct ConversationUiState: Equatable, Sendable {
    var phase: Phase = .loading
    var loadFailed = false
    var agent: AgentView?
    var peers: [AgentView] = []
    var events: [TranscriptEvent] = []
    var fallbackBlocks: [ViewBlock] = []
    var live: LiveAssistant?
    var streaming = false
    var draft = ""
    var attachments: [ComposerAttachment] = []
    var readingAttachments = false
    var attachmentError: CopyKey?
    var attachmentLimitBlocked = false
    var notice: Banner?
    var pending: PendingTool?
    var deciding = false
    var approvalError: Banner?
    var openPeerId: String?
    var sending = false
    var toolResults: [String: ToolResult] = [:]
    var widgetErrors: [String: Banner] = [:]
    var widgetBusy: String?

    var showStop: Bool {
        streaming || agent?.runtime.status == .running || oneToOneApproval(pending) != nil
    }

    var showsRunningRow: Bool {
        agent?.runtime.status == .running || oneToOneApproval(pending) != nil
    }

    var canPickAttachments: Bool {
        agent != nil && !sending && !readingAttachments && !showStop
    }

    var canEditDraft: Bool {
        agent != nil && !sending
    }

    var canRemoveAttachment: Bool {
        !sending && !readingAttachments && !showStop
    }

    var sendEnabled: Bool {
        if showStop { return true }
        guard canPickAttachments else { return false }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    var showsImageWarning: Bool {
        guard let model = agent?.settings.model else { return false }
        guard attachments.contains(where: { isImageMime($0.mimeType) }) else { return false }
        return !modelSupportsImageInput(providerRaw: model.provider.rawValue, model: model.model)
    }

    var showsWordmark: Bool {
        guard phase == .ready, !loadFailed else { return false }
        if agent == nil { return true }
        return visibleBlocks().isEmpty
    }

    var showsTranscript: Bool {
        phase == .ready && agent != nil && !visibleBlocks().isEmpty
    }

    var showsDiscussionInterruption: Bool { false }

    var streamedText: String {
        guard let live else { return "" }
        return live.parts.compactMap { part in
            if case .text(let text) = part { return text.text }
            return nil
        }.joined()
    }

    var streamedThinking: String {
        guard let live else { return "" }
        return live.parts.compactMap { part in
            if case .thinking(let text) = part { return text.text }
            return nil
        }.joined()
    }

    func visibleBlocks() -> [ViewBlock] {
        let projected: [ViewBlock]
        if !events.isEmpty || live != nil {
            projected = projectAgent(events, live: live, extraResults: toolResults)
        } else {
            projected = fallbackBlocks
        }
        return groupToolActivity(projected)
    }

    var activity: NunuActivity {
        nunuActivityState(
            status: agent?.runtime.status,
            awaitingApproval: oneToOneApproval(pending) != nil,
            executingTool: hasExecutingTool(visibleBlocks())
        )
    }

    var topBarCaption: CopyKey? {
        guard agent?.runtime.status == .running else { return nil }
        return caption(for: activity)
    }

    var runningCaption: CopyKey? {
        guard showsRunningRow else { return nil }
        return caption(for: activity)
    }

    private func caption(for activity: NunuActivity) -> CopyKey {
        switch activity {
        case .waiting: .waiting
        case .thinking: .thinking
        default: .working
        }
    }

    func withSnapshot(_ snapshot: AgentSnapshot, peers: [AgentView]) -> ConversationUiState {
        var copy = self
        copy.phase = .ready
        copy.loadFailed = false
        copy.agent = snapshot.view
        copy.peers = peers.isEmpty ? [snapshot.view] : peers
        copy.events = snapshot.events
        copy.fallbackBlocks = snapshot.events.isEmpty ? snapshot.blocks : []
        copy.live = snapshot.live
        let hostRunning = snapshot.view.runtime.status == .running
        copy.streaming = hostRunning || snapshot.live != nil
        return copy
    }

    func reduce(agentId: String, event: HostEvent) -> ConversationUiState {
        switch event {
        case .agentUpdated(let agent):
            return reduceUpdated(agentId, agent)
        case .agentMessageDelta(let delta):
            return reduceDelta(agentId, delta)
        case .agentMessageCompleted(let completed):
            return reduceCompleted(agentId, completed)
        case .agentToolPending(let pending):
            return reducePending(agentId, pending)
        case .agentToolStarted(let started):
            return reduceToolStarted(agentId, started)
        case .agentToolCompleted(let completed):
            return reduceToolCompleted(agentId, completed)
        case .agentError(let error):
            return reduceError(agentId, error)
        case .agentEnded(let ended):
            return reduceEnded(agentId, ended)
        case .workUpdated, .workEventAppended, .workCatalogUpdated, .proactiveUpdated, .settingsUpdated:
            return self
        }
    }

    private func reduceUpdated(_ agentId: String, _ agent: AgentView) -> ConversationUiState {
        var copy = self
        if copy.peers.contains(where: { $0.profile.id == agent.profile.id }) {
            copy.peers = copy.peers.map { $0.profile.id == agent.profile.id ? agent : $0 }
        }
        guard agent.profile.id == agentId else { return copy }
        if !copy.peers.contains(where: { $0.profile.id == agent.profile.id }) {
            copy.peers.append(agent)
        }
        copy.agent = agent
        copy.streaming = agent.runtime.status == .running || copy.live != nil
        return copy
    }

    private func reduceDelta(_ agentId: String, _ event: AgentMessageDeltaEvent) -> ConversationUiState {
        guard event.agentId == agentId else { return self }
        var copy = self
        copy.streaming = true
        let base = copy.live?.messageId == event.messageId ? copy.live?.parts ?? [] : []
        copy.live = LiveAssistant(
            messageId: event.messageId,
            parts: appendAssistantDelta(base, kind: event.part, delta: event.delta)
        )
        return copy
    }

    private func reduceCompleted(_ agentId: String, _ event: AgentMessageCompletedEvent) -> ConversationUiState {
        guard event.agentId == agentId else { return self }
        var copy = self
        copy.events = mergeEvents(copy.events, event.event)
        copy.fallbackBlocks = []
        if case .assistant(let assistant) = event.event, copy.live?.messageId == assistant.id {
            copy.live = nil
        }
        return copy
    }

    private func reducePending(_ agentId: String, _ event: AgentToolPendingEvent) -> ConversationUiState {
        guard event.agentId == agentId else { return self }
        var copy = self
        copy.pending = pendingTool(from: event)
        copy.streaming = true
        copy.approvalError = nil
        copy.deciding = false
        return copy
    }

    private func reduceToolStarted(_ agentId: String, _ event: AgentToolStartedEvent) -> ConversationUiState {
        guard event.agentId == agentId else { return self }
        var copy = self
        copy.streaming = true
        copy.live = ensureToolCall(copy.live, toolCallId: event.toolCallId, name: event.toolName, arguments: event.arguments)
        return copy
    }

    private func reduceToolCompleted(_ agentId: String, _ event: AgentToolCompletedEvent) -> ConversationUiState {
        guard event.agentId == agentId else { return self }
        var copy = self
        copy.toolResults[event.toolCallId] = ToolResult(content: event.output, ok: event.ok)
        if copy.pending?.toolCallId == event.toolCallId {
            copy.pending = nil
            copy.deciding = false
        }
        copy.live = ensureToolCall(copy.live, toolCallId: event.toolCallId, name: event.toolName, arguments: [:])
        return copy
    }

    private func reduceError(_ agentId: String, _ event: AgentErrorEvent) -> ConversationUiState {
        guard event.agentId == agentId else { return self }
        var copy = self
        copy.streaming = false
        copy.live = nil
        copy.pending = nil
        copy.deciding = false
        let trimmed = event.message.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.notice = trimmed.isEmpty ? .localized(.hostError, alert: true) : .raw(trimmed, alert: true)
        return copy
    }

    private func reduceEnded(_ agentId: String, _ event: AgentEndedEvent) -> ConversationUiState {
        guard event.agentId == agentId else { return self }
        var copy = self
        let stopped = event.status == .cancelled
        if stopped {
            copy.notice = .localized(.stopped, alert: false)
        } else if case .localized(.stopped, _) = copy.notice {
            copy.notice = nil
        }
        copy.streaming = false
        copy.live = nil
        copy.pending = nil
        copy.deciding = false
        if var agent = copy.agent {
            agent.runtime.status = event.status == .error ? .error : .idle
            agent.runtime.activeRunId = nil
            copy.agent = agent
        }
        return copy
    }
}

enum SendIntent: Equatable, Sendable {
    case skip
    case blocked
    case send
}

func sendIntent(_ state: ConversationUiState) -> SendIntent {
    if state.attachmentLimitBlocked || state.attachments.count > AttachmentLimits.maxCount {
        return .blocked
    }
    if state.agent == nil || state.sending || state.readingAttachments || state.showStop { return .skip }
    if state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.attachments.isEmpty {
        return .skip
    }
    return .send
}
