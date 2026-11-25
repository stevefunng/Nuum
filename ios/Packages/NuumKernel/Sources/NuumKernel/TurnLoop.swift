import Foundation
import NuumContracts

let maxRounds = 16
let roundLimitNotice = "Stopped after \(maxRounds) tool rounds without a final answer."
let contextExhausted = "Context capacity exhausted; execution paused without replaying tools."
let toolImagesPrefix = "tool-images-"
let toolImagesText = "Images returned by the preceding local read tool calls."
let reminderPrefix = "reminder-"

/// ack（从未发声）在静默调用数超过 1 时；silence 超过 6；result 在发过声后又埋头（超过 0）。
let ackToolThreshold = 1
let silenceToolThreshold = 6
let resultToolThreshold = 0

enum ReminderKind: String, Sendable {
    case ack
    case silence
    case result
}

struct DelegatedResult: Sendable {
    var ok: Bool
    var output: String
    var endTurn: Bool
}

struct ResolvedTool: Sendable {
    var ok: Bool
    var output: String
    var images: [ModelImage] = []
    var endTurn: Bool = false
}

struct ControlError: Error {
    var message: String
}

struct TurnTables {
    var task: Task<Void, Never>?
    var cancelRequested = false
    var decisions: [String: ResumeBox<ToolResolution>] = [:]
    var delegations: [String: ResumeBox<DelegatedResult>] = [:]
    var contexts: [String: ResumeBox<TurnContextResult>] = [:]
}

/// One in-flight turn. Host replies land on the boxes; cancel fails them.
final class ActiveTurn: @unchecked Sendable {
    private let tables = Locked(TurnTables())

    var isCancelRequested: Bool {
        tables.withLock { $0.cancelRequested }
    }

    func store(_ task: Task<Void, Never>) {
        let shouldCancel = tables.withLock { state -> Bool in
            state.task = task
            return state.cancelRequested
        }
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        let task = tables.withLock { state -> Task<Void, Never>? in
            state.cancelRequested = true
            return state.task
        }
        task?.cancel()
    }

    func waitDecision(id: String, announce: @escaping @Sendable () -> Void) async throws -> ToolResolution {
        try await wait(
            insert: { box in
                self.tables.withLock { state in
                    state.decisions[id] = box
                }
            },
            take: { expected in
                self.tables.withLock { state in
                    guard let current = state.decisions[id], current === expected else { return nil }
                    state.decisions[id] = nil
                    return current
                }
            },
            announce: announce
        )
    }

    func waitDelegation(id: String, announce: @escaping @Sendable () -> Void) async throws -> DelegatedResult {
        try await wait(
            insert: { box in
                self.tables.withLock { state in
                    state.delegations[id] = box
                }
            },
            take: { expected in
                self.tables.withLock { state in
                    guard let current = state.delegations[id], current === expected else { return nil }
                    state.delegations[id] = nil
                    return current
                }
            },
            announce: announce
        )
    }

    func waitContext(id: String, announce: @escaping @Sendable () -> Void) async throws -> TurnContextResult {
        try await wait(
            insert: { box in
                self.tables.withLock { state in
                    state.contexts[id] = box
                }
            },
            take: { expected in
                self.tables.withLock { state in
                    guard let current = state.contexts[id], current === expected else { return nil }
                    state.contexts[id] = nil
                    return current
                }
            },
            announce: announce
        )
    }

    func completeDecision(id: String, resolution: ToolResolution) {
        let box = tables.withLock { $0.decisions.removeValue(forKey: id) }
        box?.succeed(resolution)
    }

    func completeDelegation(id: String, result: DelegatedResult) {
        let box = tables.withLock { $0.delegations.removeValue(forKey: id) }
        box?.succeed(result)
    }

    func completeContext(id: String, result: TurnContextResult) {
        let box = tables.withLock { $0.contexts.removeValue(forKey: id) }
        box?.succeed(result)
    }

