import Foundation
import NuumContracts

/// Wall clock for message timestamps. Tests inject a `Clock` of their own.
public struct SystemClock: Clock {
    public init() {}

    public func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

/// Foreground tasks that die with the process. A later supervisor can replace this
/// without putting background policy in the turn loop.
public struct InProcessTurnSupervisor: TurnSupervisor {
    public init() {}

    @discardableResult
    public func launch(_ block: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task { await block() }
    }
}

final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

/// Resumes a waiting host reply exactly once. Cancel and the reply can race.
final class ResumeBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var finished = false

    func register(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func succeed(_ value: T) {
        resume(.success(value))
    }

    func fail(_ error: Error) {
        resume(.failure(error))
    }

    private func resume(_ result: Result<T, Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
