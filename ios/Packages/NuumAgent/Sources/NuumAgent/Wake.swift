import Foundation
import NuumProtocol

struct QueuedWake: Sendable, Equatable {
    var fromId: String
    var fromName: String
    var text: String
    var hops: Int
}

/// The queue is memory only. A wake already lives in the recipient transcript.
/// After a restart, `pendingWake` finds one that never received a reply.
/// Cold start queues that wake and does not mark the agent running.
final class WakeQueue: @unchecked Sendable {
    private let now: @Sendable () -> Int64
    private let lock = NSLock()
    private var queued: [String: [QueuedWake]] = [:]
    private var rate: [String: [Int64]] = [:]
    private var creates: [String: Int] = [:]

    init(now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.now = now
    }

    func check(fromId: String, toId: String, hops: Int) -> WakeVerdict {
        lock.lock()
        defer { lock.unlock() }
        if fromId == toId {
            return .refused("That is you. Do the work yourself instead of messaging yourself.")
        }
        if hops > maxHops {
            return .refused(
                "Refused: this message is already \(hops - 1) agents away from the user. Answer it yourself instead of passing it on."
            )
        }
        let key = "\(fromId)>\(toId)"
        let cutoff = now() - wakeRateWindowMs
        var recent = rate[key] ?? []
        recent.removeAll { $0 < cutoff }
        if recent.count >= wakeRateLimit {
            rate[key] = recent
            return .refused(
                "Refused: you have already sent \(wakeRateLimit) messages to that agent this minute. Wait for it to answer."
            )
        }
        recent.append(now())
        rate[key] = recent
        return .allowed
    }

    func enqueue(toId: String, wake: QueuedWake) {
        lock.lock()
        defer { lock.unlock() }
        queued[toId, default: []].append(wake)
    }

    func dequeue(toId: String) -> QueuedWake? {
        lock.lock()
        defer { lock.unlock() }
        guard var queue = queued[toId], !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        if queue.isEmpty {
            queued.removeValue(forKey: toId)
        } else {
            queued[toId] = queue
        }
        return next
    }

    func drop(toId: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let dropped = queued[toId]?.count ?? 0
        queued.removeValue(forKey: toId)
        return dropped
    }

    func depth(toId: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return queued[toId]?.count ?? 0
    }

    func closeRun(_ runId: String) {
        lock.lock()
        defer { lock.unlock() }
        creates.removeValue(forKey: runId)
    }

    func claimCreate(_ runId: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let runId else { return true }
        let used = creates[runId] ?? 0
        if used >= maxCreatesPerRun { return false }
        creates[runId] = used + 1
        return true
    }
}

enum WakeVerdict: Sendable, Equatable {
    case allowed
    case refused(String)

    var reason: String? {
        if case .refused(let reason) = self { return reason }
        return nil
    }
}

/// An unanswered agent wake is the last wake with no later assistant, message, or user event.
/// User turns are not replayed on startup.
func pendingWake(_ events: [TranscriptEvent]) -> QueuedWake? {
    for event in events.reversed() {
        switch event {
        case .assistant, .message, .user:
            return nil
        case .wake(_, _, _, let source, let text, let hops):
            guard case .agent(let fromId, let fromName, _) = source else { return nil }
            return QueuedWake(fromId: fromId, fromName: fromName, text: text, hops: hops)
        default:
            continue
        }
    }
    return nil
}

/// Hops come from the transcript, so they survive a process restart.
func currentHops(_ events: [TranscriptEvent]) -> Int {
    for event in events.reversed() {
        switch event {
        case .user:
            return 0
        case .wake(_, _, _, _, _, let hops):
            return hops
        default:
            continue
        }
    }
    return 0
}
