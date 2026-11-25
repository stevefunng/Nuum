import Foundation
import Testing
@testable import NuumAgent
import NuumProtocol

@Test func globalCapIsThreeAndSameAgentDoesNotOverlap() async {
    let scheduler = AgentScheduler(supervisor: ScopeSupervisor(), newRunId: countingIds())
    let started = LockedList()
    func request(_ agent: String) -> AgentScheduler.RunRequest {
        AgentScheduler.RunRequest(agentId: agent, context: .direct) { runId in
            started.add("\(agent):\(runId)")
        }
    }
    #expect(scheduler.submit(request("a")).state == .started)
    #expect(scheduler.submit(request("b")).state == .started)
    #expect(scheduler.submit(request("c")).state == .started)
    #expect(scheduler.submit(request("d")).state == .queued)
    await waitUntil { started.values.count >= 3 }
    #expect(started.values == ["a:r1", "b:r2", "c:r3"])
    #expect(scheduler.submit(request("a")).state == .queued)
    scheduler.settle("r1")
    await waitUntil { started.values.count >= 4 }
    let names = started.values
    #expect(names.contains("d:r4") || names.contains("a:r5"))
    #expect(scheduler.activeCount() == 3)
}

@Test func nestedProjectRootsDoNotRunTogether() {
    let scheduler = AgentScheduler(supervisor: ScopeSupervisor(), newRunId: countingIds())
    let first = scheduler.submit(AgentScheduler.RunRequest(agentId: "a", context: .direct, projectRoot: "/work/app") { _ in })
    let second = scheduler.submit(AgentScheduler.RunRequest(agentId: "b", context: .direct, projectRoot: "/work/app/module") { _ in })
    #expect(first.state == .started)
    #expect(second.state == .queued)
}

@Test func hopRateAndCreateLimits() {
    let queue = WakeQueue { 1_000_000 }
    #expect(queue.check(fromId: "a", toId: "a", hops: 1).reason != nil)
    if case .allowed = queue.check(fromId: "a", toId: "b", hops: maxHops) {} else {
        Issue.record("hop \(maxHops) should be allowed")
    }
    if case .refused = queue.check(fromId: "a", toId: "c", hops: maxHops + 1) {} else {
        Issue.record("hop past the cap should be refused")
    }
    for _ in 0..<(wakeRateLimit - 1) {
        if case .allowed = queue.check(fromId: "a", toId: "b", hops: 1) {} else {
            Issue.record("rate window should still allow")
        }
    }
    if case .refused = queue.check(fromId: "a", toId: "b", hops: 1) {} else {
        Issue.record("rate limit should refuse")
    }
    if case .allowed = queue.check(fromId: "a", toId: "d", hops: 1) {} else {
        Issue.record("a different pair should be allowed")
    }
    #expect(queue.claimCreate("run-1"))
    #expect(!queue.claimCreate("run-1"))
    #expect(queue.claimCreate("run-2"))
    queue.closeRun("run-1")
    #expect(queue.claimCreate("run-1"))
}

@Test func pendingWakeIgnoresAnsweredAndUserTurns() {
    let wake = TranscriptEvent.wake(
        id: "w", seq: 1, createdAt: 1, source: .agent(fromId: "a2", fromName: "Scout", priority: false), text: "check", hops: 2
    )
    #expect(pendingWake([wake])?.hops == 2)
    let user = TranscriptEvent.user(id: "u", seq: 2, createdAt: 2, text: "here", attachments: nil, widgetAnswerTo: nil)
    #expect(pendingWake([wake, user]) == nil)
    #expect(currentHops([wake, user]) == 0)
}

@Test func dedupeAndProfileCap() async throws {
    let store = MemoryAgentStore()
    let clock = ManualClock()
    let memory = MemoryStore(store: store, memoryDir: "agents/a/memory", clock: clock)
    #expect(try await memory.write(fact: "The user prefers pnpm.", tier: .profile).written)
    #expect(try await memory.write(fact: "the user prefers pnpm", tier: .profile).written == false)
    #expect(try await memory.write(fact: "The user prefers pnpm", tier: .log).written == false)
    #expect(try await memory.all().count == 1)
    for index in 0..<(profileFactLimit - 1) {
        #expect(try await memory.write(fact: "standing fact \(index)", tier: .profile).written)
    }
    #expect(try await memory.write(fact: "one fact too many", tier: .profile).written == false)
    #expect(try await memory.all().filter { $0.tier == .profile }.count == profileFactLimit)
    let rendered = renderMemory(try await memory.all(), memoryDir: "/data/memory", nowMillis: clock.nowMillis())
    #expect(rendered.contains("The user prefers pnpm"))
    #expect(!rendered.contains("one fact too many"))
}

@Test func limitsRotationAndSilentRound() async throws {
    #expect(discussionLimits.rounds == 3)
    #expect(discussionLimits.messages == 10)
    #expect(discussionLimits.perTurn == 2)
    #expect(orderSpeakers(["a", "b"], round: 1) == ["b", "a"])
    #expect(isPass(" (pass). "))
    let members = [DiscussionMember(id: "a", name: "Alice Smith"), DiscussionMember(id: "b", name: "Bob")]
    let responders = try discussionResponders(members, [MentionedMessage(body: "@BOB check", mentionedAgentIds: [])])
    #expect(responders.map(\.id) == ["b"])
    let calls = LockedList()
    try await runDiscussion(
        current: { true },
        responders: { ["a", "b"] },
        runMember: { id in
            calls.add(id)
            return MemberTurn(messages: calls.values.count == 1 ? 1 : 0, failed: id == "b")
        }
    )
    #expect(calls.values == ["a", "b", "a"])
}

@Test func blockedReturnsOnlyForTheUser() {
    #expect(taskAllowed(from: .inProgress, role: .worker, to: .blocked))
    #expect(!taskAllowed(from: .blocked, role: .worker, to: .inProgress))
    #expect(taskAllowed(from: .blocked, role: .user, to: .inProgress))
}

@Test func cardSessionHashMatchesTheMacPayload() {
    #expect(sha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(sha256Hex("hello") == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    let session = cardSession(workId: "room-1", taskId: "task-1", agentId: "agent-1", membershipRevision: 2)
    #expect(session.id == "082a03f3b2161cb9b2458ce6d5c42251c3d4a57a242d581d33f83308adc4fd4e")
    #expect(cardSessionDir(session) == "work-sessions/2cb5ddf410150fdff33e0d2840a0481f82a53303884c6f616df48103e67bc74b/\(session.id)")
}

private func taskAllowed(from: NuumProtocol.WorkTaskState, role: TaskActorRole, to: NuumProtocol.WorkTaskState) -> Bool {
    do {
        try assertTaskTransition(from: from, to: to, role: role)
        return true
    } catch {
        return false
    }
}

private func countingIds() -> @Sendable () -> String {
    let box = LockedCounter()
    return { box.next("r") }
}

final class LockedList: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
    func add(_ value: String) {
        lock.lock()
        items.append(value)
        lock.unlock()
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next(_ prefix: String) -> String {
        lock.lock()
        value += 1
        let current = value
        lock.unlock()
        return "\(prefix)\(current)"
    }
}
