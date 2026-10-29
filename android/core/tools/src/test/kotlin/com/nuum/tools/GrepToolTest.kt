package com.nuum.tools

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GrepToolTest {
    @Test
    fun grepMapsModesCaseAndResultWindows() {
        val item = fixture()
        item.files.mkdir("${item.project}/src")
        item.files.seed("${item.project}/src/one.ts", "Alpha\nsecond\nalpha")
        item.files.seed("${item.project}/src/two.txt", "alpha")

        val content = item.run(
            "grep",
            mapOf(
                "pattern" to "alpha",
                "path" to item.project,
                "glob" to "*.ts",
                "-i" to true,
                "output_mode" to "content",
                "head_limit" to 2,
                "offset" to 1
            )
        )
        assertTrue(content.ok)
        assertTrue(content.output.contains("one.ts"))
        assertTrue(content.output.contains("alpha"))
        assertEquals(1, content.output.split('\n').size)

        val files = item.run(
            "grep",
            mapOf("pattern" to "alpha", "path" to item.project, "output_mode" to "files_with_matches")
        )
        assertTrue(files.output.contains("one.ts"))
        assertTrue(files.output.contains("two.txt"))

        val counts = item.run(
            "grep",
            mapOf("pattern" to "alpha", "path" to item.project, "output_mode" to "count", "-i" to true)
        )
        assertTrue(counts.output.contains("one.ts:2"))
        assertTrue(counts.output.contains("two.txt:1"))

        assertEquals(
            "No matches found.",
            item.run("grep", mapOf("pattern" to "does-not-exist", "path" to item.project)).output
        )
        val rejected = item.run("grep", mapOf("pattern" to "x", "output_mode" to "everything"))
        assertFalse(rejected.ok)
        assertTrue(rejected.output.contains("output_mode must be one of"))
        val missing = item.run("grep", mapOf("pattern" to "x", "path" to "${item.project}/missing"))
        assertFalse(missing.ok)
        assertTrue(missing.output.contains("No such file"))
    }

    @Test
    fun grepContextAndTypeStayInsideTheFileTree() {
        val item = fixture()
        item.files.seed("${item.project}/src/Main.kt", "before\nhit\nafter\n")
        item.files.seed("${item.project}/src/Main.java", "hit")
        val output = item.run(
            "grep",
            mapOf(
                "pattern" to "hit",
                "path" to item.project,
                "type" to "kt",
                "-A" to 1,
                "-B" to 1
            )
        ).output
        assertTrue(output.contains("before"))
        assertTrue(output.contains("hit"))
        assertTrue(output.contains("after"))
        assertFalse(output.contains(".java"))
    }

    @Test
    fun grepCapsOutputWithoutCallingAnExternalProgram() {
        val item = fixture()
        val line = "hit " + "x".repeat(200)
        val body = buildString {
            repeat(4_000) {
                append(line)
                append('\n')
            }
        }
        item.files.seed("${item.project}/wide.txt", body)
        val output = item.run("grep", mapOf("pattern" to "hit", "path" to item.project)).output
        val marker = "[rg output truncated; narrow the pattern, glob, or result range.]"
        assertTrue(output.contains(marker))
        assertTrue(output.length > MAX_GREP_OUTPUT)
        assertTrue(output.length <= MAX_GREP_OUTPUT + marker.length + 1)
        assertFalse(output.contains("ripgrep failed"))
    }
}
