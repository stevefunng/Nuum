import Foundation
import NuumContracts
import Testing
@testable import NuumFeatureWork

@Test func displayTitleStripsWorkPrefixOnly() {
    #expect(workDisplayTitle("NunuBar · Design review") == "Design review")
    #expect(workDisplayTitle("Work Bar · Design review") == "Design review")
    #expect(workDisplayTitle("WorkBar: Design review") == "Design review")
    #expect(workDisplayTitle("Build the NunuBar") == "Build the NunuBar")
    #expect(workDisplayTitle("NunuBar") == "NunuBar")
}

@Test func blockedTransitionCarriesExistingReason() {
    let task = makeTask(state: .blocked, blocker: WorkBlocker(reason: "Waiting for assets"))
    #expect(blockerForTransition(task: task, to: .inProgress)?.reason == "Waiting for assets")
    #expect(blockerForTransition(task: task, to: .cancelled)?.reason == "Waiting for assets")
    var review = task
    review.state = .review
    review.blocker = nil
    #expect(blockerForTransition(task: review, to: .done) == nil)
}

@Test func catalogInputIsOnlyTheFourProtocolKinds() {
    let skill = catalogInput(kind: .skill, name: " Review ", path: " /skill/SKILL.md ", commands: "")
    guard case .input(.skill(let entry)) = skill else { Issue.record("skill"); return }
    #expect(entry.manifestPath == "/skill/SKILL.md")
    #expect(entry.description == "")

    let cli = catalogInput(kind: .cli, name: "Git", path: "/usr/bin/git", commands: "status, diff log")
    guard case .input(.cli(let cliEntry)) = cli else { Issue.record("cli"); return }
    #expect(cliEntry.allowedSubcommands == ["status", "diff", "log"])
    #expect(cliEntry.description == "")

    let knowledge = catalogInput(kind: .knowledge, name: "Docs", path: "/docs", commands: "")
    guard case .input(.knowledge(let knowledgeEntry)) = knowledge else { Issue.record("knowledge"); return }
    #expect(knowledgeEntry.roots == ["/docs"])
    #expect(knowledgeEntry.readOnly)
    #expect(knowledgeEntry.description == "")

    let tools = catalogInput(kind: .localTool, name: "Files", path: "read, write", commands: "")
    guard case .input(.localTool(let toolEntry)) = tools else { Issue.record("tools"); return }
    #expect(toolEntry.toolNames == ["read", "write"])
    #expect(toolEntry.description == "")

    #expect(catalogInput(kind: .localTool, name: "Files", path: " , ", commands: "") == .missingToolName)
    #expect(catalogInput(kind: .skill, name: " ", path: "/skill", commands: "") == .incomplete)
    #expect(CatalogKind.allCases.count == 4)
    #expect(skillManifestPath("/skills/review/") == "/skills/review/SKILL.md")
    let picked = applyPickedDirectory(kind: .skill, directory: "/skills/review", name: "")
    #expect(picked.name == "review")
    #expect(picked.path == "/skills/review/SKILL.md")
}

@Test func historyWindowUsesTheFirstKeptSequence() {
    let chat = [chatEvent(3), chatEvent(4), chatEvent(8)]
    #expect(inputAfterSeq(chat: chat, recentCount: 2) == 3)
    #expect(inputAfterSeq(chat: [], recentCount: 4) == 0)
    #expect(clampedHistoryCount(0, chatCount: 5) == 1)
    #expect(clampedHistoryCount(9, chatCount: 5) == 5)
}

@Test func runningWithoutAnActiveRunIsElsewhereAndInProgressAloneIsIdle() {
    let running = makeAgent(status: .running, activeRunId: nil)
    let snapshot = makeSnapshot(kind: .work)
    #expect(memberActivity(running, snapshot: snapshot) == .elsewhere)
    #expect(memberActivity(makeAgent(status: .idle), snapshot: snapshot) == .idle)
    let card = makeTask(state: .inProgress)
    let withCard = makeSnapshot(kind: .work, tasks: [WorkTaskView(task: card, allowedTransitions: [])])
    #expect(memberActivity(makeAgent(status: .idle), snapshot: withCard) == .idle)
    #expect(avatarState(agent: makeAgent(status: .idle), pendingApproval: false) == .idle)
    #expect(avatarState(agent: running, pendingApproval: true) == .waiting)
}

