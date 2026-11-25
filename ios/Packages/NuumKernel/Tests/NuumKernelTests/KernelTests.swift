import Foundation
import NuumContracts
import Testing

@testable import NuumKernel

// Package.swift has no test target. A later scaffold-owned change has to register
// NuumKernelTests before `swift test` in this package executes this file.

@Test func noToolsEndsIdleAndEveryEventCarriesRunId() async throws {
    try await exercise(scripted([[.thinking("hm"), .text("hi")]])) { harness in
        try await harness.start(startParams(runId: "run-xyz"))
        try await harness.awaitEnd()
        let events = harness.snapshot()
        #expect(!events.isEmpty)
        for event in events {
            #expect(runId(of: event) == "run-xyz")
        }
        #expect(try ended(events).status == .idle)
        #expect(errors(events).isEmpty)
        #expect(!events.contains { $0.name.hasPrefix("turn.tool") })
        let parts = deltas(events)
        #expect(parts.map(\.part) == [.thinking, .text])
        #expect(parts.map(\.delta) == ["hm", "hi"])
        #expect(try harness.requests().count == 1)
        #expect(try harness.requests()[0].apiKey == "k")
    }
}

@Test func delegatedToolWaitsAndFeedsTheNextRound() async throws {
    let tools = FakeTools()
    try await exercise(
        scripted([
            [.toolCall(id: "c1", name: "send_message", arguments: ["text": .string("hi")])],
            [.text("done")],
        ]),
        tools: tools
    ) { harness in
        try await harness.start(startParams(delegatedTools: [sendMessage]))
        try await harness.waitUntil("delegate") { delegates($0).isEmpty == false }
        let requests = try harness.requests()
        #expect(requests[0].tools.map(\.name) == ["send_message"])
        let delegate = try only(delegates(harness.snapshot()))
        #expect(delegate.runId == "run-1")
        #expect(delegate.toolCallId == "c1")
        #expect(delegate.toolName == "send_message")
        #expect(delegate.arguments == ["text": .string("hi")])
        #expect(started(harness.snapshot()).isEmpty)
        try await harness.kernel.provideToolResult(
            TurnToolResult(runId: "run-1", toolCallId: "c1", ok: true, output: "delivered")
        )
        try await harness.awaitEnd()
        let events = harness.snapshot()
        let completed = try only(completions(events))
        #expect(completed.runId == "run-1")
        #expect(completed.toolCallId == "c1")
        #expect(completed.toolName == "send_message")
        #expect(completed.ok)
        #expect(completed.output == "delivered")
        let second = try harness.requests()[1].messages
        #expect(second.last?.role == .tool)
        #expect(second.last?.content == "delivered")
        #expect(try ended(events).status == .idle)
        #expect(tools.executions.isEmpty)
    }
}

@Test func failedDelegationReachesTheModelInsteadOfFailingTheTurn() async throws {
    try await exercise(
        scripted([
            [.toolCall(id: "c1", name: "send_message", arguments: [:])],
            [.text("ok, noted")],
        ])
    ) { harness in
        try await harness.start(startParams(delegatedTools: [sendMessage]))
        try await harness.waitUntil("delegate") { delegates($0).isEmpty == false }
        try await harness.kernel.provideToolResult(
            TurnToolResult(runId: "run-1", toolCallId: "c1", ok: false, output: "target agent not found")
        )
        try await harness.awaitEnd()
        let events = harness.snapshot()
        #expect(errors(events).isEmpty)
        #expect(try only(completions(events)).ok == false)
        #expect(try harness.requests()[1].messages.last?.content == "target agent not found")
        #expect(try ended(events).status == .idle)
    }
}

@Test func endTurnStopsBeforeAnotherToolOrModelCall() async throws {
    try await exercise(
        scripted([
            [
                .toolCall(id: "handoff", name: "send_message", arguments: [:]),
                .toolCall(id: "later", name: "send_message", arguments: [:]),
            ],
        ])
    ) { harness in
        try await harness.start(startParams(delegatedTools: [sendMessage]))
        try await harness.waitUntil("handoff") { delegates($0).isEmpty == false }
        try await harness.kernel.provideToolResult(
            TurnToolResult(runId: "run-1", toolCallId: "handoff", ok: true, output: "returned to owner", endTurn: true)
        )
        try await harness.awaitEnd()
        let events = harness.snapshot()
        #expect(try harness.requests().count == 1)
        #expect(delegates(events).count == 1)
        #expect(try ended(events).status == .idle)
        #expect(errors(events).isEmpty)
    }
}

