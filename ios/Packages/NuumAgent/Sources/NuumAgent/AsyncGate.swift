import Foundation
import NuumContracts

/// One-shot result that can be completed from another task.
final class AsyncGate<Success: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Success, Error>?
    private var waiters: [CheckedContinuation<Success, Error>] = []

    func complete(_ value: Success) {
        resume(.success(value))
    }

    func fail(_ error: Error) {
        resume(.failure(error))
    }

    func wait() async throws -> Success {
        if let existing = current() {
            return try existing.get()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Success, Error>) in
                if let existing = register(continuation) {
                    continuation.resume(with: existing)
                }
            }
        } onCancel: {
            self.fail(CancellationError())
        }
    }

    private func current() -> Result<Success, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }

    private func register(_ continuation: CheckedContinuation<Success, Error>) -> Result<Success, Error>? {
        lock.lock()
        defer { lock.unlock() }
        if let result { return result }
        waiters.append(continuation)
        return nil
    }

    private func resume(_ next: Result<Success, Error>) {
        lock.lock()
        if result != nil {
            lock.unlock()
            return
        }
        result = next
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        for waiter in pending {
            waiter.resume(with: next)
        }
    }
}

final class HostEventBus: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<HostEvent>.Continuation] = [:]

    func stream() -> AsyncStream<HostEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    func emit(_ event: HostEvent) {
        lock.lock()
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets {
            continuation.yield(event)
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}
