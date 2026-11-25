import Foundation
import NuumContracts

/// In-process port of `packages/kernel/src/loop.ts` and Android `Kernel`.
///
/// The kernel only knows `runId`. It never sees an agent id. Tool IO goes
/// through `ToolExecutor` — this type does not touch the filesystem.
/// `events` is a single buffered stream and does not replay; collect it before `start`.
/// The caller passes `supervisor` so turn tasks stay on a lifetime the caller owns.
public final class Kernel: KernelPort, @unchecked Sendable {
    public let events: AsyncStream<KernelEvent>

    private let eventsContinuation: AsyncStream<KernelEvent>.Continuation
    private let model: any ModelPort
    private let tools: any ToolExecutor
    private let supervisor: any TurnSupervisor
    private let clock: any Clock
    private let newId: @Sendable () -> String
    private let toolDefinitions: (@Sendable () -> [ToolDefinition])?
    private let runs = Locked<[String: ActiveTurn]>([:])
    private let summaries = Locked<[String: SummarySlot]>([:])

    public init(
        model: any ModelPort,
        tools: any ToolExecutor,
        supervisor: any TurnSupervisor = InProcessTurnSupervisor(),
        clock: any Clock = SystemClock(),
        newId: @escaping @Sendable () -> String = { UUID().uuidString },
        toolDefinitions: (@Sendable () -> [ToolDefinition])? = nil
    ) {
        self.model = model
        self.tools = tools
        self.supervisor = supervisor
        self.clock = clock
        self.newId = newId
        self.toolDefinitions = toolDefinitions
        let (stream, continuation) = AsyncStream.makeStream(
            of: KernelEvent.self,
            bufferingPolicy: .unbounded
        )
        self.events = stream
        self.eventsContinuation = continuation
    }

    deinit {
        let turns = runs.withLock { state -> [ActiveTurn] in
            let values = Array(state.values)
            state.removeAll()
            return values
        }
        for turn in turns { turn.cancel() }
        let slots = summaries.withLock { state -> [SummarySlot] in
            let values = Array(state.values)
            state.removeAll()
            return values
        }
        for slot in slots { slot.cancel() }
        eventsContinuation.finish()
    }

    public func start(_ params: TurnStartParams) async throws {
        let turn = ActiveTurn()
        let inserted = runs.withLock { state -> Bool in
            if state[params.runId] != nil { return false }
            state[params.runId] = turn
            return true
        }
        guard inserted else {
            throw NuumError(
                code: KernelErrorCode.turnBusy,
                message: "Run \(params.runId) is already running"
            )
        }
        let continuation = eventsContinuation
        let engine = TurnEngine(
            model: model,
            tools: tools,
            clock: clock,
            newId: newId,
            toolDefinitions: toolDefinitions,
            publish: { event in
                continuation.yield(event)
            }
        )
        let runs = self.runs
        let runId = params.runId
        let task = supervisor.launch {
            await engine.run(params, turn: turn) {
                _ = runs.withLock { $0.removeValue(forKey: runId) }
            }
        }
        turn.store(task)
    }

    public func cancel(runId: String) async throws {
        runs.withLock { $0[runId] }?.cancel()
    }

    public func approveTool(_ decision: TurnToolDecision) async throws {
        try decide(runId: decision.runId, toolCallId: decision.toolCallId, resolution: decision.resolution)
    }

    public func denyTool(_ decision: TurnToolDecision) async throws {
        try decide(runId: decision.runId, toolCallId: decision.toolCallId, resolution: .deny)
    }

    public func provideContext(_ result: TurnContextResult) async throws {
        let turn = try requireRun(result.runId)
        turn.completeContext(id: result.requestId, result: result)
    }

    public func provideToolResult(_ result: TurnToolResult) async throws {
        let turn = try requireRun(result.runId)
        turn.completeDelegation(
            id: result.toolCallId,
            result: DelegatedResult(ok: result.ok, output: result.output, endTurn: result.endTurn)
        )
    }

    public func summarize(_ params: SummarizeRunParams) async throws -> SummarizeRunResult {
        let apiKey = try apiKey(for: params.secrets, provider: params.model.provider)
        let slot = SummarySlot()
        let inserted = summaries.withLock { state -> Bool in
            if state[params.runId] != nil { return false }
            state[params.runId] = slot
            return true
        }
        guard inserted else {
            throw NuumError(code: KernelErrorCode.invalid, message: "Summary already running")
        }
        defer {
            summaries.withLock { state in
                if state[params.runId] === slot {
                    state.removeValue(forKey: params.runId)
                }
            }
        }
        let model = self.model
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SummarizeRunResult, Error>) in
                let task = Task {
                    do {
                        let result = try await runSummarize(model: model, params: params, apiKey: apiKey)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                slot.store(task)
            }
        } onCancel: {
            slot.cancel()
        }
    }

    public func cancelSummary(runId: String) async throws {
        summaries.withLock { $0[runId] }?.cancel()
    }

    private func decide(runId: String, toolCallId: String, resolution: ToolResolution) throws {
        let turn = try requireRun(runId)
        turn.completeDecision(id: toolCallId, resolution: resolution)
    }

    private func requireRun(_ runId: String) throws -> ActiveTurn {
        guard let turn = runs.withLock({ $0[runId] }) else {
            throw NuumError(code: KernelErrorCode.invalid, message: "No running turn for \(runId)")
        }
        return turn
    }
}

final class SummarySlot: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancelRequested = false

    func store(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        let shouldCancel = cancelRequested
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelRequested = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}