    private func wait<T: Sendable>(
        insert: @Sendable (ResumeBox<T>) -> Void,
        take: @escaping @Sendable (ResumeBox<T>) -> ResumeBox<T>?,
        announce: @escaping @Sendable () -> Void
    ) async throws -> T {
        let box = ResumeBox<T>()
        insert(box)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                box.register(continuation)
                announce()
            }
        } onCancel: {
            take(box)?.fail(CancellationError())
        }
    }
}

struct TurnEngine: Sendable {
    var model: any ModelPort
    var tools: any ToolExecutor
    var clock: any Clock
    var newId: @Sendable () -> String
    var toolDefinitions: (@Sendable () -> [ToolDefinition])?
    var publish: @Sendable (KernelEvent) -> Void

    func run(
        _ params: TurnStartParams,
        turn: ActiveTurn,
        onFinish: @escaping @Sendable () -> Void
    ) async {
        var bound = false
        do {
            try Task.checkCancellation()
            if turn.isCancelRequested { throw CancellationError() }
            let apiKey = try apiKey(for: params.secrets, provider: params.model.provider)
            tools.bind(
                runId: params.runId,
                roots: params.roots,
                permission: params.toolPermission,
                approvals: params.approvals,
                refused: params.refused
            )
            bound = true
            try await drive(params, turn: turn, apiKey: apiKey)
        } catch is CancellationError {
            // 取消是正常收束，不是错误，所以不发 turn.error。
            publish(.ended(KernelEndedEvent(runId: params.runId, status: .cancelled)))
        } catch let error as NuumError {
            publish(.error(KernelErrorEvent(runId: params.runId, code: error.code, message: error.message)))
            publish(.ended(KernelEndedEvent(runId: params.runId, status: .error)))
        } catch let error as ControlError {
            publish(.error(KernelErrorEvent(runId: params.runId, code: KernelErrorCode.internal, message: error.message)))
            publish(.ended(KernelEndedEvent(runId: params.runId, status: .error)))
        } catch {
            publish(.error(KernelErrorEvent(
                runId: params.runId,
                code: KernelErrorCode.internal,
                message: error.localizedDescription
            )))
            publish(.ended(KernelEndedEvent(runId: params.runId, status: .error)))
        }
        if bound {
            tools.release(runId: params.runId)
        }
        onFinish()
    }

