import Foundation
import Testing
@testable import NuumAgent
import NuumContracts
import NuumProtocol

@Test func missingKeyThrows2004WithoutEchoingAKey() async throws {
    let secrets = MemorySecrets(Secrets(openaiApiKey: "sk-secret-value"))
    let host = openRuntime(secrets: MemorySecrets())
    try await host.start()
    let agent = try await host.agentPort.create()
    do {
        _ = try await host.agentPort.send(AgentSendParams(id: agent.profile.id, content: "hello"))
        Issue.record("expected 2004")
    } catch let error as NuumError {
        #expect(error.code == NuumContracts.HostErrorCode.noAPIKey)
        #expect(!error.message.contains("sk-secret-value"))
    }
    secrets.current = Secrets(deepseekApiKey: "sk-secret-value")
    let kernel = FakeKernel()
    let live = openRuntime(kernel: kernel, secrets: secrets)
    try await live.start()
    let created = try await live.agentPort.create()
    let sent = Task { try await live.agentPort.send(AgentSendParams(id: created.profile.id, content: "hello")) }
    await waitUntil { !kernel.startedSnapshot().isEmpty || sent.isCancelled }
    await waitUntil { !kernel.startedSnapshot().isEmpty }
    #expect(kernel.startedSnapshot().first?.secrets.deepseekApiKey == "sk-secret-value")
    kernel.emit(ended(kernel.startedSnapshot()[0].runId))
    _ = try await sent.value
    let text = try await live.store.readText(NuumPaths.transcriptPath(created.profile.id)) ?? ""
    #expect(!text.contains("sk-secret-value"))
}

@Test func sameAgentDoesNotOverlapAndRestartIsNotRunning() async throws {
    let kernel = FakeKernel()
    let hold = AsyncGate<Void>()
    kernel.hold = hold
    let store = MemoryAgentStore()
    let host = openRuntime(store: store, kernel: kernel)
    try await host.start()
    let agent = try await host.agentPort.create()
    let first = Task { try await host.agentPort.send(AgentSendParams(id: agent.profile.id, content: "go")) }
    await waitUntil { !kernel.startedSnapshot().isEmpty }
    let running = try await host.agentPort.get(id: agent.profile.id)
    #expect(running.view.runtime.status == .running)
    do {
        _ = try await host.agentPort.send(AgentSendParams(id: agent.profile.id, content: "again"))
        Issue.record("expected busy")
    } catch let error as NuumError {
        #expect(error.code == NuumContracts.HostErrorCode.agentBusy)
    }
    let restarted = openRuntime(store: store, kernel: FakeKernel(), secrets: MemorySecrets(Secrets(deepseekApiKey: "sk-test")))
    try await restarted.start()
    let idle = try await restarted.agentPort.get(id: agent.profile.id)
    #expect(idle.view.runtime.status == .idle)
    let page = try await restarted.agentPort.transcript(TranscriptQuery(id: agent.profile.id))
    #expect(!page.entries.isEmpty)
    hold.complete(())
    kernel.emit(ended(kernel.startedSnapshot()[0].runId))
    _ = try await first.value
}

@Test func compactionTriggersAtThreeQuartersThroughTheKernel() async throws {
    let kernel = FakeKernel()
    let store = MemoryAgentStore()
    let host = openRuntime(store: store, kernel: kernel, contextWindowTokens: 20_000)
    try await host.start()
    let agent = try await host.agentPort.create()
    let bulky = NuumProtocol.TranscriptEvent.assistant(
        id: "old",
        seq: 1,
        createdAt: 1,
        parts: [.text(text: String(repeating: "x", count: 80_000))]
    )
    try await store.appendLine(NuumPaths.transcriptPath(agent.profile.id), line: ProtocolJSON.encode(bulky))
    let sent = Task { try await host.agentPort.send(AgentSendParams(id: agent.profile.id, content: "hi")) }
    await waitUntil { !kernel.startedSnapshot().isEmpty }
    #expect(!kernel.summarizedSnapshot().isEmpty)
    #expect(kernel.summarizedSnapshot().allSatisfy { $0.systemPrompt.contains("quoted transcript evidence") })
    let text = try await store.readText(NuumPaths.transcriptPath(agent.profile.id)) ?? ""
    #expect(text.contains("\"type\":\"compact\""))
    kernel.emit(ended(kernel.startedSnapshot()[0].runId))
    _ = try await sent.value
}

