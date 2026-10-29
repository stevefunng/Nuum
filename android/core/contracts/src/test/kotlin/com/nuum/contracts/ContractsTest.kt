package com.nuum.contracts

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ContractsTest {
    @Test
    fun exceptionCarriesCodeAndMessage() {
        val error = NuumException(HostErrorCode.NO_API_KEY, "Add an API key in Settings")
        assertEquals(2004, error.code)
        assertEquals(HostErrorCode.NO_API_KEY, error.code)
        assertEquals("Add an API key in Settings", error.message)
        assertEquals(DesktopErrorCode.SECRET_STORE, 3001)
        assertEquals(KernelErrorCode.MODEL, 1004)
    }

    @Test
    fun hostEventNamesMatchTheMacContract() {
        assertEquals(
            setOf(
                "agent.updated",
                "agent.message.delta",
                "agent.message.completed",
                "agent.tool.pending",
                "agent.tool.started",
                "agent.tool.completed",
                "agent.error",
                "agent.ended",
                "work.updated",
                "work.event.appended",
                "work.catalog.updated",
                "proactive.updated",
                "settings.updated"
            ),
            HostEvents.ALL
        )
        assertFalse(HostEvents.ALL.contains("host.kernel.down"))
        val event = HostEvent.AgentError("a", "r", HostErrorCode.NO_API_KEY, "missing")
        assertEquals(HostEvents.AGENT_ERROR, event.name)
    }

    @Test
    fun pathsStayRelativeToTheNuumRoot() {
        assertEquals("agents/nunu/profile.json", NuumPaths.profilePath("nunu"))
        assertEquals("agents/nunu/transcript.jsonl", NuumPaths.transcriptPath("nunu"))
        assertEquals("agents/nunu/memory", NuumPaths.memoryDir("nunu"))
        assertEquals("works/room/timeline.jsonl", NuumPaths.workTimelinePath("room"))
        assertEquals("secrets.bin", NuumPaths.secretsFileName())
        assertFalse(NuumPaths.profilePath("nunu").startsWith("/"))
    }

    @Test
    fun defaultModelIdsMatchTheMacTable() {
        assertEquals("deepseek-chat", DEFAULT_MODEL_ID.getValue(ProviderId.DEEPSEEK))
        assertEquals("gpt-4o", DEFAULT_MODEL_ID.getValue(ProviderId.OPENAI))
        assertEquals("claude-sonnet-4-20250514", DEFAULT_MODEL_ID.getValue(ProviderId.ANTHROPIC))
        assertEquals(5, MAX_ATTACHMENTS)
        assertEquals(10 * 1024 * 1024, MAX_ATTACHMENT_BYTES)
        assertTrue(ProactiveSnapshot(null, emptyList(), emptyList()).actionsAvailable == false)
    }
}