@Test func roundExhaustionSaysSo() async throws {
    let rounds: [[NormalizedChunk]] = (0..<20).map { index in
        [.toolCall(id: "c\(index)", name: "send_message", arguments: [:])]
    }
    try await exercise(scripted(rounds)) { harness in
        try await harness.start(startParams(delegatedTools: [sendMessage]))
        var answered = 0
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let events = harness.snapshot()
            if events.contains(where: { $0.name == KernelEvents.ended }) { break }
            let delegated = delegates(events)
            if delegated.count > answered {
                let callId = delegated[answered].toolCallId
                try await harness.kernel.provideToolResult(
                    TurnToolResult(runId: "run-1", toolCallId: callId, ok: true, output: "ok")
                )
                answered += 1
            }
            if answered > 16 {
                Issue.record("the round limit must stop the loop")
                break
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        let events = harness.snapshot()
        #expect(answered == 16)
        #expect(try harness.requests().count == 16)
        let notice = try #require(deltas(events).last)
        #expect(notice.delta == "Stopped after 16 tool rounds without a final answer.")
        #expect(notice.part == .text)
        #expect(try ended(events).status == .idle)
        #expect(errors(events).isEmpty)
    }
}

@Test func cancelDuringDelegateEndsCancelledWithoutError() async throws {
    try await exercise(scripted([[.toolCall(id: "c1", name: "send_message", arguments: [:])]])) { harness in
        try await harness.start(startParams(delegatedTools: [sendMessage]))
        try await harness.waitUntil("delegate") { delegates($0).isEmpty == false }
        try await harness.kernel.cancel(runId: "run-1")
        try await harness.awaitEnd()
        let events = harness.snapshot()
        #expect(try ended(events).status == .cancelled)
        #expect(errors(events).isEmpty)
        #expect(completions(events).isEmpty)
    }
}

@Test func cancelMidStreamEndsCancelledWithoutError() async throws {
    let model = HangingModel()
    try await exercise(model) { harness in
        try await harness.start(startParams())
        await model.started.wait()
        try await harness.kernel.cancel(runId: "run-1")
        try await harness.awaitEnd()
        let events = harness.snapshot()
        #expect(try ended(events).status == .cancelled)
        #expect(errors(events).isEmpty)
        #expect(try only(deltas(events)).delta == "partial")
    }
}

@Test func cancelDuringApprovalEndsCancelledWithoutError() async throws {
    let tools = FakeTools(
        defs: [writeTool],
        verdict: { _, target in PermissionVerdict(decision: .ask, target: target) }
    )
    try await exercise(
        scripted([[.toolCall(id: "c1", name: "write", arguments: ["path": .string("/tmp/needs-approval.txt")])]]),
        tools: tools
    ) { harness in
        try await harness.start(startParams(localToolNames: ["write"], toolPermission: .ask))
        try await harness.waitUntil("approval") { pending($0).isEmpty == false }
        try await harness.kernel.cancel(runId: "run-1")
        try await harness.awaitEnd()
        let events = harness.snapshot()
        #expect(try ended(events).status == .cancelled)
        #expect(errors(events).isEmpty)
        #expect(tools.executions.isEmpty)
        try await harness.waitUntil("release") { _ in tools.releases.contains("run-1") }
    }
}

@Test func missingKeyEndsTheTurnWithInvalidAndDoesNotCallTheModel() async throws {
    try await exercise(scripted([])) { harness in
        try await harness.start(startParams(secrets: Secrets()))
        try await harness.awaitEnd()
        let events = harness.snapshot()
        let error = try only(errors(events))
        #expect(error.code == KernelErrorCode.invalid)
        #expect(error.message == "API key missing for deepseek")
        #expect(try ended(events).status == .error)
        #expect(try harness.requests().isEmpty)
        #expect(harness.tools.binds.isEmpty)
    }
}

@Test func emptyKeyIsAlsoMissing() async throws {
    try await exercise(scripted([])) { harness in
        try await harness.start(startParams(secrets: Secrets(deepseekApiKey: "")))
        try await harness.awaitEnd()
        let error = try only(errors(harness.snapshot()))
        #expect(error.message == "API key missing for deepseek")
        #expect(error.code == 1007)
    }
}

@Test func missingKeyNamesEachProvider() async throws {
    let cases: [(ProviderId, String)] = [
        (.openai, "gpt-4o"),
        (.anthropic, "claude-sonnet-4-20250514"),
        (.deepseek, "deepseek-chat"),
    ]
    for (provider, model) in cases {
        try await exercise(scripted([])) { harness in
            try await harness.start(startParams(
                model: ModelRef(provider: provider, model: model),
                secrets: Secrets()
            ))
            try await harness.awaitEnd()
            let error = try only(errors(harness.snapshot()))
            #expect(error.code == KernelErrorCode.invalid)
            #expect(error.message == "API key missing for \(provider.rawValue)")
            #expect(!error.message.contains("sk-"))
        }
    }
}

@Test func summarizeKeepsTheSystemPromptAndOnlyText() async throws {
    try await exercise(scriptedChunks([.thinking("let me think"), .text("  a summary  ")])) { harness in
        let result = try await harness.kernel.summarize(summarizeParams())
        #expect(result.text == "a summary")
        let messages = try harness.requests().first?.messages ?? []
        #expect(messages.map(\.role) == [.system, .user])
        #expect(messages.map(\.content) == ["You summarize.", "long history"])
        #expect(harness.snapshot().isEmpty)
    }
}

@Test func summarizeGetsNoTools() async throws {
    try await exercise(scriptedChunks([.text("x")])) { harness in
        _ = try await harness.kernel.summarize(summarizeParams())
        let request = try only(harness.requests())
        #expect(request.tools.isEmpty)
        #expect(request.maxOutputTokens == 2048)
        #expect(request.apiKey == "k")
    }
}

@Test func summarizeEmptyModelYieldsEmptyString() async throws {
    try await exercise(scriptedChunks([])) { harness in
        let result = try await harness.kernel.summarize(summarizeParams())
        #expect(result.text == "")
    }
}

@Test func summarizeMissingKeyThrowsInvalid() async throws {
    try await exercise(scriptedChunks([.text("x")])) { harness in
        do {
            _ = try await harness.kernel.summarize(summarizeParams(secrets: Secrets(deepseekApiKey: "")))
            Issue.record("expected missing key")
        } catch let error as NuumError {
            #expect(error.code == KernelErrorCode.invalid)
            #expect(error.message == "API key missing for deepseek")
        }
        #expect(try harness.requests().isEmpty)
        #expect(harness.snapshot().isEmpty)
    }
}

@Test func contextWatermarkFailureSentenceIsUnchanged() async throws {
    try await exercise(scripted([])) { harness in
        try await harness.start(startParams(contextWindow: 10))
        try await harness.waitUntil("context") { contexts($0).isEmpty == false }
        let context = try only(contexts(harness.snapshot()))
        try await harness.kernel.provideContext(
            TurnContextResult(runId: "run-1", requestId: context.requestId)
        )
        try await harness.awaitEnd()
        let events = harness.snapshot()
        let error = try only(errors(events))
        #expect(error.message == "Context capacity exhausted; execution paused without replaying tools.")
        #expect(error.code == KernelErrorCode.internal)
        #expect(try ended(events).status == .error)
        #expect(try harness.requests().isEmpty)
    }
}

@Test func contextFailureAndCancellationDoNotCallTheModel() async throws {
    for cancel in [false, true] {
        try await exercise(scripted([])) { harness in
            try await harness.start(startParams(contextWindow: 10_000))
            try await harness.waitUntil("context") { contexts($0).isEmpty == false }
            if cancel {
                try await harness.kernel.cancel(runId: "run-1")
            } else {
                let requestId = try only(contexts(harness.snapshot())).requestId
                try await harness.kernel.provideContext(
                    TurnContextResult(runId: "run-1", requestId: requestId, error: "Compaction failed")
                )
            }
            try await harness.awaitEnd()
            let events = harness.snapshot()
            #expect(try harness.requests().isEmpty)
            if cancel {
                #expect(errors(events).isEmpty)
                #expect(try ended(events).status == .cancelled)
            } else {
                #expect(try only(errors(events)).message == "Compaction failed")
                #expect(try ended(events).status == .error)
            }
        }
    }
}

@Test func turnsThatOpenWithToolsGetOneAckThenOneSilence() async throws {
    let rounds = (0..<7).map { index in
        [NormalizedChunk.toolCall(id: "c\(index)", name: "step", arguments: [:])]
    } + [[NormalizedChunk.text("done")]]
    let tools = FakeTools(defs: [stepTool], onExecute: { _ in
        ToolExecutionResult(ok: true, output: "ok")
    })
    try await exercise(scripted(rounds), tools: tools) { harness in
        try await harness.start(startParams(localToolNames: ["step"]))
        try await harness.awaitEnd()
        let requests = try harness.requests()
        #expect(firstOf("ack", requests) == 2)
        #expect(firstOf("silence", requests) == 7)
        let last = reminderKinds(requests.last)
        #expect(last.filter { $0 == "ack" }.count == 1)
        #expect(last.filter { $0 == "silence" }.count == 1)
        #expect(requests.count == 8)
        let ack = try #require(requests.last?.messages.first { $0.id.hasPrefix("reminder-ack-") })
        #expect(ack.content == ackSentence("SendMessage"))
        let silence = try #require(requests.last?.messages.first { $0.id.hasPrefix("reminder-silence-") })
        #expect(silence.content == silenceSentence("SendMessage"))
    }
}

@Test func voiceCallResetsTheStreakAndResultReminderReplacesFurtherAcks() async throws {
    let tools = FakeTools(defs: [stepTool], onExecute: { _ in
        ToolExecutionResult(ok: true, output: "ok")
    })
    try await exercise(
        scripted([
            [
                .toolCall(id: "c1", name: "step", arguments: [:]),
                .toolCall(id: "c2", name: "step", arguments: [:]),
            ],
            [.toolCall(id: "c3", name: "send_message", arguments: [:])],
            [
                .toolCall(id: "c4", name: "step", arguments: [:]),
                .toolCall(id: "c5", name: "step", arguments: [:]),
            ],
            [.text("done")],
        ]),
        tools: tools
    ) { harness in
        try await harness.start(startParams(
            localToolNames: ["step"],
            delegatedTools: [sendMessage],
            voiceToolNames: ["send_message"]
        ))
        try await harness.waitUntil("delegate") { delegates($0).isEmpty == false }
        try await harness.kernel.provideToolResult(
            TurnToolResult(runId: "run-1", toolCallId: "c3", ok: true, output: "delivered")
        )
        try await harness.awaitEnd()
        let requests = try harness.requests()
        #expect(firstOf("ack", requests) == 1)
        #expect(reminderKinds(requests[2]) == reminderKinds(requests[1]))
        #expect(firstOf("result", requests) == 3)
        let last = reminderKinds(requests.last)
        #expect(last.filter { $0 == "ack" }.count == 1)
        #expect(last.filter { $0 == "result" }.count == 1)
        #expect(requests.count == 4)
        let result = try #require(requests.last?.messages.first { $0.id.hasPrefix("reminder-result-") })
        #expect(result.content == resultSentence("send_message"))
    }
}

@Test func voiceToolNamesSuppressTheAckReminder() async throws {
    try await exercise(
        scripted([
            [
                .toolCall(id: "c1", name: "send_message", arguments: [:]),
                .toolCall(id: "c2", name: "send_message", arguments: [:]),
            ],
            [.text("done")],
        ])
    ) { harness in
        try await harness.start(startParams(
            delegatedTools: [sendMessage],
            voiceToolNames: ["send_message"]
        ))
        for id in ["c1", "c2"] {
            let needed = id == "c1" ? 1 : 2
            try await harness.waitUntil(id) { delegates($0).count >= needed }
            try await harness.kernel.provideToolResult(
                TurnToolResult(runId: "run-1", toolCallId: id, ok: true, output: "delivered")
            )
        }
        try await harness.awaitEnd()
        for request in try harness.requests() {
            #expect(reminderKinds(request).isEmpty)
        }
    }
}

@Test func compactedContextDropsHostImagesAndKeepsTheSummary() async throws {
    try await exercise(
        scripted([
            [.toolCall(id: "c", name: "send_message", arguments: [:])],
            [.text("done")],
        ])
    ) { harness in
        try await harness.start(startParams(
            messages: [
                ChatMessage(
                    id: "uploaded-image",
                    role: .user,
                    content: "Look at this",
                    seq: 1,
                    createdAt: 0,
                    images: [ModelImage(mimeType: "image/png", data: "aGVsbG8=")]
                ),
            ],
            contextWindow: 10_000,
            delegatedTools: [sendMessage]
        ))
        try await harness.waitUntil("first context") { contexts($0).isEmpty == false }
        #expect(try harness.requests().isEmpty)
        try await harness.kernel.provideContext(
            TurnContextResult(
                runId: "run-1",
                requestId: try only(contexts(harness.snapshot())).requestId
            )
        )
        try await harness.waitUntil("tool") { delegates($0).isEmpty == false }
        try await harness.kernel.provideToolResult(
            TurnToolResult(runId: "run-1", toolCallId: "c", ok: true, output: "delivered")
        )
        try await harness.waitUntil("next context") { contexts($0).count == 2 }
        let requestId = try #require(contexts(harness.snapshot()).last).requestId
        try await harness.kernel.provideContext(
            TurnContextResult(
                runId: "run-1",
                requestId: requestId,
                messages: [
                    ChatMessage(id: "summary", role: .user, content: "compacted history", seq: 1, createdAt: 0),
                ]
            )
        )
        try await harness.awaitEnd()
        let requests = try harness.requests()
        #expect(requests.count == 2)
        #expect(requests[0].maxOutputTokens == 1000)
        #expect(requests[1].messages.contains { $0.id == "summary" })
        #expect(!requests[1].messages.contains { $0.id == "uploaded-image" })
        #expect(!requests[1].messages.contains { ($0.toolCalls ?? []).isEmpty == false })
    }
}

@Test func localImageResultReachesTheNextRoundButNotTheToolOutput() async throws {
    let tools = FakeTools(defs: [readTool], onExecute: { _ in
        ToolExecutionResult(
            ok: true,
            output: "Read image file: /tmp/pixel.png",
            images: [ModelImage(mimeType: "image/png", data: "aGVsbG8=")]
        )
    })
    try await exercise(
        scripted([
            [.toolCall(id: "c-image", name: "read", arguments: ["path": .string("/tmp/pixel.png")])],
            [.text("I can see it")],
        ]),
        tools: tools
    ) { harness in
        try await harness.start(startParams(localToolNames: ["read"]))
        try await harness.awaitEnd()
        let second = try harness.requests()[1].messages
        let toolMessage = second[second.count - 2]
        #expect(toolMessage.role == .tool)
        #expect(toolMessage.content == "Read image file: /tmp/pixel.png")
        #expect(second.last?.role == .user)
        #expect(second.last?.images == [ModelImage(mimeType: "image/png", data: "aGVsbG8=")])
        #expect(second.last?.id.hasPrefix("tool-images-") == true)
        #expect(try only(completions(harness.snapshot())).output == "Read image file: /tmp/pixel.png")
    }
}

@Test func shellIdInspectionAsksToReadTheTerminalFile() async throws {
    let shellId = "00000000-0000-4000-8000-000000000001"
    let tools = FakeTools(defs: [shellTool], onExecute: { _ in
        ToolExecutionResult(ok: true, output: "inspected")
    })
    try await exercise(
        scripted([
            [.toolCall(id: "c-shell", name: "shell", arguments: ["shell_id": .string(shellId)])],
            [.text("done")],
        ]),
        tools: tools
    ) { harness in
        try await harness.start(startParams(localToolNames: ["shell"], toolPermission: .never))
        try await harness.awaitEnd()
        #expect(tools.boundPermission == .never)
        #expect(tools.authorizations == [ToolTarget(action: .readFile, target: "/tmp/nuum-loop/agents/a1/terminals/\(shellId).txt")])
        #expect(pending(harness.snapshot()).isEmpty)
        #expect(try only(started(harness.snapshot())).toolName == "shell")
        #expect(tools.executions.map(\.name) == ["shell"])
    }
}

@Test func unknownToolFailsTheTurn() async throws {
    try await exercise(scripted([[.toolCall(id: "c1", name: "ghost", arguments: [:])]])) { harness in
        try await harness.start(startParams())
        try await harness.awaitEnd()
        let events = harness.snapshot()
        let error = try only(errors(events))
        #expect(error.code == KernelErrorCode.tool)
        #expect(error.message.contains("Unknown tool: ghost"))
        #expect(try ended(events).status == .error)
    }
}

@Test func cancelSummaryDoesNotEmitATurnError() async throws {
    let model = HangingModel()
    try await exercise(model) { harness in
        let summary = Task {
            try await harness.kernel.summarize(summarizeParams())
        }
        await model.started.wait()
        try await harness.kernel.cancelSummary(runId: "run-1")
        do {
            _ = try await summary.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
            #expect(harness.snapshot().isEmpty)
        }
    }
}

@Test func deniedPermissionIsAFailedToolResult() async throws {
    let tools = FakeTools(
        defs: [writeTool],
        verdict: { _, target in PermissionVerdict(decision: .deny, target: target) },
        onExecute: { _ in ToolExecutionResult(ok: true, output: "written") }
    )
    try await exercise(
        scripted([
            [.toolCall(id: "c1", name: "write", arguments: ["path": .string("/tmp/secret.txt")])],
            [.text("ok")],
        ]),
        tools: tools
    ) { harness in
        try await harness.start(startParams(localToolNames: ["write"]))
        try await harness.awaitEnd()
        let events = harness.snapshot()
        #expect(try only(completions(events)).output == "Permission denied for write-file /tmp/secret.txt")
        #expect(tools.executions.isEmpty)
        #expect(started(events).isEmpty)
        #expect(try ended(events).status == .idle)
    }
}

@Test func onceApprovalGrantsThisCallAndExecutes() async throws {
    let tools = FakeTools(
        defs: [writeTool],
        verdict: { _, target in PermissionVerdict(decision: .ask, target: target) },
        onExecute: { _ in ToolExecutionResult(ok: true, output: "written") }
    )
    try await exercise(
        scripted([
            [.toolCall(id: "c1", name: "write", arguments: ["path": .string("/tmp/needs-approval.txt")])],
            [.text("ok")],
        ]),
        tools: tools
    ) { harness in
        try await harness.start(startParams(localToolNames: ["write"], toolPermission: .ask))
        try await harness.waitUntil("approval") { pending($0).isEmpty == false }
        try await harness.kernel.approveTool(TurnToolDecision(runId: "run-1", toolCallId: "c1", resolution: .once))
        try await harness.awaitEnd()
        #expect(tools.grants == [ToolTarget(action: .writeFile, target: "/tmp/needs-approval.txt")])
        #expect(tools.permissionUpdates.isEmpty)
        #expect(tools.executions.map(\.name) == ["write"])
        #expect(try only(completions(harness.snapshot())).output == "written")
        #expect(try ended(harness.snapshot()).status == .idle)
    }
}

@Test func neverRefusalSetsPermissionAndSkipsExecute() async throws {
    let tools = FakeTools(
        defs: [writeTool],
        verdict: { _, target in PermissionVerdict(decision: .ask, target: target) },
        onExecute: { _ in ToolExecutionResult(ok: true, output: "written") }
    )
    try await exercise(
        scripted([
            [.toolCall(id: "c1", name: "write", arguments: ["path": .string("/tmp/needs-approval.txt")])],
            [.text("ok")],
        ]),
        tools: tools
    ) { harness in
        try await harness.start(startParams(localToolNames: ["write"], toolPermission: .ask))
        try await harness.waitUntil("approval") { pending($0).isEmpty == false }
        try await harness.kernel.approveTool(TurnToolDecision(runId: "run-1", toolCallId: "c1", resolution: .never))
        try await harness.awaitEnd()
        #expect(tools.permissionUpdates == [.never])
        #expect(tools.refusals == [ToolTarget(action: .writeFile, target: "/tmp/needs-approval.txt")])
        #expect(tools.executions.isEmpty)
        #expect(try only(completions(harness.snapshot())).output == "User denied this tool call.")
        #expect(try ended(harness.snapshot()).status == .idle)
    }
}

@Test func userDenialIsAFailedToolResult() async throws {
    let tools = FakeTools(
        defs: [writeTool],
        verdict: { _, target in PermissionVerdict(decision: .ask, target: target) }
    )
    try await exercise(
        scripted([
            [.toolCall(id: "c1", name: "write", arguments: ["path": .string("/tmp/needs-approval.txt")])],
            [.text("ok")],
        ]),
        tools: tools
    ) { harness in
        try await harness.start(startParams(localToolNames: ["write"], toolPermission: .ask))
        try await harness.waitUntil("approval") { pending($0).isEmpty == false }
        let approval = try only(pending(harness.snapshot()))
        #expect(approval.action == .writeFile)
        #expect(approval.target == "/tmp/needs-approval.txt")
        #expect(approval.mutating)
        try await harness.kernel.denyTool(TurnToolDecision(runId: "run-1", toolCallId: "c1", resolution: .deny))
        try await harness.awaitEnd()
        let events = harness.snapshot()
        #expect(try only(completions(events)).output == "User denied this tool call.")
        #expect(tools.executions.isEmpty)
        #expect(tools.refusals == [ToolTarget(action: .writeFile, target: "/tmp/needs-approval.txt")])
        #expect(try ended(events).status == .idle)
        #expect(errors(events).isEmpty)
    }
}

@Test func aSecondStartWhileRunningIsBusy() async throws {
    let model = HangingModel()
    try await exercise(model) { harness in
        try await harness.start(startParams())
        await model.started.wait()
        do {
            try await harness.kernel.start(startParams())
            Issue.record("expected busy")
        } catch let error as NuumError {
            #expect(error.code == KernelErrorCode.turnBusy)
            #expect(error.message == "Run run-1 is already running")
        }
        try await harness.kernel.cancel(runId: "run-1")
        try await harness.awaitEnd()
    }
}

@Test func estimateModelTokensMatchesTheMacBudget() {
    let message = ChatMessage(id: "u1", role: .user, content: "go", seq: 0, createdAt: 1)
    #expect(estimateModelTokens([message]) == 30)
    var wide = message
    wide.content = "你好"
    #expect(estimateModelTokens([wide]) == 33)
    var withImage = message
    withImage.images = [ModelImage(mimeType: "image/png", data: "aGVsbG8=")]
    #expect(estimateModelTokens([withImage]) == 30 + 8192)
    var huge = message
    huge.images = [ModelImage(mimeType: "image/png", data: String(repeating: "A", count: 10_000))]
    #expect(estimateModelTokens([huge]) == estimateModelTokens([message]) + 8192)
    var cjk = message
    cjk.content += "你"
    #expect(estimateModelTokens([cjk]) == estimateModelTokens([message]) + 2)
}

private func exercise(
    _ model: any ModelPort,
    tools: FakeTools = FakeTools(),
    _ body: @escaping @Sendable (Harness) async throws -> Void
) async throws {
    let kernel = Kernel(model: model, tools: tools, clock: FixedClock())
    let log = EventLog()
    let collector = Task {
        for await event in kernel.events {
            log.append(event)
        }
    }
    let harness = Harness(kernel: kernel, model: model, tools: tools, log: log)
    defer { collector.cancel() }
    try await withTimeout(seconds: 20) {
        try await body(harness)
    }
}

private func withTimeout(
    seconds: Double,
    _ body: @escaping @Sendable () async throws -> Void
) async throws {
    try await withThrowingTaskGroup(of: Bool.self) { group in
        group.addTask {
            try await body()
            return true
        }
        group.addTask {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            } catch {
                return true
            }
        }
        let finished = try await group.next() ?? false
        group.cancelAll()
        if !finished {
            throw WaitFailure(what: "overall timeout", events: [])
        }
    }
}