@Test func roomChatStaysOpenAndBoardChatOpensOnFocus() {
    var room = WorkChatDockState(roomForcesOpen: true)
    room.close()
    #expect(room.isOpen)
    var board = WorkChatDockState(roomForcesOpen: false)
    #expect(!board.isOpen)
    board.focusInput()
    #expect(board.isOpen)
    board.close()
    #expect(!board.isOpen)
}

@Test func discoverCardsAreNotInteractiveAndCreationHasNoGoal() {
    let cards = discoverCards(language: .en)
    #expect(cards.count == 2)
    #expect(cards.allSatisfy { !$0.interactive })
    #expect(cards.map(\.title) == ["Skills", "CLI tools"])
    var form = WorkCreationForm()
    #expect(form.kind == .work)
    #expect(!form.canSubmit)
    #expect(!form.includesGoal)
    form.name = "  Launch  "
    #expect(form.canSubmit)
    #expect(form.trimmedName == "Launch")
}

@Test func detailActionsDoNotIncludeAFreeStatePicker() {
    #expect(taskDetailActions(.blocked) == [.confirmResume, .cancelTask])
    #expect(taskDetailActions(.review) == [.requestChanges, .acceptDelivery])
    #expect(taskDetailActions(.ready) == [.dispatch])
    #expect(taskDetailActions(.inProgress) == [.dispatch])
    #expect(taskDetailActions(.proposed).isEmpty)
    #expect(taskDetailActions(.done).isEmpty)
    #expect(approvalResolutions == [.deny, .once, .always])
    #expect(!approvalResolutions.contains(.never))
}

@Test func noticesHideKeyMaterial() {
    let missing = NuumError(code: HostErrorCode.noAPIKey, message: "Missing API key for deepseek")
    let notice = workNotice(from: missing)
    #expect(notice.code == HostErrorCode.noAPIKey)
    #expect(notice.message == WorkCopy.roomResponseFailed)
    #expect(!WorkSecrets.shouldHide(WorkCopy.roomResponseFailed))
    #expect(WorkSecrets.shouldHide("sk-test-secret-value"))
    let shown = presentHostSentence("Missing API key for openai", language: .zhCN)
    #expect(shown == "有一轮房间回应失败，请检查模型设置后重新派工。")
    #expect(!shown.localizedCaseInsensitiveContains("api key"))
    let conflict = workNotice(from: NuumError(code: HostErrorCode.workConflict, message: "Card revision conflict"))
    #expect(conflict.message == "Card revision conflict")
}

@Test func surfacesCoverLoadingRoomBoardAndInterruptions() {
    var loading = WorkUiState()
    let loadingSurface = workSurface(state: loading, language: .en, fallbackTitle: "Launch")
    #expect(loadingSurface.phase == .loading)
    #expect(!loadingSurface.upgradeEnabled)
    #expect(loadingSurface.showsUpgrade)
    #expect(!loadingSurface.showsLanes)
    #expect(loadingSurface.laneCount == 0)
    #expect(forbiddenControls(loadingSurface.controlLabels) == 0)
    #expect(loadingSurface.title == "Launch")

    loading.loading = false
    loading.snapshot = makeSnapshot(kind: .room, discussionRunning: true)
    let room = workSurface(state: loading, language: .en)
    #expect(room.phase == .room)
    #expect(room.upgradeEnabled)
    #expect(room.showsStop)
    #expect(!room.showsLanes)
    #expect(room.title == "Launch")
    #expect(room.chatEmpty)
    #expect(room.memberEmpty)
    #expect(forbiddenControls(room.controlLabels) == 0)

    let blocked = makeTask(state: .blocked, blocker: WorkBlocker(reason: "Waiting for assets"))
    loading.snapshot = makeSnapshot(
        kind: .work,
        tasks: [WorkTaskView(task: blocked, allowedTransitions: [.inProgress, .cancelled])],
        interruptions: [
            WorkInterruption(eventId: "d1", error: "Discussion interrupted. Continue starts a new bounded discussion.", kind: "discussion"),
            WorkInterruption(eventId: "e1", error: "Execution failed. Check the result before continuing.", kind: "execution", taskId: "task-1"),
        ]
    )
    let board = workSurface(state: loading, language: .zhCN)
    #expect(board.phase == .board)
    #expect(board.showsLanes)
    #expect(board.laneCount == 7)
    #expect(board.blockedCount == 1)
    #expect(board.historyEditors == 1)
    #expect(board.continueButtons == 2)
    #expect(board.discoverInteractiveCount == 0)
    #expect(board.catalogKindCount == 4)
    #expect(forbiddenControls(board.controlLabels) == 0)
    #expect(!board.showsGoalField)
    #expect(board.approvalResolutions == [.deny, .once, .always])
}