    private func drive(_ params: TurnStartParams, turn: ActiveTurn, apiKey: String) async throws {
        let catalog = definitions()
        let enabled = Set(params.localToolNames)
        let visible = catalog.filter { enabled.contains($0.name) } + params.delegatedTools
        let delegated = Set(params.delegatedTools.map(\.name))
        var messages = params.messages
        let voiceTools = Set(params.voiceToolNames)
        let voice = params.voiceToolNames.first ?? "SendMessage"
        var toolCallsSinceVoice = 0
        var voiceSentThisTurn = false
        var reminded = Set<ReminderKind>()

        for _ in 0..<maxRounds {
            try Task.checkCancellation()
            if turn.isCancelRequested { throw CancellationError() }
            let window = params.contextWindow
            if let window {
                let requestId = newId()
                let snapshot = messages
                let visibleTools = visible
                let runId = params.runId
                let publish = self.publish
                let next = try await turn.waitContext(id: requestId) {
                    publish(.context(KernelContextEvent(
                        runId: runId,
                        requestId: requestId,
                        usedTokens: estimateModelTokens(snapshot, tools: visibleTools)
                    )))
                }
                try Task.checkCancellation()
                if turn.isCancelRequested { throw CancellationError() }
                if let failure = next.error {
                    throw ControlError(message: failure)
                }
                if let replacement = next.messages {
                    let local = messages.filter { message in
                        message.id.hasPrefix(toolImagesPrefix) || message.id.hasPrefix(reminderPrefix)
                    }
                    let kept = local.filter { item in
                        !replacement.contains { $0.id == item.id }
                    }
                    messages = replacement + kept
                }
                if Double(estimateModelTokens(messages, tools: visible)) > Double(window) * 0.9 {
                    throw ControlError(message: contextExhausted)
                }
            }

            let messageId = newId()
            var text = ""
            var thinking = ""
            var toolCalls: [ToolCall] = []
            let request = NormalizedChatRequest(
                model: params.model,
                messages: messages,
                tools: visible,
                apiKey: apiKey,
                maxOutputTokens: window.map(outputCap)
            )
            do {
                for try await chunk in model.streamChat(request) {
                    try Task.checkCancellation()
                    switch chunk {
                    case .thinking(let piece):
                        thinking += piece
                        publish(.delta(KernelDeltaEvent(
                            runId: params.runId,
                            messageId: messageId,
                            delta: piece,
                            part: .thinking
                        )))
                    case .text(let piece):
                        text += piece
                        publish(.delta(KernelDeltaEvent(
                            runId: params.runId,
                            messageId: messageId,
                            delta: piece,
                            part: .text
                        )))
                    case .toolCall(let id, let name, let arguments):
                        toolCalls.append(ToolCall(id: id, name: name, arguments: arguments))
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled || turn.isCancelRequested { throw CancellationError() }
                throw error
            }
            if Task.isCancelled || turn.isCancelRequested { throw CancellationError() }

            messages.append(ChatMessage(
                id: messageId,
                role: .assistant,
                content: text,
                seq: messages.count,
                createdAt: clock.nowMillis(),
                thinking: thinking.isEmpty ? nil : thinking,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            ))
            if toolCalls.isEmpty {
                publish(.ended(KernelEndedEvent(runId: params.runId, status: .idle)))
                return
            }

            var toolImages: [ModelImage] = []
            for call in toolCalls {
                let result = try await resolveToolCall(
                    params,
                    turn: turn,
                    call: call,
                    delegated: delegated,
                    catalog: catalog
                )
                messages.append(ChatMessage(
                    id: newId(),
                    role: .tool,
                    content: result.output,
                    seq: messages.count,
                    createdAt: clock.nowMillis(),
                    toolCallId: call.id,
                    name: call.name
                ))
                toolImages.append(contentsOf: result.images)
                publish(.toolCompleted(KernelToolCompletedEvent(
                    runId: params.runId,
                    toolCallId: call.id,
                    toolName: call.name,
                    ok: result.ok,
                    output: result.output
                )))
                if result.ok && result.endTurn {
                    publish(.ended(KernelEndedEvent(runId: params.runId, status: .idle)))
                    return
                }
                if voiceTools.contains(call.name) {
                    toolCallsSinceVoice = 0
                    voiceSentThisTurn = true
                    reminded.removeAll()
                } else {
                    toolCallsSinceVoice += 1
                }
            }
            if !toolImages.isEmpty {
                messages.append(ChatMessage(
                    id: toolImagesPrefix + newId(),
                    role: .user,
                    content: toolImagesText,
                    seq: messages.count,
                    createdAt: clock.nowMillis(),
                    images: toolImages
                ))
            }
            if let reminder = reminderToInject(
                voiceSentThisTurn: voiceSentThisTurn,
                toolCallsSinceVoice: toolCallsSinceVoice,
                reminded: reminded
            ) {
                reminded.insert(reminder)
                messages.append(ChatMessage(
                    id: "\(reminderPrefix)\(reminder.rawValue)-\(newId())",
                    role: .user,
                    content: reminderText(reminder, voice: voice),
                    seq: messages.count,
                    createdAt: clock.nowMillis()
                ))
            }
        }

        // 轮次用尽时不能装作正常收束：把原因作为最后一段文本告诉用户。
        publish(.delta(KernelDeltaEvent(
            runId: params.runId,
            messageId: newId(),
            delta: roundLimitNotice,
            part: .text
        )))
        publish(.ended(KernelEndedEvent(runId: params.runId, status: .idle)))
    }

    private func resolveToolCall(
        _ params: TurnStartParams,
        turn: ActiveTurn,
        call: ToolCall,
        delegated: Set<String>,
        catalog: [ToolDefinition]
    ) async throws -> ResolvedTool {
        if delegated.contains(call.name) {
            let runId = params.runId
            let publish = self.publish
            let provided = try await turn.waitDelegation(id: call.id) {
                publish(.toolDelegate(KernelToolDelegateEvent(
                    runId: runId,
                    toolCallId: call.id,
                    toolName: call.name,
                    arguments: call.arguments
                )))
            }
            try Task.checkCancellation()
            if turn.isCancelRequested { throw CancellationError() }
            return ResolvedTool(ok: provided.ok, output: provided.output, endTurn: provided.endTurn)
        }
        guard let definition = catalog.first(where: { $0.name == call.name }) else {
            throw NuumError(code: KernelErrorCode.tool, message: "Unknown tool: \(call.name)")
        }
        guard let declared = definition.action else {
            throw NuumError(
                code: KernelErrorCode.tool,
                message: "Local tool \(call.name) does not declare a permission action"
            )
        }
        let requested = permissionRequest(
            toolName: call.name,
            action: declared,
            arguments: call.arguments,
            terminalsRoot: params.roots.terminals
        )
        let verdict = try await tools.authorize(runId: params.runId, action: requested.action, target: requested.target)
        if verdict.decision == .deny {
            let reason = verdict.reason ?? "Permission denied for \(requested.action.rawValue) \(verdict.target)"
            return ResolvedTool(ok: false, output: reason)
        }
        if verdict.decision == .ask {
            let runId = params.runId
            let publish = self.publish
            let pending = KernelToolPendingEvent(
                runId: runId,
                toolCallId: call.id,
                toolName: call.name,
                arguments: call.arguments,
                mutating: requested.action != .readFile && definition.mutating,
                action: requested.action,
                target: verdict.target
            )
            let resolution = try await turn.waitDecision(id: call.id) {
                publish(.toolPending(pending))
            }
            try Task.checkCancellation()
            if turn.isCancelRequested { throw CancellationError() }
            if resolution == .deny || resolution == .never {
                tools.refuse(runId: params.runId, action: requested.action, target: verdict.target)
                if resolution == .never {
                    tools.setPermission(runId: params.runId, permission: .never)
                }
                return ResolvedTool(ok: false, output: "User denied this tool call.")
            }
            // always 与 once 都只放行这一次。把 run 权限改成 always 不是 loop 的事。
            tools.grantOnce(runId: params.runId, action: requested.action, target: verdict.target)
        }
        publish(.toolStarted(KernelToolStartedEvent(
            runId: params.runId,
            toolCallId: call.id,
            toolName: call.name,
            arguments: call.arguments
        )))
        do {
            let executed = try await tools.execute(runId: params.runId, call: call)
            return ResolvedTool(
                ok: executed.ok,
                output: executed.output,
                images: executed.images,
                endTurn: executed.endTurn
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled || turn.isCancelRequested { throw CancellationError() }
            return ResolvedTool(ok: false, output: describe(error))
        }
    }

    private func definitions() -> [ToolDefinition] {
        if let toolDefinitions {
            return toolDefinitions()
        }
        guard let backend = tools as? any ToolBackend else { return [] }
        return backend.definitions()
    }
}

func runSummarize(model: any ModelPort, params: SummarizeRunParams, apiKey: String) async throws -> SummarizeRunResult {
    try Task.checkCancellation()
    let messages = [
        ChatMessage(id: "system", role: .system, content: params.systemPrompt, seq: 0, createdAt: 0),
    ] + params.messages
    let request = NormalizedChatRequest(
        model: params.model,
        messages: messages,
        tools: [],
        apiKey: apiKey,
        maxOutputTokens: params.maxOutputTokens ?? 2048
    )
    let streamTask = Task<SummarizeRunResult, Error> {
        var text = ""
        for try await chunk in model.streamChat(request) {
            try Task.checkCancellation()
            if case .text(let piece) = chunk {
                text += piece
            }
        }
        // 取消会让流结束成 nil，不能把半截摘要当成成功结果。
        try Task.checkCancellation()
        return SummarizeRunResult(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    let timeoutTask = Task {
        try await Task.sleep(nanoseconds: nanoseconds(fromMilliseconds: params.timeoutMs ?? 60_000))
        streamTask.cancel()
    }
    return try await withTaskCancellationHandler {
        let result = try await streamTask.value
        timeoutTask.cancel()
        return result
    } onCancel: {
        streamTask.cancel()
        timeoutTask.cancel()
    }
}

func apiKey(for secrets: Secrets, provider: ProviderId) throws -> String {
    let key: String?
    switch provider {
    case .openai:
        key = secrets.openaiApiKey
    case .anthropic:
        key = secrets.anthropicApiKey
    case .deepseek:
        key = secrets.deepseekApiKey
    }
    guard let key, !key.isEmpty else {
        throw NuumError(code: KernelErrorCode.invalid, message: "API key missing for \(provider.rawValue)")
    }
    return key
}

func outputCap(_ contextWindow: Int) -> Int {
    let scaled = Int((Double(contextWindow) * 0.1).rounded(.down))
    return max(1, min(4096, scaled))
}

/// ack（从未发声）→ result（发过声又埋头）→ silence（长静默），每轮至多一条。
func reminderToInject(
    voiceSentThisTurn: Bool,
    toolCallsSinceVoice: Int,
    reminded: Set<ReminderKind>
) -> ReminderKind? {
    if !voiceSentThisTurn && toolCallsSinceVoice > ackToolThreshold && !reminded.contains(.ack) {
        return .ack
    }
    if voiceSentThisTurn && toolCallsSinceVoice > resultToolThreshold && !reminded.contains(.result) {
        return .result
    }
    if toolCallsSinceVoice > silenceToolThreshold && !reminded.contains(.silence) {
        return .silence
    }
    return nil
}

func reminderText(_ kind: ReminderKind, voice: String) -> String {
    switch kind {
    case .ack:
        return "<system_reminder>You opened this turn by calling tools without first acknowledging the user, "
            + "so they are watching silence and may think the app froze. Call \(voice) right now — a real tool "
            + "call, not text you write — with a one-line acknowledgement before any further tool call, then continue the work.</system_reminder>"
    case .silence:
        return "<system_reminder>You have made several tool calls without a message, so the user is currently "
            + "watching silence. Call \(voice) now with a brief, specific update on what you are doing or what "
            + "you just found, then continue.</system_reminder>"
    case .result:
        return "<system_reminder>The user cannot see tool output or your thinking — only \(voice) reaches them. "
            + "If you have produced a result or finished what they asked, send it with \(voice) before continuing "
            + "or ending the turn; if you are still mid-task, keep working and send it once you have it.</system_reminder>"
    }
}

/// `shell` + `shell_id` 改判为读本 agent 的 terminal 文件。其余按参数里的路径或命令。
/// 真正的允许 / 询问 / 拒绝在 `ToolExecutor.authorize`。不读文件系统。
func permissionRequest(
    toolName: String,
    action: LocalToolAction,
    arguments: [String: JSONValue],
    terminalsRoot: String
) -> (action: LocalToolAction, target: String) {
    if toolName == "shell", let shellId = stringArgument(arguments, "shell_id") {
        return (.readFile, joinPath(terminalsRoot, "\(shellId).txt"))
    }
    if action == .runCommand {
        return (action, stringArgument(arguments, "command") ?? "")
    }
    for key in ["path", "target_directory", "working_directory"] {
        if let value = stringArgument(arguments, key), !value.isEmpty {
            return (action, value)
        }
    }
    return (action, ".")
}

func stringArgument(_ arguments: [String: JSONValue], _ key: String) -> String? {
    if case .string(let value) = arguments[key] { return value }
    return nil
}

func joinPath(_ root: String, _ child: String) -> String {
    if root.isEmpty || root == "." { return child }
    var trimmed = root
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    return trimmed + "/" + child
}

func describe(_ error: Error) -> String {
    if let control = error as? ControlError { return control.message }
    if let nuum = error as? NuumError { return nuum.message }
    return error.localizedDescription
}

func nanoseconds(fromMilliseconds milliseconds: Int64) -> UInt64 {
    let clamped = max(Int64(0), milliseconds)
    let limit = Int64(UInt64.max / 1_000_000)
    if clamped >= limit { return UInt64.max }
    return UInt64(clamped) * 1_000_000
}
