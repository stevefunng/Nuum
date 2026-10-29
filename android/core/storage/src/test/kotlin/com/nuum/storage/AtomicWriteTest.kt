package com.nuum.storage

import java.io.File
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AtomicWriteTest : StorageRobolectricTest() {
    @Test
    fun failureBeforeReplaceKeepsThePreviousFile() {
        val gate = CommitGate()
        withStore(beforeCommit = gate::checkpoint) { store ->
            val relative = "agents/a1/profile.json"
            val original = """{"id":"a1","name":"Old","description":"","createdAt":1}"""
            val replacement = """{"id":"a1","name":"New","description":"","createdAt":1}"""
            store.writeTextAtomic(relative, original)
            assertEquals("Old", store.agentList().single().name)

            gate.armed = true
            try {
                store.writeTextAtomic(relative, replacement)
                throw AssertionError("expected the replace to fail")
            } catch (error: IOException) {
                assertTrue(error.message!!.contains("before replace"))
            }

            assertEquals(original, store.readText(relative))
            assertEquals(original, store.readBytes(relative)!!.toString(Charsets.UTF_8))
            assertEquals("Old", store.agentList().single().name)
            val directory = File(store.root, "agents/a1")
            assertTrue(directory.list().orEmpty().none { it.contains(".tmp") })
            assertFalse(store.root.walkTopDown().any { it.name.contains(".tmp") })
        }
    }
}

private class CommitGate {
    var armed: Boolean = false

    fun checkpoint() {
        if (!armed) return
        armed = false
        throw IOException("atomic write failed before replace")
    }
}