@Test func inspectorPreferenceClampsAndRecovers() {
    let narrow = WorkInspectorLayout.project(preference: InspectorPreference(width: 10, split: 0.32), columnWidth: 1200)
    #expect(narrow == 184)
    let wide = WorkInspectorLayout.project(preference: InspectorPreference(width: 900, split: 2), columnWidth: 1200)
    #expect(wide == 380)
    let defaults = UserDefaults(suiteName: "nuum-work-test-\(UUID().uuidString)")!
    #expect(WorkInspectorLayout.read(defaults) == .standard)
    defaults.set(Data("nope".utf8), forKey: WorkInspectorLayout.storageKey)
    #expect(WorkInspectorLayout.read(defaults) == .standard)
    WorkInspectorLayout.write(InspectorPreference(width: 300, split: 0.4), defaults)
    #expect(WorkInspectorLayout.read(defaults).width == 300)
    #expect(WorkInspectorLayout.storageKey == "nuum.ui.workInspector.v1")
}

@Test func copyUsesMessageColumns() {
    #expect(WorkCopy.text("Create a Work", language: .en) == "Create a NunuBar")
    #expect(WorkCopy.text("Create a Work", language: .zhCN) == "创建 NunuBar")
    #expect(WorkCopy.text("Create Work", language: .en) == "Create NunuBar")
    #expect(WorkCopy.text("Enable task board", language: .zhCN) == "升级为 NunuBar")
    #expect(WorkCopy.text("Allow {action}?", language: .zhCN, ["action": "读取文件"]) == "允许读取文件？")
    #expect(NuumFeatureWorkModule.discussionBudgetOwnedByAgent)
    #expect(NuumFeatureWorkModule.protocolModule == "NuumProtocol")
}

@Test func roomUpgradeRequestsWorkKind() async {
    let work = FakeWorkPort(snapshot: makeSnapshot(kind: .room))
    let store = WorkStore(workId: "work-1", ports: WorkPorts(work: work, agent: FakeAgentPort(), desktop: FakeDesktopPort()))
    await store.reload()
    await store.upgrade()
    #expect(work.updates.count == 1)
    #expect(work.updates[0].id == "work-1")
    #expect(work.updates[0].kind == .work)
    let state = await store.state
    #expect(state.snapshot?.profile.kind == .work)
    #expect(forbiddenControls(workSurface(state: state, language: .en).controlLabels) == 0)
}

