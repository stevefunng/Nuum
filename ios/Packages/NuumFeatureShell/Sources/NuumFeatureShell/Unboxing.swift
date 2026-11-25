import Foundation

enum UnboxingPackage: String, Equatable, CaseIterable, Sendable {
    case softTray = "soft-tray"
    case paperFold = "paper-fold"
    case roundBox = "round-box"
}

func rollUnboxingPackage<R: RandomNumberGenerator>(using random: inout R) -> UnboxingPackage {
    let index = min(2, Int.random(in: 0..<3, using: &random))
    return UnboxingPackage.allCases[index]
}

/// `--nuum-easing-out-strong`: cubic-bezier(0.165, 0.84, 0.44, 1).
func easeOutStrong(_ fraction: Double) -> Double {
    if fraction <= 0 { return 0 }
    if fraction >= 1 { return 1 }
    var low = 0.0
    var high = 1.0
    var t = fraction
    for _ in 0..<16 {
        t = (low + high) / 2
        let x = cubicBezier(t, 0.165, 0.44)
        if x < fraction { low = t } else { high = t }
    }
    return cubicBezier(t, 0.84, 1)
}

func cubicBezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
    let u = 1 - t
    return (3 * u * u * t * p1) + (3 * u * t * t * p2) + (t * t * t)
}

struct UnboxPlayback: Equatable, Sendable {
    var registersClock: Bool
    var packagingOpacity: Double
    var avatarScale: Double
    var settled: Bool
    var showsPackaging: Bool
    var package: UnboxingPackage?
}

func sampleUnbox(reducedMotion: Bool, elapsedMillis: Int, package: UnboxingPackage?) -> UnboxPlayback {
    if reducedMotion {
        return UnboxPlayback(
            registersClock: false,
            packagingOpacity: 0,
            avatarScale: 1,
            settled: true,
            showsPackaging: false,
            package: package
        )
    }
    let clamped = min(1_500, max(0, elapsedMillis))
    let eased = easeOutStrong(Double(clamped) / 1_500)
    let settled = clamped >= 1_500
    let opacity = settled ? 0 : (1 - eased)
    let scale = settled ? 1 : (0.92 + 0.08 * eased)
    return UnboxPlayback(
        registersClock: true,
        packagingOpacity: opacity,
        avatarScale: scale,
        settled: settled,
        showsPackaging: !settled && opacity > 0.001,
        package: package
    )
}

struct UnboxModel: Equatable, Sendable {
    var reducedMotion = true
    var package: UnboxingPackage = .softTray
    var startedAt: Date?
    var clockRegistrations = 0
    var armed = false

    mutating func begin(reducedMotion: Bool, package: UnboxingPackage, now: Date = Date()) {
        self.reducedMotion = reducedMotion
        self.package = package
        armed = true
        if reducedMotion {
            startedAt = nil
            return
        }
        clockRegistrations += 1
        startedAt = now
    }

    func playback(at date: Date) -> UnboxPlayback {
        guard armed else {
            return UnboxPlayback(
                registersClock: false,
                packagingOpacity: 0,
                avatarScale: 1,
                settled: true,
                showsPackaging: false,
                package: nil
            )
        }
        if reducedMotion {
            return sampleUnbox(reducedMotion: true, elapsedMillis: 0, package: package)
        }
        let elapsed = startedAt.map { Int((date.timeIntervalSince($0) * 1000).rounded(.down)) } ?? 0
        return sampleUnbox(reducedMotion: false, elapsedMillis: elapsed, package: package)
    }
}

func greetScale(reducedMotion: Bool, expanded: Bool) -> Double {
    if reducedMotion || !expanded { return 1 }
    return 1.04
}
