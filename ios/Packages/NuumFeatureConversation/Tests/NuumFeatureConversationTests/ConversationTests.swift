import Foundation
import NuumContracts
import Testing
@testable import NuumFeatureConversation

@MainActor
struct ConversationTests {
    @Test func textDeltasAppendWithoutShowingFreeText() {
        var state = ConversationUiState()
        state.agent = makeAgent(status: .running)
        state.phase = .ready
        state = state.reduce(agentId: "ada", event: delta("Hel"))
        state = state.reduce(agentId: "ada", event: delta("lo"))
        #expect(state.streamedText == "Hello")
        #expect(messageTexts(state).isEmpty)
        let assistant = assistantBlocks(state)
        #expect(assistant.count == 1)
        #expect(activityLine(for: assistant[0]) == .thinking)
        #expect(state.activity == .thinking)
        #expect(state.showStop)
    }

    @Test func deltasForAnotherAgentAreIgnored() {
        let state = ConversationUiState().reduce(
            agentId: "ada",
            event: HostEvent.agentMessageDelta(AgentMessageDeltaEvent(
                agentId: "other", runId: "run", messageId: "m1", delta: "Nope", part: .text
            ))
        )
        #expect(state.visibleBlocks().isEmpty)
        #expect(state.streamedText.isEmpty)
    }

    @Test func thinkingDeltasAppendOntoTheActivity() {
        var state = ConversationUiState()
        state = state.reduce(agentId: "ada", event: delta("hmm", part: .thinking))
        state = state.reduce(agentId: "ada", event: delta("?", part: .thinking))
        #expect(state.streamedThinking == "hmm?")
        #expect(state.streamedText.isEmpty)
        #expect(activityLine(for: assistantBlocks(state)[0]) == .thinking)
    }

