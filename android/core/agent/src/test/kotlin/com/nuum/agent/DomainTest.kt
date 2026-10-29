package com.nuum.agent

import com.nuum.protocol.TranscriptEvent
import com.nuum.protocol.WakeSource
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SchedulerTest {
    @Test
    fun globalCapIsThreeAndSameAgentDoesNotOverlap() = runBlocking {
        val scheduler = AgentScheduler(supervisor = ScopeSupervisor(), newRunId = countingIds())
        val started = mutableListOf<String>()
        fun request(agent: String) = AgentScheduler.RunRequest(agent, RunContext.Direct) { runId ->
            started += "$agent:$runId"
        }
        assertEquals(RunState.STARTED, scheduler.submit(request("a")).state)
        assertEquals(RunState.STARTED, scheduler.submit(request("b")).state)
        assertEquals(RunState.STARTED, scheduler.submit(request("c")).state)
        assertEquals(RunState.QUEUED, scheduler.submit(request("d")).state)
        kotlinx.coroutines.yield()
        assertEquals(listOf("a:r1", "b:r2", "c:r3"), started)
        assertEquals(RunState.QUEUED, scheduler.submit(request("a")).state)
        scheduler.settle("r1")
        kotlinx.coroutines.yield()
        assertTrue(started.contains("d:r4") || started.contains("a:r5"))
        assertEquals(3, scheduler.activeCount())
    }

    @Test
    fun nestedProjectRootsDoNotRunTogether() = runBlocking {
        val scheduler = AgentScheduler(supervisor = ScopeSupervisor(), newRunId = countingIds())
        val first = scheduler.submit(AgentScheduler.RunRequest("a", RunContext.Direct, "/work/app") { })
        val second = scheduler.submit(AgentScheduler.RunRequest("b", RunContext.Direct, "/work/app/module") { })
        assertEquals(RunState.STARTED, first.state)
        assertEquals(RunState.QUEUED, second.state)
    }
}

class WakeTest {
    @Test
    fun hopRateAndCreateLimits() {
        val queue = WakeQueue { 1_000_000 }
        assertTrue(queue.check("a", "a", 1) is WakeVerdict.Refused)
        assertTrue(queue.check("a", "b", MAX_HOPS) is WakeVerdict.Allowed)
        assertTrue(queue.check("a", "c", MAX_HOPS + 1) is WakeVerdict.Refused)
        repeat(WAKE_RATE_LIMIT - 1) { assertTrue(queue.check("a", "b", 1) is WakeVerdict.Allowed) }
        assertTrue(queue.check("a", "b", 1) is WakeVerdict.Refused)
        assertTrue(queue.check("a", "d", 1) is WakeVerdict.Allowed)
        assertTrue(queue.claimCreate("run-1"))
        assertFalse(queue.claimCreate("run-1"))
        assertTrue(queue.claimCreate("run-2"))
        queue.closeRun("run-1")
        assertTrue(queue.claimCreate("run-1"))
    }

    @Test
    fun pendingWakeIgnoresAnsweredAndUserTurns() {
        val wake = TranscriptEvent.Wake("w", 1, 1, WakeSource.Agent("a2", "Scout", false), "check", 2)
        assertEquals(2, pendingWake(listOf(wake))?.hops)
        assertNull(pendingWake(listOf(wake, TranscriptEvent.User("u", 2, 2, "here"))))
        assertEquals(0, currentHops(listOf(wake, TranscriptEvent.User("u", 2, 2, "here"))))
    }
}

class MemoryRuleTest {
    @Test
    fun dedupeAndProfileCap() = runBlocking {
        val store = MemoryAgentStore()
        val clock = ManualClock()
        val memory = MemoryStore(store, "agents/a/memory", clock)
        assertTrue(memory.write("The user prefers pnpm.", MemoryTier.PROFILE).written)
        assertFalse(memory.write("the user prefers pnpm", MemoryTier.PROFILE).written)
        assertFalse(memory.write("The user prefers pnpm", MemoryTier.LOG).written)
        assertEquals(1, memory.all().size)
        repeat(PROFILE_FACT_LIMIT - 1) { index ->
            assertTrue(memory.write("standing fact $index", MemoryTier.PROFILE).written)
        }
        assertFalse(memory.write("one fact too many", MemoryTier.PROFILE).written)
        assertEquals(PROFILE_FACT_LIMIT, memory.all().count { it.tier == MemoryTier.PROFILE })
        val rendered = renderMemory(memory.all(), "/data/memory", clock.nowMillis())
        assertTrue(rendered.contains("The user prefers pnpm"))
        assertFalse(rendered.contains("one fact too many"))
    }
}

class DiscussionRuleTest {
    @Test
    fun limitsRotationAndSilentRound() = runBlocking {
        assertEquals(3, discussionLimits.rounds)
        assertEquals(10, discussionLimits.messages)
        assertEquals(2, discussionLimits.perTurn)
        assertEquals(listOf("b", "a"), orderSpeakers(listOf("a", "b"), 1))
        assertTrue(isPass(" (pass). "))
        val members = listOf(DiscussionMember("a", "Alice Smith"), DiscussionMember("b", "Bob"))
        assertEquals(listOf("b"), discussionResponders(members, listOf(MentionedMessage("@BOB check", emptyList()))).map { it.id })
        val calls = mutableListOf<String>()
        runDiscussion(
            current = { true },
            responders = { listOf("a", "b") },
            runMember = { id ->
                calls += id
                MemberTurn(messages = if (calls.size == 1) 1 else 0, failed = id == "b")
            }
        )
        assertEquals(listOf("a", "b", "a"), calls)
    }
}

class WorkPolicyTest {
    @Test
    fun blockedReturnsOnlyForTheUser() {
        assertTrue(WorkTaskStateAllowed(com.nuum.protocol.WorkTaskState.IN_PROGRESS, TaskActorRole.WORKER, com.nuum.protocol.WorkTaskState.BLOCKED))
        assertFalse(WorkTaskStateAllowed(com.nuum.protocol.WorkTaskState.BLOCKED, TaskActorRole.WORKER, com.nuum.protocol.WorkTaskState.IN_PROGRESS))
        assertTrue(WorkTaskStateAllowed(com.nuum.protocol.WorkTaskState.BLOCKED, TaskActorRole.USER, com.nuum.protocol.WorkTaskState.IN_PROGRESS))
    }
}

private fun WorkTaskStateAllowed(
    from: com.nuum.protocol.WorkTaskState,
    role: TaskActorRole,
    to: com.nuum.protocol.WorkTaskState
): Boolean = try {
    assertTaskTransition(from, to, role)
    true
} catch (_: IllegalArgumentException) {
    false
}

private fun countingIds(): () -> String {
    var n = 0
    return { "r${++n}" }
}