@Test func importSubmitsOnlyTheFourAllowedKinds() async throws {
    let work = FakeWorkPort(snapshot: makeSnapshot(kind: .work))
    let store = WorkStore(workId: "work-1", ports: WorkPorts(work: work, agent: FakeAgentPort(), desktop: FakeDesktopPort()))
    await store.reload()
    let builds: [CatalogBuild] = [
        catalogInput(kind: .skill, name: "Design review", path: "/skills/review/SKILL.md", commands: ""),
        catalogInput(kind: .cli, name: "Git", path: "/usr/bin/git", commands: "status, diff log"),
        catalogInput(kind: .knowledge, name: "Docs", path: "/knowledge", commands: ""),
        catalogInput(kind: .localTool, name: "Files", path: "read, write", commands: ""),
    ]
    for build in builds {
        guard case .input(let entry) = build else { Issue.record("input"); return }
        try await store.addCatalog(entry)
    }
    #expect(work.catalogAdds.count == 4)
    guard case .skill(let skill) = work.catalogAdds[0].entry else { Issue.record("skill"); return }
    #expect(skill.name == "Design review")
    #expect(skill.description == "")
    #expect(skill.manifestPath == "/skills/review/SKILL.md")
    guard case .cli(let cli) = work.catalogAdds[1].entry else { Issue.record("cli"); return }
    #expect(cli.executable == "/usr/bin/git")
    #expect(cli.allowedSubcommands == ["status", "diff", "log"])
    guard case .knowledge(let knowledge) = work.catalogAdds[2].entry else { Issue.record("knowledge"); return }
    #expect(knowledge.roots == ["/knowledge"])
    #expect(knowledge.readOnly)
    guard case .localTool(let tools) = work.catalogAdds[3].entry else { Issue.record("tools"); return }
    #expect(tools.toolNames == ["read", "write"])
    #expect(work.catalogAdds.allSatisfy { $0.expectedRevision >= 3 })
}

@Test func blockedTransitionCarriesReasonAndBlankPostDoesNotSend() async throws {
    let task = makeTask(state: .blocked, blocker: WorkBlocker(reason: "Waiting for assets"), revision: 4)
    let work = FakeWorkPort(snapshot: makeSnapshot(kind: .work, tasks: [WorkTaskView(task: task, allowedTransitions: [])]))
    let store = WorkStore(workId: "work-1", ports: WorkPorts(work: work, agent: FakeAgentPort(), desktop: FakeDesktopPort()))
    try await store.transition(task: task, to: .inProgress)
    #expect(work.transitions.count == 1)
    #expect(work.transitions[0].taskId == "task-1")
    #expect(work.transitions[0].to == .inProgress)
    #expect(work.transitions[0].expectedRevision == 4)
    #expect(work.transitions[0].blocker?.reason == "Waiting for assets")
    await store.post(body: "   ")
    #expect(work.posts.isEmpty)
    await store.post(body: "hello")
    #expect(work.posts.count == 1)
    #expect(work.posts[0].mentionedAgentIds.isEmpty)
    #expect(work.posts[0].body == "hello")
    let state = await store.state
    #expect(state.snapshot?.tasks.contains { $0.task.title == "hello" } == false)
}

@Test func backgroundDoesNotStartModelRequests() async {
    let work = FakeWorkPort(snapshot: makeSnapshot(kind: .work))
    let store = WorkStore(workId: "work-1", ports: WorkPorts(work: work, agent: FakeAgentPort(), desktop: FakeDesktopPort()))
    await store.setAcceptsModelRequests(false)
    await store.post(body: "hello")
    await store.continueDiscussion(eventId: "e1", inputAfterSeq: 2)
    try? await store.dispatch(agentId: "ada", taskId: "task-1", instruction: "go")
    #expect(work.posts.isEmpty)
    #expect(work.continues.isEmpty)
    #expect(work.dispatches.isEmpty)
    await store.stopDiscussion()
    #expect(work.stops == ["work-1"])
}

@Test func denyRemovesTheMemberBarAndNeverIsIgnored() async {
    let member = makeAgent()
    let work = FakeWorkPort(snapshot: makeSnapshot(kind: .work, members: [member]))
    let agent = FakeAgentPort()
    let store = WorkStore(workId: "work-1", ports: WorkPorts(work: work, agent: agent, desktop: FakeDesktopPort()))
    await store.reload()
    let pending = AgentToolPendingEvent(
        agentId: "ada",
        runId: "run",
        toolCallId: "call",
        toolName: "read",
        arguments: [:],
        action: .readFile,
        target: "/notes/spec.md",
        allowAlways: false
    )
    await store.apply(.agentToolPending(pending))
    var state = await store.state
    #expect(state.approvals.map(\.id) == ["ada:call"])
    #expect(state.approvals[0].allowAlways == false)
    await store.apply(.agentToolPending(AgentToolPendingEvent(
        agentId: "other", runId: "run", toolCallId: "x", toolName: "read", arguments: [:], action: .readFile, target: "/tmp"
    )))
    state = await store.state
    #expect(state.approvals.count == 1)
    await store.decide(approval: state.approvals[0], resolution: .never)
    #expect(agent.approvals.isEmpty)
    #expect(agent.denies.isEmpty)
    await store.decide(approval: state.approvals[0], resolution: .deny)
    state = await store.state
    #expect(state.approvals.isEmpty)
    #expect(agent.denies == ["call"])
    #expect(agent.approvals.isEmpty)
}

