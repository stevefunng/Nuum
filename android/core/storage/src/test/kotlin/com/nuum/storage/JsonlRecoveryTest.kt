package com.nuum.storage

import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NuumException
import com.nuum.contracts.NuumPaths
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JsonlRecoveryTest : StorageRobolectricTest() {
    @Test
    fun truncatedLastLineIsDroppedAndEarlierLinesStay() = withStore { store ->
        val relative = NuumPaths.transcriptPath("a1")
        val kept = """{"id":"u1","createdAt":1}"""
        val alsoKept = """{"id":"u2","createdAt":2}"""
        store.writeTextAtomic(relative, "$kept\n$alsoKept\n")
        File(store.root, relative).appendText("""{"id":"u3","createdAt":3,"te""")

        val lines = store.readJsonLines(relative)
        assertEquals(listOf(kept, alsoKept), lines)
        val raw = store.readText(relative)!!
        assertFalse(raw.contains("u3"))
        assertTrue(raw.endsWith("\n"))

        store.appendLine(relative, """{"id":"u4","createdAt":4}""")
        val after = store.readText(relative)!!
        assertEquals(
            listOf(kept, alsoKept, """{"id":"u4","createdAt":4}"""),
            after.split('\n').filter { it.isNotEmpty() }
        )
        assertFalse(after.contains("u3"))
        assertTrue(after.endsWith("\n"))
    }

    @Test
    fun aCompleteCorruptMiddleLineIsKept() = withStore { store ->
        val relative = "notes.jsonl"
        store.writeTextAtomic(relative, "one\n{not-json\nthree\n")
        assertEquals(listOf("one", "{not-json", "three"), store.readJsonLines(relative))
    }

    @Test
    fun aFileThatIsOnlyAPartialLineBecomesEmpty() = withStore { store ->
        val relative = "notes.jsonl"
        store.writeTextAtomic(relative, """{"id":"torn"""")
        assertEquals(emptyList<String>(), store.readJsonLines(relative))
        assertEquals("", store.readText(relative))
        store.appendLine(relative, """{"id":"fresh","createdAt":1}""")
        assertEquals(listOf("""{"id":"fresh","createdAt":1}"""), store.readJsonLines(relative))
    }

    @Test
    fun readTailStartsOnALineBoundary() = withStore { store ->
        val relative = "notes.jsonl"
        store.writeTextAtomic(relative, "aaaa\nbbbb\ncccc\n")
        assertEquals("bbbb\ncccc\n", store.readTail(relative, 10))
        assertEquals("aaaa\nbbbb\ncccc\n", store.readTail(relative, 100))
        assertEquals("", store.readTail(relative, 0))
    }

    @Test
    fun embeddedNewlinesAreRejected() = withStore { store ->
        try {
            store.appendLine("notes.jsonl", "one\ntwo")
            throw AssertionError("expected a newline to be rejected")
        } catch (error: NuumException) {
            assertEquals(KernelErrorCode.INVALID, error.code)
            assertFalse(store.exists("notes.jsonl"))
        }
    }
}
