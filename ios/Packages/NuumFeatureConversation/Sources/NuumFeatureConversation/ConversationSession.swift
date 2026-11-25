import Foundation
import NuumContracts

public struct ConversationPorts: Sendable {
    public var agent: any AgentPort
    public var desktop: any DesktopPort

    public init(agent: any AgentPort, desktop: any DesktopPort) {
        self.agent = agent
        self.desktop = desktop
    }
}

/// Drives one conversation from `AgentPort` and `DesktopPort`.
/// Call `run()` from the view task so events that arrive during the snapshot load are kept.
@MainActor
final class ConversationSession {
    let agentId: String?
    let ports: ConversationPorts
    private(set) var state: ConversationUiState
    var onChange: (@MainActor () -> Void)?
    private var started = false

    init(agentId: String?, ports: ConversationPorts) {
        self.agentId = agentId
        self.ports = ports
        var initial = ConversationUiState()
        if agentId == nil { initial.phase = .ready }
        self.state = initial
    }

    func run() async {
        if started { return }
        started = true
        guard let agentId else {
            update { $0.phase = .ready }
            return
        }
        let buffer = EventBuffer()
        let events = ports.agent.events
        let pump = Task { [weak self] in
            for await event in events {
                if Task.isCancelled { break }
                let immediate = await buffer.push(event)
                if let immediate {
                    self?.apply(immediate)
                }
            }
        }
        let loaded: Result<AgentSnapshot, Error>
        do {
            loaded = .success(try await ports.agent.get(id: agentId))
        } catch {
            loaded = .failure(error)
        }
        let peers = (try? await ports.agent.list()) ?? []
        let queued = await buffer.markReady()
        update { state in
            switch loaded {
            case .success(let snapshot):
                state = state.withSnapshot(snapshot, peers: peers)
            case .failure(let error):
                state.phase = .ready
                state.loadFailed = true
                state.notice = banner(from: error)
            }
        }
        for event in queued {
            apply(event)
        }
        await withTaskCancellationHandler {
            await pump.value
        } onCancel: {
            pump.cancel()
        }
    }

    func setDraft(_ value: String) {
        guard value != state.draft else { return }
        update { state in
            state.draft = value
            state.attachmentLimitBlocked = false
            if state.attachmentError == .atMost5 { state.attachmentError = nil }
        }
    }

    func send() async {
        guard let agentId else { return }
        switch sendIntent(state) {
        case .skip:
            return
        case .blocked:
            update { state in
                state.attachmentError = .atMost5
                state.attachmentLimitBlocked = true
            }
            return
        case .send:
            break
        }
        let draft = state.draft
        let attachments = state.attachments
        update { state in
            state.sending = true
            state.notice = nil
        }
        do {
            _ = try await ports.agent.send(AgentSendParams(
                id: agentId,
                content: draft,
                attachments: attachments.map {
                    AttachmentUpload(name: $0.name, mimeType: $0.mimeType, bytes: $0.bytes)
                }
            ))
            update { state in
                state.sending = false
                state.draft = ""
                state.attachments = []
                state.attachmentError = nil
                state.attachmentLimitBlocked = false
            }
        } catch {
            update { state in
                state.sending = false
                state.notice = banner(from: error)
            }
        }
    }

    func cancelRun() async {
        guard let agentId else { return }
        do {
            try await ports.agent.cancel(id: agentId)
        } catch {
            update { $0.notice = banner(from: error) }
        }
    }

    func pickAttachments() async {
        guard state.canPickAttachments else { return }
        update { $0.readingAttachments = true }
        do {
            let picked = try await ports.desktop.pickFiles()
            applyIncoming(picked)
        } catch {
            update { state in
                state.readingAttachments = false
                state.attachmentError = .readFailed
            }
        }
    }

    func ingestDropped(_ files: [PickedFile]) {
        guard state.canPickAttachments else { return }
        applyIncoming(files)
    }

    func noteAttachmentReadFailed() {
        update { state in
            state.readingAttachments = false
            state.attachmentError = .readFailed
        }
    }

    func removeAttachment(at index: Int) {
        guard state.canRemoveAttachment, state.attachments.indices.contains(index) else { return }
        update { state in
            state.attachments.remove(at: index)
            state.attachmentLimitBlocked = false
            if state.attachmentError == .atMost5 { state.attachmentError = nil }
        }
    }

    func decide(_ resolution: ToolResolution) async {
        if resolution == .never { return }
        guard let agentId, let pending = oneToOneApproval(state.pending) else { return }
        if state.deciding { return }
        if resolution == .always, !pending.alwaysEnabled { return }
        update { state in
            state.deciding = true
            state.approvalError = nil
        }
        do {
            if resolution == .deny {
                try await ports.agent.deny(id: agentId, toolCallId: pending.toolCallId, resolution: resolution)
            } else {
                try await ports.agent.approve(id: agentId, toolCallId: pending.toolCallId, resolution: resolution)
            }
            update { state in
                state.deciding = false
                state.approvalError = nil
                if state.pending?.toolCallId == pending.toolCallId {
                    state.pending = nil
                }
            }
        } catch {
            update { state in
                state.deciding = false
                state.approvalError = banner(from: error)
            }
        }
    }

    func answerWidget(messageId: String, value: String) async {
        guard let agentId else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || state.widgetBusy == messageId { return }
        update { state in
            state.widgetBusy = messageId
            state.widgetErrors[messageId] = nil
        }
        do {
            _ = try await ports.agent.answerWidget(AgentAnswerWidgetParams(
                id: agentId,
                messageId: messageId,
                value: trimmed
            ))
            update { state in
                if state.widgetBusy == messageId { state.widgetBusy = nil }
            }
        } catch {
            update { state in
                if state.widgetBusy == messageId { state.widgetBusy = nil }
                state.widgetErrors[messageId] = banner(from: error)
            }
        }
    }

    func openAttachment(path: String) async {
        do {
            try await ports.desktop.openAttachment(path: path)
        } catch let openError {
            do {
                try await ports.desktop.share(path: path)
            } catch {
                update { $0.notice = banner(from: openError) }
            }
        }
    }

    func openPeer(_ peerId: String) {
        update { $0.openPeerId = peerId }
    }

    func closePeer() {
        update { $0.openPeerId = nil }
    }

    func update(_ body: (inout ConversationUiState) -> Void) {
        body(&state)
        onChange?()
    }

    private func apply(_ event: HostEvent) {
        guard let agentId else { return }
        state = state.reduce(agentId: agentId, event: event)
        onChange?()
    }

    private func applyIncoming(_ picked: [PickedFile]) {
        update { state in
            state.readingAttachments = false
            guard !picked.isEmpty else { return }
            switch validateAttachments(current: state.attachments, incoming: picked) {
            case .accept(let files):
                state.attachments = files
                state.attachmentError = nil
                state.attachmentLimitBlocked = false
            case .reject(let reason):
                state.attachmentError = reason
                state.attachmentLimitBlocked = reason == .atMost5
            }
        }
    }
}

private actor EventBuffer {
    private var ready = false
    private var pending: [HostEvent] = []

    func push(_ event: HostEvent) -> HostEvent? {
        if ready { return event }
        pending.append(event)
        return nil
    }

    func markReady() -> [HostEvent] {
        ready = true
        let queued = pending
        pending.removeAll()
        return queued
    }
}