    @Test func workScopedPendingIsNotDrawnOnTheOneToOneBar() {
        let pending = PendingTool(
            toolCallId: "t",
            name: "write",
            arguments: [:],
            action: .writeFile,
            target: "a.txt",
            workId: "work-1"
        )
        #expect(oneToOneApproval(pending) == nil)
        #expect(oneToOneApproval(PendingTool(
            toolCallId: "t", name: "write", arguments: [:], action: .writeFile, target: "a.txt", workId: nil
        ))?.toolCallId == "t")
        #expect(oneToOneApproval(PendingTool(
            toolCallId: "t", name: "write", arguments: [:], action: .writeFile, target: "a.txt", workId: ""
        ))?.toolCallId == "t")
    }

    @Test func contractPendingHasNoWorkIdSoTheBarStays() {
        var state = ConversationUiState()
        state = state.reduce(agentId: "ada", event: pending())
        #expect(state.pending?.workId == nil)
        #expect(oneToOneApproval(state.pending)?.toolCallId == "t1")
        #expect(state.activity == .waiting)
    }

    @Test func sixAttachmentsAreRejectedAndFiveAreKept() {
        let five = (0..<5).map { PickedFile(name: "f\($0).txt", mimeType: "text/plain", bytes: Data([1])) }
        let accepted = validateAttachments(current: [], incoming: five)
        guard case .accept(let files) = accepted else {
            Issue.record("expected five files")
            return
        }
        #expect(files.count == 5)
        let rejected = validateAttachments(
            current: files,
            incoming: [PickedFile(name: "f5.txt", mimeType: "text/plain", bytes: Data([1]))]
        )
        guard case .reject(let reason) = rejected else {
            Issue.record("expected the sixth file to be rejected")
            return
        }
        #expect(reason == .atMost5)
        #expect(files.count == 5)
    }

    @Test func attachmentLimitsPreferCountThenSizeThenTotal() {
        #expect(attachmentDecision(currentBytes: [], incomingBytes: Array(repeating: 1, count: 6)) == .reject(.atMost5))
        #expect(attachmentDecision(currentBytes: [], incomingBytes: [AttachmentLimits.maxBytes + 1]) == .reject(.tooLarge))
        #expect(attachmentDecision(
            currentBytes: [AttachmentLimits.maxTotalBytes - 10],
            incomingBytes: [11]
        ) == .reject(.totalTooLarge))
        #expect(attachmentDecision(currentBytes: [10], incomingBytes: []) == .accept)
        #expect(attachmentKilobytes(1) == 1)
        #expect(attachmentKilobytes(1024) == 1)
        #expect(attachmentKilobytes(1025) == 2)
    }

    @Test func moreThanFiveAttachmentsDoesNotCallSend() async {
        let agent = FakeAgent()
        let session = ConversationSession(agentId: "ada", ports: ConversationPorts(agent: agent, desktop: FakeDesktop()))
        session.update { state in
            state.agent = makeAgent()
            state.phase = .ready
            state.attachments = (0..<6).map {
                ComposerAttachment(name: "f\($0).txt", mimeType: "text/plain", bytes: Data([1]))
            }
        }
        await session.send()
        #expect(agent.sendCount == 0)
        #expect(session.state.attachmentLimitBlocked)
        #expect(session.state.attachmentError == .atMost5)
        #expect(session.state.draft.isEmpty)
    }

    @Test func pickingASixthFileDoesNotCallSend() async {
        let agent = FakeAgent()
        let desktop = FakeDesktop()
        desktop.files = [PickedFile(name: "more.txt", mimeType: "text/plain", bytes: Data([1]))]
        let session = ConversationSession(agentId: "ada", ports: ConversationPorts(agent: agent, desktop: desktop))
        session.update { state in
            state.agent = makeAgent()
            state.phase = .ready
            state.attachments = (0..<5).map {
                ComposerAttachment(name: "f\($0).txt", mimeType: "text/plain", bytes: Data([1]))
            }
            state.draft = "hello"
        }
        await session.pickAttachments()
        await session.send()
        #expect(agent.sendCount == 0)
        #expect(session.state.attachments.count == 5)
        #expect(session.state.draft == "hello")
    }

    @Test func consecutiveToolCallsGroupUntilAVisibleMessage() {
        func activity(_ id: String) -> ViewBlock {
            .assistant(AssistantBlock(
                id: id,
                thinking: "",
                tools: [ToolView(id: id, name: "shell", arguments: [:], output: nil, status: "ok")]
            ))
        }
        let blocks = [
            activity("a"),
            .assistant(AssistantBlock(id: "hidden", thinking: "", tools: [])),
            activity("b"),
            .message(MessageBlock(id: "reply", payload: .text(TextOutbound(content: "Done")))),
            activity("c"),
        ]
        let result = groupToolActivity(blocks)
        #expect(result.count == 3)
        guard case .assistant(let grouped) = result[0] else {
            Issue.record("expected a grouped activity")
            return
        }
        #expect(grouped.id == "a")
        #expect(grouped.tools.map(\.id) == ["a", "b"])
        #expect(blocks.count == 5)
    }

    @Test func approvalCallbacksAreDenyOnceAndAlways() async {
        let agent = FakeAgent()
        let session = session(agent)
        session.update { $0.pending = oneToOnePending(allowAlways: true) }
        await session.decide(.deny)
        #expect(agent.denials.map(\.0) == ["t1"])
        #expect(agent.denials.map(\.1) == [.deny])
        #expect(agent.approvals.isEmpty)
        #expect(session.state.pending == nil)

        session.update { $0.pending = oneToOnePending(allowAlways: true) }
        await session.decide(.once)
        #expect(agent.approvals.map(\.0) == ["t1"])
        #expect(agent.approvals.map(\.1) == [.once])

        session.update { $0.pending = oneToOnePending(allowAlways: true) }
        await session.decide(.always)
        #expect(agent.approvals.last?.1 == .always)

        let before = agent.approvals.count + agent.denials.count
        session.update { $0.pending = oneToOnePending(allowAlways: false) }
        await session.decide(.always)
        await session.decide(.never)
        #expect(agent.approvals.count + agent.denials.count == before)
        #expect(session.state.pending != nil)
    }

    @Test func deniedApprovalClearsTheBarAndAFailedToolUsesTheFailureKey() {
        var state = ConversationUiState()
        state = state.reduce(agentId: "ada", event: pending())
        #expect(oneToOneApproval(state.pending) != nil)
        state = state.reduce(agentId: "ada", event: HostEvent.agentToolCompleted(AgentToolCompletedEvent(
            agentId: "ada", runId: "run", toolCallId: "t1", toolName: "write", ok: false, output: "denied"
        )))
        #expect(state.pending == nil)
        let tool = assistantBlocks(state).flatMap(\.tools).first
        #expect(tool?.status == "error")
        #expect(toolStatusKey(tool?.status ?? "") == .failed)
        #expect(tool?.output == "denied")
    }

    @Test func widgetOptionBecomesOneAnswer() async {
        let agent = FakeAgent()
        let session = session(agent)
        await session.answerWidget(messageId: "card", value: "Ship it")
        await session.answerWidget(messageId: "card", value: "   ")
        #expect(agent.answers.count == 1)
        #expect(agent.answers[0].messageId == "card")
        #expect(agent.answers[0].value == "Ship it")
        #expect(agent.answers[0].id == "ada")
    }

    @Test func widgetFailureKeepsTheMessageAndDoesNotIncludeAKey() async {
        let secret = "sk-test-secret-value"
        let agent = FakeAgent()
        agent.answerError = NuumError(code: HostErrorCode.noAPIKey, message: "Missing API key for openai")
        let session = session(agent)
        await session.answerWidget(messageId: "card", value: "Yes")
        let banner = session.state.widgetErrors["card"]
        #expect(banner?.alert == true)
        let text = banner?.text(language: .en) ?? ""
        #expect(text == "Missing API key for openai")
        #expect(!text.contains(secret))
        #expect(!text.contains("2004"))
        #expect(session.state.widgetBusy == nil)
    }

    @Test func missingKeyKeepsTheDraftAndAttachments() async {
        let secret = "sk-test-secret-value"
        let agent = FakeAgent()
        agent.sendError = NuumError(code: HostErrorCode.noAPIKey, message: "Missing API key for openai")
        let session = session(agent)
        session.update { state in
            state.agent = makeAgent()
            state.draft = "hello \(secret)"
            state.attachments = [ComposerAttachment(name: "a.txt", mimeType: "text/plain", bytes: Data(secret.utf8))]
        }
        await session.send()
        #expect(agent.sendCount == 1)
        #expect(session.state.draft == "hello \(secret)")
        #expect(session.state.attachments.count == 1)
        #expect(session.state.sending == false)
        let notice = session.state.notice?.text(language: .en) ?? ""
        #expect(notice == "Missing API key for openai")
        #expect(!notice.contains(secret))
        #expect(!notice.contains("2004"))
        #expect(messageTexts(session.state).isEmpty)
    }

    @Test func successfulSendClearsDraftAndAttachments() async {
        let agent = FakeAgent()
        let session = session(agent)
        session.update { state in
            state.agent = makeAgent()
            state.draft = "hello"
            state.attachments = [ComposerAttachment(name: "a.txt", mimeType: "text/plain", bytes: Data([1]))]
        }
        await session.send()
        #expect(agent.sendCount == 1)
        #expect(agent.lastSend?.content == "hello")
        #expect(agent.lastSend?.attachments.count == 1)
        #expect(session.state.draft.isEmpty)
        #expect(session.state.attachments.isEmpty)
    }

    @Test func blankDraftDoesNotSend() async {
        let agent = FakeAgent()
        let session = session(agent)
        session.update { state in
            state.agent = makeAgent()
            state.draft = "   "
        }
        await session.send()
        #expect(agent.sendCount == 0)
    }

    @Test func emptySelectionShowsTheWordmarkAndDoesNotLoad() async {
        let agent = FakeAgent()
        let session = ConversationSession(agentId: nil, ports: ConversationPorts(agent: agent, desktop: FakeDesktop()))
        #expect(session.state.showsWordmark)
        #expect(!session.state.canPickAttachments)
        #expect(!session.state.sendEnabled)
        await session.run()
        #expect(agent.getCount == 0)
        #expect(session.state.showsWordmark)
        #expect(!session.state.showsTranscript)
    }

    @Test func loadingDoesNotShowTheWordmark() {
        let session = ConversationSession(agentId: "ada", ports: ConversationPorts(agent: FakeAgent(), desktop: FakeDesktop()))
        #expect(session.state.phase == .loading)
        #expect(!session.state.showsWordmark)
        #expect(!session.state.showsTranscript)
    }

    @Test func readyEmptyTranscriptShowsTheWordmark() {
        var state = ConversationUiState()
        state.phase = .ready
        state.agent = makeAgent()
        #expect(state.showsWordmark)
        #expect(!state.showsTranscript)
        state.events = [.user(UserTranscript(id: "u", seq: 1, createdAt: 1, text: "Hi"))]
        #expect(!state.showsWordmark)
        #expect(state.showsTranscript)
    }

    @Test func loadFailureKeepsTheCenterBlank() async {
        let agent = FakeAgent()
        agent.getError = NuumError(code: HostErrorCode.agentNotFound, message: "No such Nunu.")
        let session = session(agent)
        let task = Task { await session.run() }
        await waitUntil { session.state.phase == .ready }
        #expect(session.state.loadFailed)
        #expect(!session.state.showsWordmark)
        #expect(session.state.notice?.text(language: .en) == "No such Nunu.")
        task.cancel()
    }

    @Test func deltaDuringLoadIsAppended() async {
        let agent = FakeAgent()
        agent.snapshot = AgentSnapshot(view: makeAgent(), events: [], blocks: [], live: nil)
        agent.eventDuringGet = delta("Hel")
        let session = session(agent)
        let task = Task { await session.run() }
        await waitUntil { session.state.streamedText == "Hel" }
        #expect(session.state.phase == .ready)
        #expect(session.state.streamedText == "Hel")
        task.cancel()
    }

    @Test func cancelledNoticeIsNotAnError() {
        var state = ConversationUiState()
        state.agent = makeAgent(status: .running)
        state.notice = .raw("Missing API key for openai", alert: true)
        state = state.reduce(agentId: "ada", event: HostEvent.agentEnded(AgentEndedEvent(
            agentId: "ada", runId: "run", status: .cancelled
        )))
        #expect(state.notice == .localized(.stopped, alert: false))
        #expect(state.notice?.alert == false)
        #expect(state.agent?.runtime.status == .idle)
        #expect(state.agent?.runtime.activeRunId == nil)
        #expect(!state.showStop)
    }

    @Test func hostErrorFallsBackWhenTheMessageIsBlank() {
        let state = ConversationUiState().reduce(agentId: "ada", event: HostEvent.agentError(AgentErrorEvent(
            agentId: "ada", runId: "run", code: 1004, message: "  "
        )))
        #expect(state.notice == .localized(.hostError, alert: true))
        #expect(!state.notice!.text(language: .zhCN).contains("1004"))
    }

    @Test func workEventsDoNotShowADiscussionInterruption() {
        var state = ConversationUiState()
        state.agent = makeAgent()
        state.phase = .ready
        let next = state.reduce(agentId: "ada", event: .workUpdated(WorkProfile(
            id: "room", name: "Room", description: "", projectRoot: nil, createdAt: 1
        )))
        #expect(next == state)
        #expect(!next.showsDiscussionInterruption)
        #expect(NuumFeatureConversationModule.showsDiscussionInterruption == false)
        #expect(NuumFeatureConversationModule.drawsNunuBar == false)
        let rendered = next.notice?.text(language: .en) ?? ""
        #expect(!rendered.contains(ConversationCopy.discussionInterruptionKey))
    }

    @Test func imageSupportFollowsTheProtocolRules() {
        #expect(modelSupportsImageInput(providerRaw: "deepseek", model: "deepseek-chat") == false)
        #expect(modelSupportsImageInput(providerRaw: "openai", model: "custom-model") == false)
        #expect(modelSupportsImageInput(providerRaw: "openai", model: "o3-mini") == false)
        #expect(modelSupportsImageInput(providerRaw: "openai", model: "gpt-4o") == true)
        #expect(modelSupportsImageInput(providerRaw: "anthropic", model: "claude-sonnet-4-20250514") == true)
        var state = ConversationUiState()
        state.agent = makeAgent(provider: .deepseek, model: "deepseek-chat")
        state.attachments = [ComposerAttachment(name: "a.png", mimeType: "image/png", bytes: Data([1]))]
        #expect(state.showsImageWarning)
        state.agent = makeAgent(provider: .openai, model: "gpt-4o")
        #expect(!state.showsImageWarning)
    }

    @Test func profileRenameAndRoomNoticeUseCatalogKeys() {
        let renamed = NoticeBlock(id: "p", kind: "profile", text: "This agent changed name to \"Ada\".")
        #expect(localizedNotice(renamed, language: .en) == "This Nunu changed name to \"Ada\".")
        #expect(localizedNotice(renamed, language: .zhCN) == "此 Nunu 已更名为“Ada”。")
        let other = NoticeBlock(id: "p2", kind: "profile", text: "This agent changed its description.")
        #expect(localizedNotice(other, language: .en) == "This Nunu changed its profile.")
        let room = NoticeBlock(id: "w", kind: "wake", text: "Participated in room: Design")
        #expect(localizedNotice(room, language: .zhCN) == "参与群聊：Design")
    }

    @Test func timeSeparatorAppearsAfterFiveMinutes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = Int64(1_700_000_000_000)
        #expect(showTimeSeparator(previous: nil, current: first, calendar: calendar))
        #expect(!showTimeSeparator(previous: first, current: first + 4 * 60 * 1000, calendar: calendar))
        #expect(showTimeSeparator(previous: first, current: first + 5 * 60 * 1000, calendar: calendar))
        let stamp = transcriptStamp(millis: first, now: Date(timeIntervalSince1970: Double(first) / 1000), calendar: calendar, language: .en)
        #expect(stamp.hasPrefix("Today "))
    }

    @Test func markdownKeepsParagraphsListsCodeAndLinks() {
        let blocks = parseMarkdown("Hello\n\n- one\n- two\n\n```\nlet n = 1\n```\n\nSee [docs](https://example.com).")
        #expect(blocks.count == 4)
        if case .paragraph(let intro) = blocks[0] {
            #expect(intro == [.text("Hello")])
        } else {
            Issue.record("paragraph")
        }
        if case .bullets(let items) = blocks[1] {
            #expect(items.count == 2)
        } else {
            Issue.record("list")
        }
        if case .code(let code) = blocks[2] {
            #expect(code == "let n = 1")
        } else {
            Issue.record("code")
        }
        if case .paragraph(let linked) = blocks[3] {
            #expect(linked.contains(.link(text: "docs", url: "https://example.com")))
        } else {
            Issue.record("link")
        }
        #expect(isOpenableURL("https://example.com"))
        #expect(!isOpenableURL("javascript:alert(1)"))
    }

    @Test func toolLabelsAndUnimplementedOutputStayLiteral() {
        #expect(toolLabel("shell", language: .zhCN) == "终端")
        #expect(toolLabel("request_network", language: .en) == ConversationCopy.networkAccessKey)
        #expect(toolLabel("SendMessage", language: .en) == "Send Message")
        let block = assistantBlock(
            id: "a",
            parts: [.toolCall(ToolCallPart(id: "call", name: "shell", arguments: ["command": .string("ls")]))],
            results: ["call": ToolResult(content: UnimplementedToolMessage.iosClient, ok: false)],
            live: false
        )
        #expect(block.tools.first?.output == "This iOS client does not implement this tool.")
        #expect(block.tools.first?.status == "error")
        #expect(prettyJSONObject(["command": .string("ls")]) == "{\n  \"command\": \"ls\"\n}")
    }

    @Test func sendMessageIsNotAToolCardAndWidgetAnswersPointAtTheCard() {
        let events: [TranscriptEvent] = [
            .assistant(AssistantTranscript(id: "a", seq: 1, createdAt: 1, parts: [
                .toolCall(ToolCallPart(id: "send", name: "SendMessage", arguments: [:])),
            ])),
            .message(MessageTranscript(id: "card", seq: 2, createdAt: 2, payload: .widget(WidgetPayload(
                prompt: "Go?",
                options: [WidgetOption(label: "Yes", value: "yes")]
            )))),
            .user(UserTranscript(id: "u", seq: 3, createdAt: 3, text: "yes", widgetAnswerTo: "card")),
        ]
        let blocks = projectAgent(events)
        #expect(assistantBlocks(ConversationUiState(phase: .ready, events: events)).isEmpty)
        let answers = widgetAnswers(blocks)
        #expect(answers["card"] == "yes")
    }

    @Test func pickerCancelIsSilentAndReadFailureUsesTheKey() async {
        let desktop = FakeDesktop()
        desktop.files = []
        let session = session(FakeAgent(), desktop)
        session.update { state in
            state.agent = makeAgent()
            state.phase = .ready
        }
        await session.pickAttachments()
        #expect(session.state.attachmentError == nil)
        #expect(!session.state.readingAttachments)

        desktop.pickError = NuumError(code: DesktopErrorCode.folderPick, message: "no")
        await session.pickAttachments()
        #expect(session.state.attachmentError == .readFailed)
        #expect(session.state.notice == nil)
    }

    @Test func openingATranscriptAttachmentFallsBackToShare() async {
        let desktop = FakeDesktop()
        desktop.openError = NuumError(code: 3002, message: "The folder authorization expired.")
        let session = session(FakeAgent(), desktop)
        await session.openAttachment(path: "/tmp/note.txt")
        #expect(desktop.opened == ["/tmp/note.txt"])
        #expect(desktop.shared == ["/tmp/note.txt"])
        #expect(session.state.notice == nil)

        desktop.shareError = NuumError(code: 3002, message: "The folder authorization expired.")
        await session.openAttachment(path: "/tmp/other.txt")
        let notice = session.state.notice?.text(language: .en) ?? ""
        #expect(notice == "The folder authorization expired.")
        #expect(!notice.contains("sk-"))
    }

    @Test func sandHexKeepsAlphaInTheLastByte() {
        let parsed = parseSandHex("#14141499")
        #expect(parsed?.a == Double(0x99) / 255)
        #expect(parsed?.r == Double(0x14) / 255)
        let commands = NunuSilhouette.path(for: "circle")
        #expect(commands.contains(.close))
        #expect(resolveNunuAppearance(agentId: "ada", color: "blue", shape: "droplet", material: "glass").shape == "droplet")
    }

    @Test func copyUsesTheCatalogForBothLanguages() {
        #expect(ConversationCopy.text(.waiting, language: .zhCN) == "等待确认")
        #expect(ConversationCopy.text(.waiting, language: .en) == "Waiting for approval")
        #expect(ConversationCopy.text(.messageName, language: .zhCN, values: ["name": "Ada"]) == "给 Ada 发消息")
        #expect(ConversationCopy.text("Ask anything, or drop a file.", language: .en) == "Ask anything, or drop a file.")
    }
}