@Test func continueWithHistoryAndCreationKind() async throws {
    let work = FakeWorkPort(snapshot: makeSnapshot(kind: .room, chat: [chatEvent(3), chatEvent(4), chatEvent(8)]))
    let ports = WorkPorts(work: work, agent: FakeAgentPort(), desktop: FakeDesktopPort())
    let store = WorkStore(workId: "work-1", ports: ports)
    let chat = [chatEvent(3), chatEvent(4), chatEvent(8)]
    await store.continueDiscussion(eventId: "d1", inputAfterSeq: inputAfterSeq(chat: chat, recentCount: 2))
    #expect(work.continues.first?.inputAfterSeq == 3)
    let created = try await store.create(name: "  Launch  ", kind: .room)
    #expect(created?.name == "Launch")
    #expect(created?.kind == .room)
    #expect(work.creates.first?.kind == .room)
    let blank = try await store.create(name: "  ", kind: .work)
    #expect(blank == nil)
    #expect(work.creates.count == 1)
}

@Test func attachUsesTheMembershipRevision() async {
    let outsider = makeAgent(id: "bea", revision: 5, bound: false)
    let work = FakeWorkPort(snapshot: makeSnapshot(kind: .work))
    let agent = FakeAgentPort(agents: [outsider])
    let store = WorkStore(workId: "work-1", ports: WorkPorts(work: work, agent: agent, desktop: FakeDesktopPort()))
    await store.attach(agentId: "bea")
    #expect(work.attaches.count == 1)
    #expect(work.attaches[0].expectedRevision == 5)
    #expect(work.attaches[0].role == .worker)
    let already = makeAgent(id: "ada", bound: true)
    let busy = FakeAgentPort(agents: [already])
    let second = WorkStore(workId: "work-1", ports: WorkPorts(work: work, agent: busy, desktop: FakeDesktopPort()))
    await second.attach(agentId: "ada")
    #expect(work.attaches.count == 1)
}

@Test func directoryCancelDoesNotWarnAndImportFailureStaysANotice() async {
    let desktop = FakeDesktopPort()
    desktop.directory = nil
    let store = WorkStore(workId: "work-1", ports: WorkPorts(work: FakeWorkPort(snapshot: makeSnapshot(kind: .work)), agent: FakeAgentPort(), desktop: desktop))
    let pick = await store.pickDirectory()
    #expect(pick == .cancelled)
    var draft = CatalogDraft(page: .local, kind: .localTool, name: "Files", path: " , ")
    #expect(draft.build() == .missingToolName)
    draft.errorKey = WorkCopy.enterToolName
    #expect(WorkCopy.text(draft.errorKey ?? "", language: .en) == "Enter at least one tool name.")
}

private func forbiddenControls(_ labels: [String]) -> Int {
    let forbidden = ["New task", "Create task", "A new task", "新建任务", "创建任务"]
    return labels.filter { forbidden.contains($0) }.count
}

@Test func sourcesStayInsideTheFeatureBoundary() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/NuumFeatureWork")
    let forbidden = [
        "import NuumAgent",
        "import WidgetKit",
        "import Firebase",
        "Datadog",
        "Sentry",
        "secrets.bin",
        "New task",
        "Create task",
        "A new task",
        "新建任务",
        "创建任务",
        "What should this Work accomplish?",
    ]
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
    #expect(!files.isEmpty)
    for file in files {
        let source = try String(contentsOf: file, encoding: .utf8)
        for phrase in forbidden {
            #expect(!source.contains(phrase), "\(file.lastPathComponent) contains \(phrase)")
        }
    }
}
