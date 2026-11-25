import Foundation
import NuumContracts

/// In-process run scheduling. A run id is process-local and is not a resume cursor.
/// Global cap is `maxConcurrent`. One agent has one active run. Nested project roots
/// do not run together.
final class AgentScheduler: @unchecked Sendable {
    struct RunRequest: Sendable {
        var agentId: String
        var context: RunContext
        var projectRoot: String?
        var start: @Sendable (String) async throws -> Void

        init(
            agentId: String,
            context: RunContext,
            projectRoot: String? = nil,
            start: @escaping @Sendable (String) async throws -> Void
        ) {
            self.agentId = agentId
            self.context = context
            self.projectRoot = projectRoot
            self.start = start
        }
    }

    private final class Scheduled: @unchecked Sendable {
        let request: RunRequest
        let runId: String
        let projectRoot: String?
        let completed: AsyncGate<RunOutcome>

        init(request: RunRequest, runId: String, projectRoot: String?, completed: AsyncGate<RunOutcome>) {
            self.request = request
            self.runId = runId
            self.projectRoot = projectRoot
            self.completed = completed
        }
    }

    private let supervisor: any TurnSupervisor
    private let maxConcurrent: Int
    private let newRunId: @Sendable () -> String
    private let lock = NSLock()
    private var active: [String: Scheduled] = [:]
    private var activeOrder: [String] = []
    private var pending: [Scheduled] = []
    private var jobs: [String: Task<Void, Never>] = [:]

    init(
        supervisor: any TurnSupervisor,
        maxConcurrent: Int = defaultMaxConcurrentRuns,
        newRunId: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.supervisor = supervisor
        self.maxConcurrent = maxConcurrent
        self.newRunId = newRunId
    }

    func submit(_ request: RunRequest) -> SubmittedRun {
        let completed = AsyncGate<RunOutcome>()
        let scheduled = Scheduled(
            request: request,
            runId: newRunId(),
            projectRoot: request.projectRoot.map(canonicalRoot),
            completed: completed
        )
        lock.lock()
        let startNow = canStart(scheduled)
        if startNow {
            active[scheduled.runId] = scheduled
            activeOrder.append(scheduled.runId)
        } else {
            pending.append(scheduled)
        }
        lock.unlock()
        if startNow {
            let started = launch(scheduled)
            return SubmittedRun(runId: scheduled.runId, state: .started, started: started, completed: completed)
        }
        return SubmittedRun(runId: scheduled.runId, state: .queued, started: nil, completed: completed)
    }

    func settle(_ runId: String, _ status: RunOutcome = .completed) {
        var launching: [Scheduled] = []
        lock.lock()
        guard let run = active.removeValue(forKey: runId) else {
            lock.unlock()
            return
        }
        activeOrder.removeAll { $0 == runId }
        jobs.removeValue(forKey: runId)
        launching = pumpLocked()
        lock.unlock()
        run.completed.complete(status)
        for next in launching {
            _ = launch(next)
        }
    }

    /// Drops queued work for `agentId` and returns active run ids the kernel must cancel.
    func cancelAgent(_ agentId: String) -> [String] {
        var cancelling: [String] = []
        var tasks: [Task<Void, Never>] = []
        lock.lock()
        pending.removeAll { item in
            if item.request.agentId == agentId {
                item.completed.complete(.cancelled)
                return true
            }
            return false
        }
        cancelling = activeOrder.filter { active[$0]?.request.agentId == agentId }
        tasks = cancelling.compactMap { jobs[$0] }
        lock.unlock()
        tasks.forEach { $0.cancel() }
        return cancelling
    }

    func cancelQueued(_ runId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = pending.firstIndex(where: { $0.runId == runId }) else { return false }
        pending.remove(at: index).completed.complete(.cancelled)
        return true
    }

    func agentIdFor(_ runId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return active[runId]?.request.agentId ?? pending.first { $0.runId == runId }?.request.agentId
    }

    func contextFor(_ runId: String) -> RunContext? {
        lock.lock()
        defer { lock.unlock() }
        return active[runId]?.request.context ?? pending.first { $0.runId == runId }?.request.context
    }

    func activeRunFor(_ agentId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return activeOrder.first { active[$0]?.request.agentId == agentId }
    }

    func isBusy(_ agentId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if activeOrder.contains(where: { active[$0]?.request.agentId == agentId }) { return true }
        return pending.contains { $0.request.agentId == agentId }
    }

    func activeCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return active.count
    }

    func queueDepth() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    func close() {
        var tasks: [Task<Void, Never>] = []
        lock.lock()
        (pending + activeOrder.compactMap { active[$0] }).forEach { $0.completed.complete(.cancelled) }
        pending.removeAll()
        active.removeAll()
        activeOrder.removeAll()
        tasks = Array(jobs.values)
        jobs.removeAll()
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    private func canStart(_ candidate: Scheduled) -> Bool {
        if active.count >= maxConcurrent { return false }
        for runId in activeOrder {
            guard let run = active[runId] else { continue }
            if run.request.agentId == candidate.request.agentId { return false }
            if let left = run.projectRoot, let right = candidate.projectRoot,
               containsRoot(left, right) || containsRoot(right, left) {
                return false
            }
        }
        return true
    }

    private func launch(_ run: Scheduled) -> AsyncGate<Void> {
        let started = AsyncGate<Void>()
        let start = run.request.start
        let runId = run.runId
        let job = supervisor.launch {
            do {
                try await start(runId)
                started.complete(())
            } catch is CancellationError {
                started.fail(CancellationError())
                self.settle(runId, .cancelled)
            } catch {
                started.fail(error)
                self.settle(runId, .failed)
            }
        }
        lock.lock()
        jobs[runId] = job
        lock.unlock()
        return started
    }

    /// Skip a busy agent at the head so a free agent behind it can start.
    private func pumpLocked() -> [Scheduled] {
        var launching: [Scheduled] = []
        while active.count < maxConcurrent {
            guard let index = pending.firstIndex(where: { canStart($0) }) else { break }
            let next = pending.remove(at: index)
            active[next.runId] = next
            activeOrder.append(next.runId)
            launching.append(next)
        }
        return launching
    }
}

enum RunState: Sendable, Equatable {
    case started
    case queued
}

enum RunOutcome: Sendable, Equatable {
    case completed
    case failed
    case cancelled
}

struct SubmittedRun: Sendable {
    var runId: String
    var state: RunState
    var started: AsyncGate<Void>?
    var completed: AsyncGate<RunOutcome>
}

enum RunContext: Sendable, Equatable {
    case direct
    case work(
        workId: String,
        bridgeId: String? = nil,
        taskId: String? = nil,
        discussionId: String? = nil,
        membershipRevision: Int? = nil,
        instruction: String = "",
        inputAfterSeq: Int? = nil
    )
}

func canonicalRoot(_ root: String) -> String {
    URL(fileURLWithPath: root).standardizedFileURL.path
}

func containsRoot(_ parent: String, _ child: String) -> Bool {
    let base = canonicalRoot(parent)
    let other = canonicalRoot(child)
    if other == base { return true }
    let prefix = base.hasSuffix("/") ? base : base + "/"
    return other.hasPrefix(prefix)
}