@Test func contextRequestIsAnsweredWithoutReplacingMessages() async throws {
    let kernel = FakeKernel()
    let host = openRuntime(kernel: kernel)
    try await host.start()
    let agent = try await host.agentPort.create()
    let sent = Task { try await host.agentPort.send(AgentSendParams(id: agent.profile.id, content: "hi")) }
    await waitUntil { !kernel.startedSnapshot().isEmpty }
    let runId = kernel.startedSnapshot()[0].runId
    #expect(kernel.startedSnapshot()[0].contextWindow == defaultContextWindow)
    kernel.emit(.context(KernelContextEvent(runId: runId, requestId: "ctx-1", usedTokens: 10)))
    await waitUntil { !kernel.contextsSnapshot().isEmpty }
    let answer = kernel.contextsSnapshot()[0]
    #expect(answer.runId == runId)
    #expect(answer.requestId == "ctx-1")
    #expect(answer.messages == nil)
    kernel.emit(ended(runId))
    _ = try await sent.value
}

@Test func createAgentStopsAtMaxAgents() async throws {
    let host = openRuntime()
    try await host.start()
    for _ in 0..<maxAgents {
        _ = try await host.agentPort.create()
    }
    do {
        _ = try await host.agentPort.create()
        Issue.record("expected cap")
    } catch let error as NuumError {
        #expect(error.code == NuumContracts.KernelErrorCode.invalid)
        #expect(error.message.contains(String(maxAgents)))
    }
    let owner = try await host.agentPort.list().first
    let ownerId = try #require(owner).profile.id
    let refused = try await host.executeDelegated(
        ownerId,
        "CreateAgent",
        .object([("name", .string("extra")), ("description", .string("no"))]),
        .direct,
        "call-1"
    )
    #expect(refused.output.contains("already \(maxAgents)"))
    #expect(try await host.agentPort.list().count == maxAgents)
}

@Test func promptStatesIOSAndDropsTheMacShellSentence() async throws {
    let kernel = FakeKernel()
    let host = openRuntime(kernel: kernel, osLabel: "iOS 26.2")
    try await host.start()
    let agent = try await host.agentPort.create()
    let sent = Task { try await host.agentPort.send(AgentSendParams(id: agent.profile.id, content: "hi")) }
    await waitUntil { !kernel.startedSnapshot().isEmpty }
    let system = kernel.startedSnapshot()[0].messages.first { $0.role == .system }?.content ?? ""
    #expect(system.contains(IOSEnvironmentPrompt.sentence))
    #expect(system.contains("cannot run a shell"))
    #expect(system.contains("iOS 26.2"))
    #expect(system.contains("## Autonomy"))
    #expect(system.contains("Never fabricate data"))
    #expect(system.contains("SendMessage is your only voice"))
    #expect(!system.contains("own Mac"))
    #expect(!system.contains("real shell"))
    kernel.emit(ended(kernel.startedSnapshot()[0].runId))
    _ = try await sent.value
}

@Test func proactiveActionsStayUnavailableAndCheckWaitsForContext() async throws {
    let host = openRuntime()
    try await host.start()
    let snapshot = try await host.proactivePort.configure(ProactiveConfigureParams(expectedRevision: 0, enabled: true))
    #expect(snapshot.actionsAvailable == false)
    #expect(snapshot.availableSourceIds.isEmpty)
    let agentId = snapshot.defaultAgentId ?? snapshot.agents[0].agentId
    let checked = try await host.proactivePort.check(agentId: agentId)
    #expect(checked.actionsAvailable == false)
    #expect(checked.agents.count == 1)
    #expect(checked.agents[0].state == "waiting-context")
    #expect(checked.agents[0].activity.first?.kind == "waiting-context")
}

@Test func runWorkCliIsUnimplemented() async throws {
    let host = openRuntime()
    try await host.start()
    let work = try await host.workPort.create(WorkCreateParams(name: "Bar", kind: .work))
    let result = try await host.executeDelegated(
        "agent",
        "RunWorkCLI",
        .object([("capability_id", .string("echo"))]),
        .work(workId: work.id),
        "cli-1"
    )
    #expect(!result.ok)
    #expect(result.output.contains("no local executable"))
}

