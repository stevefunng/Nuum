import Foundation

final class LockedGenerator<G: RandomNumberGenerator>: @unchecked Sendable {
    private let lock = NSLock()
    private var generator: G

    init(_ generator: G) {
        self.generator = generator
    }

    func with<T>(_ body: (inout G) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&generator)
    }
}

final class AnyAppearanceRoller: @unchecked Sendable {
    private let lock = NSLock()
    private var appearanceRollsStorage = 0
    private var packageRollsStorage = 0
    private let appearanceBody: () -> RolledAppearance
    private let packageBody: () -> UnboxingPackage

    var appearanceRolls: Int {
        lock.lock()
        defer { lock.unlock() }
        return appearanceRollsStorage
    }

    var packageRolls: Int {
        lock.lock()
        defer { lock.unlock() }
        return packageRollsStorage
    }

    init<G: RandomNumberGenerator>(_ generator: G) {
        let box = LockedGenerator(generator)
        appearanceBody = { box.with { NuumFeatureShell.rollAppearance(using: &$0) } }
        packageBody = { box.with { rollUnboxingPackage(using: &$0) } }
    }

    func rollAppearance() -> RolledAppearance {
        lock.lock()
        appearanceRollsStorage += 1
        lock.unlock()
        return appearanceBody()
    }

    func rollPackage() -> UnboxingPackage {
        lock.lock()
        packageRollsStorage += 1
        lock.unlock()
        return packageBody()
    }
}
