package com.nuum.storage

import com.nuum.contracts.NuumPaths
import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProjectionRebuildTest : StorageRobolectricTest() {
    @Test
    fun deletedProjectionRebuildsTheAgentListFromProfileJson() = withStore { store ->
        store.writeTextAtomic(
            NuumPaths.profilePath("a1"),
            """{"id":"a1","name":"One","description":"hello","createdAt":1000,"tags":[" Research ","Research"],"avatarColor":"blue"}"""
        )
        store.writeTextAtomic(
            NuumPaths.agentSettingsPath("a1"),
            """{"model":{"provider":"deepseek","model":"deepseek-chat"},"hiddenFromSidebar":true}"""
        )
        store.appendLine(NuumPaths.transcriptPath("a1"), """{"type":"user","id":"u1","seq":1,"createdAt":9000,"text":"hi"}""")
        store.writeTextAtomic(
            NuumPaths.profilePath("a2"),
            """{"id":"a2","name":"Two","description":"","createdAt":2000}"""
        )

        assertEquals(listOf("a1", "a2"), store.agentList().map { it.id })
        val first = store.agentList().first()
        assertEquals("One", first.name)
        assertEquals("hello", first.description)
        assertEquals(listOf("Research"), first.tags)
        assertEquals("blue", first.avatarColor)
        assertTrue(first.hiddenFromSidebar)
        assertEquals(9000L, first.lastActivityAt)

        store.discardListProjection()
        assertTrue(store.agentList().isEmpty())

        store.rebuildListProjection()
        val rebuilt = store.agentList()
        assertEquals(listOf("a1", "a2"), rebuilt.map { it.id })
        assertEquals("One", rebuilt.first().name)
        assertEquals(9000L, rebuilt.first().lastActivityAt)
        assertEquals(2000L, rebuilt[1].lastActivityAt)
        assertTrue(rebuilt.first().hiddenFromSidebar)

        store.discardListProjection()
        store.open()
        assertEquals(listOf("a1", "a2"), store.agentList().map { it.id })
    }

    @Test
    fun workTasksRebuildFromTheTimelineAndATornLineIsNotATask() = withStore { store ->
        store.writeTextAtomic(
            NuumPaths.workProfilePath("w1"),
            """{"id":"w1","name":"Room","description":"d","projectRoot":null,"createdAt":10,"kind":"room"}"""
        )
        val created = """{"type":"task.created","id":"e1","workId":"w1","seq":1,"createdAt":50,"actor":{"kind":"agent","id":"a1"},"task":{"id":"t1","title":"Write spec","description":"","state":"proposed","assigneeIds":[],"revision":1,"updatedAt":50}}"""
        val transitioned = """{"type":"task.transitioned","id":"e2","workId":"w1","seq":2,"createdAt":80,"actor":{"kind":"user","id":"u"},"taskId":"t1","from":"proposed","to":"ready","revision":2}"""
        val chat = """{"type":"chat.posted","id":"e3","workId":"w1","seq":3,"createdAt":90,"actor":{"kind":"user","id":"u"},"messageId":"m1","body":"hello   room","mentionedAgentIds":[]}"""
        store.writeTextAtomic(
            NuumPaths.workTimelinePath("w1"),
            "$created\n$transitioned\n$chat\n"
        )
        File(store.root, NuumPaths.workTimelinePath("w1")).appendText(
            """{"type":"task.created","id":"e4","task":{"id":"t-torn""""
        )

        store.discardListProjection()
        store.rebuildListProjection()

        val work = store.workList().single()
        assertEquals("Room", work.name)
        assertEquals("room", work.kind)
        assertEquals(90L, work.lastActivityAt)
        assertEquals("hello room", work.preview)
        val task = store.taskList("w1").single()
        assertEquals("t1", task.taskId)
        assertEquals("Write spec", task.title)
        assertEquals("ready", task.state)
        assertEquals(2, task.revision)
        assertEquals("a1", task.ownerAgentId)
        assertEquals(80L, task.updatedAt)
        val timeline = store.readText(NuumPaths.workTimelinePath("w1"))!!
        assertFalse(timeline.contains("t-torn"))
    }

    @Test
    fun laterTaskEventsUpdateTheRowAndADeletedWorkDropsIt() = withStore { store ->
        store.writeTextAtomic(
            NuumPaths.workProfilePath("w1"),
            """{"id":"w1","name":"Room","description":"","projectRoot":null,"createdAt":10,"kind":"room"}"""
        )
        val timeline = NuumPaths.workTimelinePath("w1")
        store.appendLine(
            timeline,
            """{"type":"task.created","id":"e1","workId":"w1","seq":1,"createdAt":20,"actor":{"kind":"user","id":"u"},"task":{"id":"t1","title":"Write spec","description":"","state":"proposed","assigneeIds":[],"revision":1,"updatedAt":20}}"""
        )
        store.appendLine(
            timeline,
            """{"type":"task.transitioned","id":"e2","workId":"w1","seq":2,"createdAt":30,"actor":{"kind":"user","id":"u"},"taskId":"t1","from":"proposed","to":"ready","revision":2}"""
        )
        store.appendLine(
            timeline,
            """{"type":"task.claimed","id":"e3","workId":"w1","seq":3,"createdAt":40,"actor":{"kind":"agent","id":"a2"},"taskId":"t1","assigneeIds":["a2"],"revision":3,"messageId":"m","body":"mine"}"""
        )
        store.appendLine(
            timeline,
            """{"type":"task.assigned","id":"e4","workId":"w1","seq":4,"createdAt":41,"actor":{"kind":"user","id":"u"},"taskId":"t1","assigneeIds":["stale"],"revision":2}"""
        )
        store.appendLine(
            timeline,
            """{"type":"task.delegated","id":"e5","workId":"w1","seq":5,"createdAt":50,"actor":{"kind":"agent","id":"a1"},"taskId":"t1","agentId":"a3","instruction":"take it","revision":4,"messageId":"m2","membershipRevision":1}"""
        )
        store.appendLine(
            timeline,
            """{"type":"task.handed_off","id":"e6","workId":"w1","seq":6,"createdAt":60,"actor":{"kind":"agent","id":"a3"},"taskId":"t1","summary":"ready for review","deliverables":[],"nextStatus":"review","revision":5,"messageId":"m3"}"""
        )
        store.appendLine(
            timeline,
            """{"type":"task.transitioned","id":"e7","workId":"w1","seq":7,"createdAt":70,"actor":{"kind":"user","id":"u"},"taskId":"t1","from":"ready","to":"done","revision":6}"""
        )

        val task = store.taskList("w1").single()
        assertEquals("review", task.state)
        assertEquals(listOf("a2", "a3"), task.assigneeIds)
        assertEquals(5, task.revision)
        assertEquals(60L, task.updatedAt)
        assertEquals("ready for review", store.workList().single().preview)

        store.delete(NuumPaths.workDir("w1"))
        assertFalse(store.exists(NuumPaths.workProfilePath("w1")))
        assertTrue(store.workList().isEmpty())
        assertTrue(store.taskList("w1").isEmpty())
    }

    @Test
    fun markdownMemoryIsNotInterpreted() = withStore { store ->
        store.writeTextAtomic(
            NuumPaths.profilePath("a1"),
            """{"id":"a1","name":"One","description":"","createdAt":1000}"""
        )
        val memory = NuumPaths.memoryDir("a1") + "/profile.md"
        val markdown = "# Secret Name\n\nnot the profile name\n"
        store.writeTextAtomic(memory, markdown)
        assertEquals(markdown, store.readText(memory))
        assertEquals("One", store.agentList().single().name)
        assertEquals(listOf("profile.md"), store.list(NuumPaths.memoryDir("a1")))
        store.delete(memory)
        assertFalse(store.exists(memory))
        assertEquals("One", store.agentList().single().name)
        store.delete(NuumPaths.agentDir("a1"))
        assertFalse(store.exists(NuumPaths.profilePath("a1")))
        assertTrue(store.agentList().isEmpty())
    }

    @Test
    fun openCreatesTheMacDirectoryLayout() = withStore { store ->
        store.open()
        StoragePaths.topLevelDirectories.forEach { name ->
            assertTrue(File(store.root, name).isDirectory)
        }
        val marker = JSONObject(File(store.root, StoragePaths.migrationsPath()).readText())
        assertEquals(3, marker.getInt("version"))
        assertEquals(
            listOf("agents", "migrations.json", "work-sessions", "works", "workspaces"),
            store.root.list().orEmpty().sorted()
        )
    }

    @Test
    fun pathsCannotEscapeTheNuumRoot() = withStore { store ->
        store.writeTextAtomic("inside.txt", "safe")
        for (path in listOf("../outside.txt", "/etc/passwd", "agents/../../outside.txt")) {
            try {
                store.writeTextAtomic(path, "nope")
                throw AssertionError("expected $path to be rejected")
            } catch (error: com.nuum.contracts.NuumException) {
                assertEquals(com.nuum.contracts.KernelErrorCode.INVALID, error.code)
                assertFalse(error.message.contains("nope"))
            }
        }
        assertEquals("safe", store.readText("inside.txt"))
        assertEquals("agents/a1/profile.json", store.profilePath("a1"))
        assertEquals(NuumPaths.transcriptPath("a1"), store.transcriptPath("a1"))
    }
}