private func delta(_ text: String, part: MessagePart = .text) -> HostEvent {
    .agentMessageDelta(AgentMessageDeltaEvent(agentId: "ada", runId: "run", messageId: "m1", delta: text, part: part))
}

private func pending() -> HostEvent {
    .agentToolPending(AgentToolPendingEvent(
        agentId: "ada",
        runId: "run",
        toolCallId: "t1",
        toolName: "write",
        arguments: [:],
        action: .writeFile,
        target: "notes.txt"
    ))
}

@MainActor
private func session(_ agent: FakeAgent, _ desktop: FakeDesktop = FakeDesktop()) -> ConversationSession {
    ConversationSession(agentId: "ada", ports: ConversationPorts(agent: agent, desktop: desktop))
}

private func oneToOnePending(allowAlways: Bool) -> PendingTool {
    PendingTool(
        toolCallId: "t1",
        name: "write",
        arguments: [:],
        action: .writeFile,
        target: "notes.txt",
        allowAlways: allowAlways
    )
}

private func makeAgent(
    status: AgentStatus = .idle,
    provider: ProviderId = .openai,
    model: String = "gpt-4o"
) -> AgentView {
    AgentView(
        profile: AgentProfile(id: "ada", name: "Ada", description: "", createdAt: 1),
        settings: AgentSettings(model: ModelRef(provider: provider, model: model)),
        runtime: AgentRuntime(status: status, unread: false, lastActivityAt: 1)
    )
}

