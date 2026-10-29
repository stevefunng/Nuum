package com.nuum.storage

import com.nuum.contracts.NuumPaths
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class StoragePathsTest {
    @Test
    fun sharedPathsMatchTheMacRelativeLayout() {
        assertEquals("settings.json", StoragePaths.settingsPath())
        assertEquals("migrations.json", StoragePaths.migrationsPath())
        assertEquals("agents/nunu/profile.json", StoragePaths.profilePath("nunu"))
        assertEquals("agents/nunu/settings.json", StoragePaths.agentSettingsPath("nunu"))
        assertEquals("agents/nunu/transcript.jsonl", StoragePaths.transcriptPath("nunu"))
        assertEquals("agents/nunu/read-cursor.json", StoragePaths.readCursorPath("nunu"))
        assertEquals("agents/nunu/tool-approvals.json", StoragePaths.toolApprovalsPath("nunu"))
        assertEquals("agents/nunu/prompt-cache.json", StoragePaths.promptCachePath("nunu"))
        assertEquals("agents/nunu/memory", StoragePaths.memoryDir("nunu"))
        assertEquals("agents/nunu/scratch", StoragePaths.scratchDir("nunu"))
        assertEquals("agents/nunu/terminals", StoragePaths.terminalsDir("nunu"))
        assertEquals("works/room/profile.json", StoragePaths.workProfilePath("room"))
        assertEquals("works/room/catalog.json", StoragePaths.workCatalogPath("room"))
        assertEquals("works/room/timeline.jsonl", StoragePaths.workTimelinePath("room"))
        assertEquals("workspaces/abc.json", StoragePaths.workspaceRecordPath("abc"))
        assertEquals("workspaces/abc", StoragePaths.managedWorkspaceDir("abc"))
        assertEquals("secrets.bin", StoragePaths.secretsFileName())
        assertEquals(NuumPaths.profilePath("nunu"), StoragePaths.profilePath("nunu"))
        assertEquals(NuumPaths.transcriptPath("nunu"), StoragePaths.transcriptPath("nunu"))
        assertFalse(StoragePaths.profilePath("nunu").startsWith("/"))
        assertFalse(StoragePaths.workTimelinePath("room").contains('\\'))
        assertEquals(3, StoragePaths.MIGRATION_VERSION)
        assertEquals(64 * 1024, StoragePaths.TAIL_WINDOW_BYTES)
    }

    @Test
    fun workSessionPathsUseTheMacSha256Rules() {
        assertEquals(
            "[\"room-1\",\"task-1\",\"agent-1\",2]",
            StoragePaths.cardSessionPayload("room-1", "task-1", "agent-1", 2)
        )
        assertEquals(
            "[\"a\\\"b\",\"c\\\\d\",\"e\",4]",
            StoragePaths.cardSessionPayload("a\"b", "c\\d", "e", 4)
        )
        assertEquals(
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
            StoragePaths.sha256Hex("hello")
        )
        assertEquals(
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
            StoragePaths.workspaceIdForOwner("hello")
        )
        assertEquals(
            "workspaces/2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824.json",
            StoragePaths.workspaceRecordPathForOwner("hello")
        )
        val room = "2cb5ddf410150fdff33e0d2840a0481f82a53303884c6f616df48103e67bc74b"
        val session = "082a03f3b2161cb9b2458ce6d5c42251c3d4a57a242d581d33f83308adc4fd4e"
        assertEquals("work-sessions/$room/$session", StoragePaths.workSessionDir("room-1", "task-1", "agent-1", 2))
        assertEquals(
            "work-sessions/$room/$session/session.json",
            StoragePaths.workSessionRecordPath("room-1", "task-1", "agent-1", 2)
        )
        assertEquals(
            "work-sessions/$room/$session/transcript.jsonl",
            StoragePaths.workSessionTranscriptPath("room-1", "task-1", "agent-1", 2)
        )
        assertEquals(
            StoragePaths.workSessionDir("room-1", "task-1", "agent-1", 2),
            FileAgentStore.workSessionDir("room-1", "task-1", "agent-1", 2)
        )
        assertEquals("migrations.json", FileAgentStore.migrationsPath())
    }
}
