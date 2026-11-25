import Foundation
import NuumContracts
import Testing
@testable import NuumFeatureSettings

@Test func proactiveTogglePauseAndCheckSendSnapshotFields() async {
    let clock = FakeClock(now: 5_000)
    let (model, port, _, _) = await makeProactive(
        proactiveSnapshot(agent: proactiveAgent(enabled: true, state: "waiting-context", revision: 7)),
        clock: clock
    )
    await model.pause(ProactivePause.thirtyMinutes)
    let paused = port.configures[0]
    #expect(paused.agentId == "agent-1")
    #expect(paused.expectedRevision == 7)
    #expect(paused.pausedUntil == 5_000 + ProactivePause.thirtyMinutes)
    #expect(await model.snapshot().snapshot?.agents.first?.state == "paused")

    await model.resume()
    let resumed = port.configures[1]
    #expect(resumed.resume)
    #expect(resumed.pausedUntil == nil)
    #expect(resumed.agentId == "agent-1")
    #expect(resumed.expectedRevision == 8)

    await model.check()
    #expect(port.checks == ["agent-1"])
}

@Test func failedConfigureDoesNotMoveTheSwitchAndRetryRepeatsTheCall() async {
    let initial = proactiveSnapshot(agent: proactiveAgent(enabled: false, state: "disabled", revision: 2))
    let (model, port, _, _) = await makeProactive(initial)
    port.failConfigure = true
    let enabled = proactiveSnapshot(agent: proactiveAgent(enabled: true, state: "waiting-context", revision: 99))
    port.onConfigure = { await model.accept(.proactiveUpdated(enabled)) }
    await model.toggle()
    let failed = await model.snapshot()
    #expect(failed.snapshot?.agents.first?.policy.enabled == false)
    #expect(failed.failed)
    let first = port.configures[0]
    #expect(first.enabled == true)
    #expect(first.resume)
    #expect(first.pausedUntil == nil)
    #expect(first.expectedRevision == 2)
    #expect(first.agentId == "agent-1")
    port.failConfigure = false
    port.onConfigure = nil
    await model.retry()
    #expect(port.configures.count == 2)
    #expect(port.configures[1] == first)
    #expect(await model.snapshot().snapshot?.agents.first?.policy.enabled == true)
    #expect(await model.snapshot().failed == false)
}

@Test func checkFailureRetriesTheSameAgentAndDoesNotStartAKeyTurn() async {
    let (model, port, _, _) = await makeProactive(
        proactiveSnapshot(agent: proactiveAgent(enabled: true, state: "ready", revision: 3))
    )
    port.failCheck = true
    await model.check()
    #expect(port.checks == ["agent-1"])
    #expect(await model.snapshot().failed)
    #expect(presentProactive(await model.snapshot(), language: .en).failureKey == "Could not update proactive mode.")
    port.failCheck = false
    await model.retry()
    #expect(port.checks == ["agent-1", "agent-1"])
    #expect(await model.snapshot().failed == false)
    #expect(port.configures.isEmpty)
}

@Test func agentActionsLabelComesFromTheSnapshotFlag() {
    #expect(agentActionsLabel(actionsAvailable: false) == .notConnected)
    #expect(agentActionsLabel(actionsAvailable: true) == .available)
    #expect(contextSourcesLabel([]) == .notConnected)
    #expect(contextSourcesLabel(["calendar"]) == .available)
}

@Test func pauseIsIgnoredWhileDisabledAndCheckIsIgnoredWhilePausedOrChecking() async {
    let (disabled, disabledPort, _, _) = await makeProactive(
        proactiveSnapshot(agent: proactiveAgent(enabled: false, state: "disabled"))
    )
    await disabled.pause(ProactivePause.oneHour)
    await disabled.check()
    #expect(disabledPort.configures.isEmpty)
    #expect(disabledPort.checks.isEmpty)

    let (paused, pausedPort, _, _) = await makeProactive(
        proactiveSnapshot(agent: proactiveAgent(enabled: true, state: "paused", pausedUntil: 9))
    )
    await paused.check()
    #expect(pausedPort.checks.isEmpty)

    let (checking, checkingPort, _, _) = await makeProactive(
        proactiveSnapshot(agent: proactiveAgent(enabled: true, state: "checking"))
    )
    await checking.check()
    #expect(checkingPort.checks.isEmpty)
}

@Test func missingAgentDisablesTheSwitchAndLoadFailureCanRetry() async {
    let (empty, _, _, _) = await makeProactive(proactiveSnapshot())
    await empty.toggle()
    let presented = presentProactive(await empty.snapshot(), language: .en)
    #expect(presented.phase == .empty)
    #expect(presented.title == "Nunu")
    #expect(!presented.switchEnabled)
    #expect(presented.footerKey == "Open Nuum")
    #expect(presented.footerAgentId == nil)

    let failing = FailingProactivePort()
    let model = ProactiveModel(settings: FakeSettingsPort(), proactive: failing, clock: FakeClock())
    await model.refresh()
    #expect(await model.snapshot().failed)
    #expect(await model.snapshot().loading == false)
    #expect(presentProactive(await model.snapshot(), language: .en).statusKey == "Connecting to Nuum…")
}

private final class FailingProactivePort: ProactivePort, @unchecked Sendable {
    let events: AsyncStream<HostEvent> = AsyncStream { _ in }
    func get() async throws -> ProactiveSnapshot {
        throw NuumError(code: 1, message: "proactive unavailable")
    }

    func configure(_ params: ProactiveConfigureParams) async throws -> ProactiveSnapshot {
        throw NuumError(code: 1, message: "proactive unavailable")
    }

    func check(agentId: String) async throws -> ProactiveSnapshot {
        throw NuumError(code: 1, message: "proactive unavailable")
    }
}