private func messageTexts(_ state: ConversationUiState) -> [String] {
    state.visibleBlocks().compactMap { block in
        guard case .message(let message) = block, case .text(let text) = message.payload else { return nil }
        return text.content
    }
}

private func assistantBlocks(_ state: ConversationUiState) -> [AssistantBlock] {
    state.visibleBlocks().compactMap { block in
        if case .assistant(let assistant) = block { return assistant }
        return nil
    }
}

@MainActor
private func waitUntil(_ predicate: @MainActor () -> Bool) async {
    for _ in 0..<50 {
        if predicate() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

final class FakeAgent: AgentPort, @unchecked Sendable {
    private let continuation: AsyncStream<HostEvent>.Continuation
    private let stream: AsyncStream<HostEvent>
    var snapshot = AgentSnapshot(
        view: AgentView(
            profile: AgentProfile(id: "ada", name: "Ada", description: "", createdAt: 1),
            settings: AgentSettings(model: ModelRef(provider: .openai, model: "gpt-4o")),
            runtime: AgentRuntime(status: .idle, unread: false, lastActivityAt: 1)
        ),
        events: [],
        blocks: [],
        live: nil
    )
    var peers: [AgentView] = []
    var sendCount = 0
    var lastSend: AgentSendParams?
    var sendError: Error?
    var answerError: Error?
    var getError: Error?
    var eventDuringGet: HostEvent?
    var approvals: [(String, ToolResolution)] = []
    var denials: [(String, ToolResolution)] = []
    var answers: [AgentAnswerWidgetParams] = []
    var cancelCount = 0
    var getCount = 0

    init() {
        var continuation: AsyncStream<HostEvent>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    var events: AsyncStream<HostEvent> { stream }

    func list() async throws -> [AgentView] { peers }
    func get(id: String) async throws -> AgentSnapshot {
        getCount += 1
        if let eventDuringGet { continuation.yield(eventDuringGet) }
        if let getError { throw getError }
        return snapshot
    }
    func create(_ params: AgentCreateParams) async throws -> AgentView { snapshot.view }
    func update(_ params: AgentUpdateParams) async throws -> AgentView { snapshot.view }
    func delete(id: String) async throws {}
    func transcript(_ query: TranscriptQuery) async throws -> TranscriptPage {
        TranscriptPage(id: query.id, entries: [])
    }
    func send(_ params: AgentSendParams) async throws -> SendResult {
        sendCount += 1
        lastSend = params
        if let sendError { throw sendError }
        return SendResult(runId: "run", queued: false)
    }
    func answerWidget(_ params: AgentAnswerWidgetParams) async throws -> SendResult {
        if let answerError { throw answerError }
        answers.append(params)
        return SendResult(runId: "run", queued: false)
    }
    func cancel(id: String) async throws { cancelCount += 1 }
    func approve(id: String, toolCallId: String, resolution: ToolResolution) async throws {
        approvals.append((toolCallId, resolution))
    }
    func deny(id: String, toolCallId: String, resolution: ToolResolution) async throws {
        denials.append((toolCallId, resolution))
    }
}

final class FakeDesktop: DesktopPort, @unchecked Sendable {
    var files: [PickedFile] = []
    var pickError: Error?
    var openError: Error?
    var shareError: Error?
    var opened: [String] = []
    var shared: [String] = []

    func pickDirectory() async throws -> String? { nil }
    func pickFiles() async throws -> [PickedFile] {
        if let pickError { throw pickError }
        return files
    }
    func openAttachment(path: String) async throws {
        opened.append(path)
        if let openError { throw openError }
    }
    func share(path: String) async throws {
        shared.append(path)
        if let shareError { throw shareError }
    }
}