@Test func discussionFinishesAndTaskTransitionsFollowTheTable() async throws {
    let kernel = FakeKernel()
    let host = openRuntime(kernel: kernel)
    try await host.start()
    let agent = try await host.agentPort.create()
    let room = try await host.workPort.create(WorkCreateParams(name: "Room", kind: .room))
    try await host.workPort.attachMember(WorkMemberAttachParams(workId: room.id, agentId: agent.profile.id, expectedRevision: 0, role: .worker))
    _ = try await host.workPort.postMessage(WorkPostMessageParams(workId: room.id, body: "hello"))
    var finished = false
    for _ in 0..<40 {
        await Task.yield()
        let runs = kernel.startedSnapshot().map(\.runId)
        for runId in Set(runs) {
            kernel.emit(ended(runId))
        }
        let snapshot = try await host.workPort.get(id: room.id)
        finished = snapshot.events.contains { $0.type == "discussion.finished" }
        if finished && !snapshot.discussionRunning { break }
    }
    let roomSnapshot = try await host.workPort.get(id: room.id)
    #expect(roomSnapshot.events.contains { $0.type == "discussion.finished" })

    let bar = try await host.workPort.create(WorkCreateParams(name: "Bar", kind: .work))
    let created = try await host.executeDelegated(
        agent.profile.id,
        "CreateTask",
        .object([("title", .string("Write the note"))]),
        .work(workId: bar.id),
        "task-1"
    )
    #expect(created.ok)
    let taskId = try #require(try await host.workPort.get(id: bar.id).tasks.first).task.id
    do {
        _ = try await host.workPort.transitionTask(WorkTaskTransitionParams(workId: bar.id, taskId: taskId, to: .done, expectedRevision: 1))
        Issue.record("done is not a direct step")
    } catch let error as NuumError {
        #expect(error.code == NuumContracts.HostErrorCode.workConflict)
    }
    _ = try await host.workPort.transitionTask(WorkTaskTransitionParams(workId: bar.id, taskId: taskId, to: .inProgress, expectedRevision: 1))
    do {
        _ = try await host.workPort.transitionTask(WorkTaskTransitionParams(workId: bar.id, taskId: taskId, to: .blocked, expectedRevision: 2))
        Issue.record("blocked needs a reason")
    } catch let error as NuumError {
        #expect(error.code == NuumContracts.KernelErrorCode.invalid)
    }
    let blocked = try await host.workPort.transitionTask(WorkTaskTransitionParams(
        workId: bar.id,
        taskId: taskId,
        to: .blocked,
        expectedRevision: 2,
        blocker: WorkBlocker(reason: "waiting on the user")
    ))
    #expect(blocked.task.state == .blocked)
    #expect(blocked.allowedTransitions.contains(.inProgress))
}

@Test func executionReceiptIsClaimedOnce() async throws {
    let store = MemoryAgentStore()
    let agentId = "agent-1"
    try await store.writeTextAtomic(NuumPaths.profilePath(agentId), text: #"{"id":"agent-1","name":"Ada","description":"","createdAt":1}"#)
    try await store.writeTextAtomic(
        NuumPaths.agentSettingsPath(agentId),
        text: #"{"model":{"provider":"deepseek","model":"deepseek-chat"}}"#
    )
    let call = NuumProtocol.TranscriptEvent.assistant(
        id: "asst",
        seq: 1,
        createdAt: 1,
        parts: [.toolCall(id: "call", executionId: "run-1:call", name: "write", arguments: .object([]))]
    )
    try await store.appendLine(NuumPaths.transcriptPath(agentId), line: ProtocolJSON.encode(call))
    try await store.writeTextAtomic(
        "\(NuumPaths.agentDir(agentId))/execution-receipts.json",
        text: #"[{"requestId":"run-1:call","runId":"run-1","name":"write","arguments":{},"ok":true,"output":"wrote it"}]"#
    )
    let host = openRuntime(store: store)
    try await host.start()
    let page = try await host.agentPort.transcript(TranscriptQuery(id: agentId))
    let claimed = page.entries.filter { event in
        if case .tool(let tool) = event { return tool.content == "wrote it" }
        return false
    }
    #expect(claimed.count == 1)
    let again = openRuntime(store: store)
    try await again.start()
    let second = try await again.agentPort.transcript(TranscriptQuery(id: agentId))
    let tools = second.entries.filter { event in
        if case .tool = event { return true }
        return false
    }
    #expect(tools.count == 1)
}

@Test func agentSourcesDoNotTouchModelSecurityStorageOrAShell() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/NuumAgent")
    let forbidden = [
        "NuumModel", "NuumSecurity", "NuumStorage", "NuumKernel", "URLSession", "UIKit", "SwiftUI",
        "Process", "Datadog", "Sentry", "Firebase",
    ]
    var hits: [String] = []
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    for file in files where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        for token in forbidden where text.contains(token) {
            hits.append("\(file.lastPathComponent):\(token)")
        }
    }
    #expect(hits.isEmpty)
    let manifest = try String(contentsOf: root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Package.swift"), encoding: .utf8)
    #expect(!manifest.contains("NuumModel"))
    #expect(!manifest.contains("NuumSecurity"))
    #expect(!manifest.contains("NuumStorage"))
    #expect(!manifest.contains("NuumKernel"))
}

@Test func knowledgeCatalogStaysReadOnly() async throws {
    let host = openRuntime()
    try await host.start()
    let work = try await host.workPort.create(WorkCreateParams(name: "Bar", kind: .work))
    do {
        _ = try await host.workPort.addCatalog(WorkCatalogAddParams(
            workId: work.id,
            expectedRevision: 0,
            entry: .knowledge(KnowledgeCatalogInput(name: "notes", description: "docs", roots: ["/docs"], readOnly: false))
        ))
        Issue.record("knowledge must stay read only")
    } catch let error as NuumError {
        #expect(error.code == NuumContracts.KernelErrorCode.invalid)
    }
}