private struct FixedClock: Clock {
    func nowMillis() -> Int64 { 1 }
}

private struct WaitFailure: Error, CustomStringConvertible {
    var what: String
    var events: [String]
    var description: String { "timed out waiting for \(what); events=\(events.joined(separator: ","))" }
}

private struct ToolTarget: Equatable {
    var action: LocalToolAction
    var target: String
}

private struct UnexpectedExecute: Error, CustomStringConvertible {
    var name: String
    var description: String { "unexpected execute \(name)" }
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [KernelEvent] = []

    func append(_ event: KernelEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [KernelEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private final class AsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func fire() {
        lock.lock()
        if fired {
            lock.unlock()
            return
        }
        fired = true
        let waiters = self.waiters
        self.waiters.removeAll()
        lock.unlock()
        for waiter in waiters { waiter.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }
}

private final class Harness: @unchecked Sendable {
    let kernel: Kernel
    let tools: FakeTools
    private let model: any ModelPort
    private let log: EventLog

    init(kernel: Kernel, model: any ModelPort, tools: FakeTools, log: EventLog) {
        self.kernel = kernel
        self.model = model
        self.tools = tools
        self.log = log
    }

    func start(_ params: TurnStartParams) async throws {
        try await kernel.start(params)
    }

    func snapshot() -> [KernelEvent] {
        log.snapshot()
    }

    func waitUntil(
        _ what: String,
        timeoutMs: UInt64 = 3_000,
        _ predicate: @Sendable ([KernelEvent]) -> Bool
    ) async throws {
        let attempts = max(1, timeoutMs / 2)
        for _ in 0..<attempts {
            let events = snapshot()
            if predicate(events) { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        throw WaitFailure(what: what, events: snapshot().map(\.name))
    }

    func awaitEnd() async throws {
        try await waitUntil("turn end", timeoutMs: 5_000) { events in
            events.contains { $0.name == KernelEvents.ended }
        }
    }

    func requests() throws -> [NormalizedChatRequest] {
        guard let model = model as? ScriptedModel else {
            throw WaitFailure(what: "scripted model", events: [])
        }
        return model.requests
    }
}

private final class ScriptedModel: ModelPort, @unchecked Sendable {
    private let lock = NSLock()
    private let rounds: [[NormalizedChunk]]
    private var cursor = 0
    private var stored: [NormalizedChatRequest] = []

    init(rounds: [[NormalizedChunk]]) {
        self.rounds = rounds
    }

    var requests: [NormalizedChatRequest] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func streamChat(_ request: NormalizedChatRequest) -> AsyncThrowingStream<NormalizedChunk, Error> {
        let chunks: [NormalizedChunk] = {
            lock.lock()
            defer { lock.unlock() }
            stored.append(request)
            let chunks = cursor < rounds.count ? rounds[cursor] : [.text("")]
            cursor += 1
            return chunks
        }()
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

private final class HangingModel: ModelPort, @unchecked Sendable {
    let started = AsyncSignal()
    private let lock = NSLock()
    private var callCount = 0

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    func streamChat(_ request: NormalizedChatRequest) -> AsyncThrowingStream<NormalizedChunk, Error> {
        lock.lock()
        callCount += 1
        lock.unlock()
        let started = self.started
        return AsyncThrowingStream { continuation in
            continuation.yield(.text("partial"))
            started.fire()
        }
    }
}

private final class FakeTools: ToolBackend, @unchecked Sendable {
    private let lock = NSLock()
    private let defs: [ToolDefinition]
    private let verdictOf: @Sendable (LocalToolAction, String) -> PermissionVerdict
    private let onExecute: @Sendable (ToolCall) async throws -> ToolExecutionResult
    private var storedBinds: [String] = []
    private var storedReleases: [String] = []
    private var storedAuthorizations: [ToolTarget] = []
    private var storedExecutions: [ToolCall] = []
    private var storedRefusals: [ToolTarget] = []
    private var storedGrants: [ToolTarget] = []
    private var storedPermissions: [ToolPermission] = []
    private var storedPermission: ToolPermission?

    init(
        defs: [ToolDefinition] = [],
        verdict: @escaping @Sendable (LocalToolAction, String) -> PermissionVerdict = { _, target in
            PermissionVerdict(decision: .allow, target: target)
        },
        onExecute: @escaping @Sendable (ToolCall) async throws -> ToolExecutionResult = { call in
            throw UnexpectedExecute(name: call.name)
        }
    ) {
        self.defs = defs
        self.verdictOf = verdict
        self.onExecute = onExecute
    }

    func definitions() -> [ToolDefinition] { defs }

    var binds: [String] { copy { $0.storedBinds } }
    var releases: [String] { copy { $0.storedReleases } }
    var authorizations: [ToolTarget] { copy { $0.storedAuthorizations } }
    var executions: [ToolCall] { copy { $0.storedExecutions } }
    var refusals: [ToolTarget] { copy { $0.storedRefusals } }
    var grants: [ToolTarget] { copy { $0.storedGrants } }
    var permissionUpdates: [ToolPermission] { copy { $0.storedPermissions } }
    var boundPermission: ToolPermission? { copy { $0.storedPermission } }

    func bind(
        runId: String,
        roots: ToolRoots,
        permission: ToolPermission,
        approvals: [ToolApproval],
        refused: [ToolApproval]
    ) {
        lock.lock()
        storedBinds.append(runId)
        storedPermission = permission
        lock.unlock()
    }

    func authorize(runId: String, action: LocalToolAction, target: String) async throws -> PermissionVerdict {
        let verdict = verdictOf(action, target)
        recordAuthorization(ToolTarget(action: action, target: target))
        return verdict
    }

    func grantOnce(runId: String, action: LocalToolAction, target: String) {
        recordGrant(ToolTarget(action: action, target: target))
    }

    func refuse(runId: String, action: LocalToolAction, target: String) {
        recordRefusal(ToolTarget(action: action, target: target))
    }

    func setPermission(runId: String, permission: ToolPermission) {
        lock.lock()
        storedPermissions.append(permission)
        lock.unlock()
    }

    func execute(runId: String, call: ToolCall) async throws -> ToolExecutionResult {
        recordExecution(call)
        return try await onExecute(call)
    }

    private func recordAuthorization(_ target: ToolTarget) {
        lock.lock()
        storedAuthorizations.append(target)
        lock.unlock()
    }

    private func recordGrant(_ target: ToolTarget) {
        lock.lock()
        storedGrants.append(target)
        lock.unlock()
    }

    private func recordRefusal(_ target: ToolTarget) {
        lock.lock()
        storedRefusals.append(target)
        lock.unlock()
    }

    private func recordExecution(_ call: ToolCall) {
        lock.lock()
        storedExecutions.append(call)
        lock.unlock()
    }

    func release(runId: String) {
        lock.lock()
        storedReleases.append(runId)
        lock.unlock()
    }

    private func copy<T>(_ read: (FakeTools) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return read(self)
    }
}

private func scripted(_ rounds: [[NormalizedChunk]]) -> ScriptedModel {
    ScriptedModel(rounds: rounds)
}

private func scriptedChunks(_ chunks: [NormalizedChunk]) -> ScriptedModel {
    ScriptedModel(rounds: [chunks])
}

private func reminderKinds(_ request: NormalizedChatRequest?) -> [String] {
    guard let request else { return [] }
    return request.messages.compactMap { message in
        guard message.id.hasPrefix("reminder-") else { return nil }
        let parts = message.id.split(separator: "-")
        return parts.count > 1 ? String(parts[1]) : nil
    }
}

private func firstOf(_ kind: String, _ requests: [NormalizedChatRequest]) -> Int {
    requests.firstIndex { reminderKinds($0).contains(kind) } ?? -1
}

private func runId(of event: KernelEvent) -> String {
    switch event {
    case .context(let payload): payload.runId
    case .delta(let payload): payload.runId
    case .toolPending(let payload): payload.runId
    case .toolStarted(let payload): payload.runId
    case .toolDelegate(let payload): payload.runId
    case .toolCompleted(let payload): payload.runId
    case .error(let payload): payload.runId
    case .ended(let payload): payload.runId
    }
}

private func deltas(_ events: [KernelEvent]) -> [KernelDeltaEvent] {
    events.compactMap { if case .delta(let payload) = $0 { payload } else { nil } }
}

private func delegates(_ events: [KernelEvent]) -> [KernelToolDelegateEvent] {
    events.compactMap { if case .toolDelegate(let payload) = $0 { payload } else { nil } }
}

private func completions(_ events: [KernelEvent]) -> [KernelToolCompletedEvent] {
    events.compactMap { if case .toolCompleted(let payload) = $0 { payload } else { nil } }
}

private func errors(_ events: [KernelEvent]) -> [KernelErrorEvent] {
    events.compactMap { if case .error(let payload) = $0 { payload } else { nil } }
}

private func contexts(_ events: [KernelEvent]) -> [KernelContextEvent] {
    events.compactMap { if case .context(let payload) = $0 { payload } else { nil } }
}

private func pending(_ events: [KernelEvent]) -> [KernelToolPendingEvent] {
    events.compactMap { if case .toolPending(let payload) = $0 { payload } else { nil } }
}

private func started(_ events: [KernelEvent]) -> [KernelToolStartedEvent] {
    events.compactMap { if case .toolStarted(let payload) = $0 { payload } else { nil } }
}

private func ended(_ events: [KernelEvent]) throws -> KernelEndedEvent {
    for event in events.reversed() {
        if case .ended(let payload) = event { return payload }
    }
    throw WaitFailure(what: "ended event", events: events.map(\.name))
}

private func only<T>(_ items: [T]) throws -> T {
    guard items.count == 1, let first = items.first else {
        throw WaitFailure(what: "exactly one item, got \(items.count)", events: [])
    }
    return first
}

private func objectSchema(_ properties: [String: JSONValue] = [:]) -> [String: JSONValue] {
    [
        "type": .string("object"),
        "properties": .object(properties),
    ]
}

private let sendMessage = ToolDefinition(
    name: "send_message",
    description: "post a message",
    inputSchema: objectSchema(["text": .object(["type": .string("string")])]),
    mutating: false
)

private let stepTool = ToolDefinition(
    name: "step",
    description: "one unit of silent work",
    inputSchema: objectSchema(),
    mutating: false,
    action: .readFile
)

private let readTool = ToolDefinition(
    name: "read",
    description: "read an image",
    inputSchema: objectSchema(["path": .object(["type": .string("string")])]),
    mutating: false,
    action: .readFile
)

private let writeTool = ToolDefinition(
    name: "write",
    description: "w",
    inputSchema: objectSchema(["path": .object(["type": .string("string")])]),
    mutating: true,
    action: .writeFile
)

private let shellTool = ToolDefinition(
    name: "shell",
    description: "inspect a shell",
    inputSchema: objectSchema(["shell_id": .object(["type": .string("string")])]),
    mutating: true,
    action: .runCommand
)

private func startParams(
    runId: String = "run-1",
    messages: [ChatMessage] = [ChatMessage(id: "u1", role: .user, content: "go", seq: 0, createdAt: 1)],
    model: ModelRef = ModelRef(provider: .deepseek, model: "deepseek-chat"),
    secrets: Secrets = Secrets(deepseekApiKey: "k"),
    contextWindow: Int? = nil,
    localToolNames: [String] = [],
    delegatedTools: [ToolDefinition] = [],
    voiceToolNames: [String] = ["SendMessage"],
    toolPermission: ToolPermission = .always
) -> TurnStartParams {
    TurnStartParams(
        runId: runId,
        messages: messages,
        model: model,
        roots: ToolRoots(
            home: "/tmp",
            project: nil,
            scratch: "/tmp/nuum-loop/agents/a1/scratch",
            terminals: "/tmp/nuum-loop/agents/a1/terminals",
            denied: []
        ),
        toolPermission: toolPermission,
        localToolNames: localToolNames,
        secrets: secrets,
        contextWindow: contextWindow,
        delegatedTools: delegatedTools,
        voiceToolNames: voiceToolNames
    )
}

private func summarizeParams(secrets: Secrets = Secrets(deepseekApiKey: "k")) -> SummarizeRunParams {
    SummarizeRunParams(
        runId: "run-1",
        systemPrompt: "You summarize.",
        messages: [ChatMessage(id: "u1", role: .user, content: "long history", seq: 1, createdAt: 1)],
        model: ModelRef(provider: .deepseek, model: "deepseek-chat"),
        secrets: secrets
    )
}

private func ackSentence(_ voice: String) -> String {
    "<system_reminder>You opened this turn by calling tools without first acknowledging the user, "
        + "so they are watching silence and may think the app froze. Call \(voice) right now — a real tool "
        + "call, not text you write — with a one-line acknowledgement before any further tool call, then continue the work.</system_reminder>"
}

private func silenceSentence(_ voice: String) -> String {
    "<system_reminder>You have made several tool calls without a message, so the user is currently "
        + "watching silence. Call \(voice) now with a brief, specific update on what you are doing or what "
        + "you just found, then continue.</system_reminder>"
}

private func resultSentence(_ voice: String) -> String {
    "<system_reminder>The user cannot see tool output or your thinking — only \(voice) reaches them. "
        + "If you have produced a result or finished what they asked, send it with \(voice) before continuing "
        + "or ending the turn; if you are still mid-task, keep working and send it once you have it.</system_reminder>"
}
