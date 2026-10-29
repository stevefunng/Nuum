package com.nuum.tools

import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NuumException
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FileToolTest {
    @Test
    fun readSupportsRangesLineNumbersAndEmptyFiles() {
        val item = fixture()
        val file = "${item.project}/lines.txt"
        item.files.seed(file, "alpha\nbeta\ngamma\ndelta")
        assertEquals(
            "2|beta\n3|gamma\n\n[Showing lines 2-3 of 4. 1 line remains.]",
            item.run(
                "read",
                mapOf("path" to file, "offset" to 2, "limit" to 2, "include_line_numbers" to true)
            ).output
        )
        assertEquals(
            "beta\n\n[Showing line 2 of 4. 2 lines remain.]",
            item.run("read", mapOf("path" to file, "offset" to 2, "limit" to 1)).output
        )
        val empty = "${item.project}/empty.txt"
        item.files.seed(empty, "")
        assertEquals("File is empty.", item.run("read", mapOf("path" to empty)).output)
        val rejected = item.run("read", mapOf("path" to file, "offset" to 0))
        assertFalse(rejected.ok)
        assertTrue(rejected.output.contains("offset must be an integer >= 1"))
    }

    @Test
    fun readTruncatesOversizedOutput() {
        val item = fixture()
        val file = "${item.project}/large.txt"
        val body = (1..5_000).joinToString("\n") { index -> "line-$index-${"x".repeat(20)}" }
        item.files.seed(file, body)
        val output = item.run("read", mapOf("path" to file, "include_line_numbers" to true)).output
        assertTrue(output.length < 40_000)
        assertTrue(Regex("Output truncated at line \\d+ of 5000").containsMatchIn(output))
        assertTrue(output.contains("Call read again with offset="))
    }

    @Test
    fun readReturnsSupportedImagesAndRejectsBinaryText() {
        val item = fixture()
        val file = "${item.project}/pixel.png"
        val bytes = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
        item.files.seedBytes(file, bytes)
        val image = item.run("read", mapOf("path" to file))
        assertTrue(image.ok)
        assertTrue(image.output.endsWith("/pixel.png"))
        assertEquals("image/png", image.images.single().mimeType)
        assertEquals(Base64.getEncoder().encodeToString(bytes), image.images.single().data)
        val ranged = item.run("read", mapOf("path" to file, "offset" to 1))
        assertFalse(ranged.ok)
        assertTrue(ranged.output.contains("offset and limit are not supported for image files"))

        val binary = "${item.project}/blob.bin"
        item.files.seedBytes(binary, byteArrayOf(0x00, 0x01))
        val rejected = item.run("read", mapOf("path" to binary))
        assertFalse(rejected.ok)
        assertTrue(rejected.output.contains("Cannot read binary file as UTF-8 text"))
    }

    @Test
    fun writeReturnsACompactDiff() {
        val item = fixture()
        val file = "${item.project}/write.txt"
        val created = item.run("write", mapOf("path" to file, "content" to "one\ntwo"))
        assertTrue(created.output.contains("Created"))
        assertTrue(created.output.contains("(+2/-0)"))
        assertTrue(created.output.contains("+one\n+two"))
        val updated = item.run("write", mapOf("path" to file, "content" to "one\nthree\nfour"))
        assertTrue(updated.output.contains("Updated"))
        assertTrue(updated.output.contains("(+2/-1)"))
        assertTrue(updated.output.contains("-two"))
        assertTrue(updated.output.contains("+three"))
        assertEquals("one\nthree\nfour", item.files.text(file))
    }

    @Test
    fun diffTruncationKeepsTheBudget() {
        val mutation = FileMutation(
            path = "/home/project/big.txt",
            before = null,
            after = "x".repeat(MAX_DIFF_CHARS)
        )
        val output = formatMutation(mutation)
        assertTrue(output.endsWith("[Diff truncated; read /home/project/big.txt to inspect the complete result.]"))
        assertTrue(output.length > MAX_DIFF_CHARS)
    }

    @Test
    fun strReplaceIsUniqueUnlessReplaceAllIsSet() {
        val item = fixture()
        val file = "${item.project}/replace.txt"
        item.files.seed(file, "red blue red")
        val ambiguous = item.run(
            "str_replace",
            mapOf("path" to file, "old_string" to "red", "new_string" to "green")
        )
        assertFalse(ambiguous.ok)
        assertTrue(ambiguous.output.contains("matched 2 times"))
        assertTrue(ambiguous.output.contains("replace_all"))
        assertEquals("red blue red", item.files.text(file))
        val replaced = item.run(
            "str_replace",
            mapOf("path" to file, "old_string" to "red", "new_string" to "green", "replace_all" to true)
        )
        assertTrue(replaced.output.contains("Replaced 2 occurrences"))
        assertEquals("green blue green", item.files.text(file))
        val missing = item.run(
            "str_replace",
            mapOf("path" to file, "old_string" to "purple", "new_string" to "")
        )
        assertFalse(missing.ok)
        assertTrue(missing.output.contains("matched 0 times"))
        assertEquals("green blue green", item.files.text(file))
    }

    @Test
    fun multiStrReplaceIsAtomic() {
        val item = fixture()
        val file = "${item.project}/multi.txt"
        item.files.seed(file, "alpha beta gamma")
        val applied = item.run(
            "multi_str_replace",
            mapOf(
                "path" to file,
                "edits" to listOf(
                    mapOf("old_string" to "alpha", "new_string" to "A"),
                    mapOf("old_string" to "gamma", "new_string" to "G")
                )
            )
        )
        assertTrue(applied.output.contains("Applied 2 edits"))
        assertEquals("A beta G", item.files.text(file))
        val failed = item.run(
            "multi_str_replace",
            mapOf(
                "path" to file,
                "edits" to listOf(
                    mapOf("old_string" to "A", "new_string" to "changed"),
                    mapOf("old_string" to "missing", "new_string" to "nope")
                )
            )
        )
        assertFalse(failed.ok)
        assertTrue(failed.output.contains("Edit 2:"))
        assertTrue(failed.output.contains("matched 0 times"))
        assertEquals("A beta G", item.files.text(file))
    }

    @Test
    fun deleteRemovesADirectoryTree() {
        val item = fixture()
        val directory = "${item.project}/obsolete"
        item.files.mkdir(directory)
        item.files.seed("$directory/old.txt", "old")
        val deleted = item.run("delete", mapOf("path" to directory))
        assertTrue(deleted.output.contains("Deleted directory"))
        assertEquals(null, item.files.text("$directory/old.txt"))
        assertFalse(item.files.exists(directory))
    }

    @Test
    fun lsRendersDirectoriesBeforeFiles() {
        val item = fixture()
        item.files.mkdir("${item.project}/src/nested")
        item.files.seed("${item.project}/README.md", "readme")
        item.files.seed("${item.project}/src/index.ts", "code")
        val output = item.run("ls", mapOf("path" to item.project)).output
        assertTrue(output.contains("project/"))
        assertTrue(output.contains("├── src/"))
        assertTrue(output.contains("│   ├── nested/"))
        assertTrue(output.contains("└── README.md"))
    }

    @Test
    fun globSortsNewestMatchesFirstAndCapsTheList() {
        val item = fixture()
        item.files.mkdir("${item.project}/src")
        val oldFile = "${item.project}/old.ts"
        val newFile = "${item.project}/src/new.ts"
        item.files.seed(oldFile, "old", modifiedAt = 1_000)
        item.files.seed(newFile, "new", modifiedAt = 2_000)
        item.files.seed("${item.project}/README.md", "readme", modifiedAt = 3_000)
        val output = item.run(
            "glob",
            mapOf("glob_pattern" to "*.ts", "target_directory" to item.project)
        ).output
        assertTrue(output.indexOf(newFile) < output.indexOf(oldFile))
        assertFalse(output.contains("README"))

        repeat(MAX_GLOB_RESULTS + 1) { index ->
            item.files.seed("${item.project}/extra/f$index.txt", "x", modifiedAt = index.toLong())
        }
        val capped = item.run(
            "glob",
            mapOf("glob_pattern" to "*.txt", "target_directory" to "${item.project}/extra")
        ).output
        assertTrue(capped.contains("[1 more matches omitted.]"))
    }

    @Test
    fun unknownToolAndUnboundSessionFailClosed() {
        val item = fixture()
        try {
            item.run("missing", emptyMap())
            throw AssertionError("expected an unknown-tool failure")
        } catch (error: NuumException) {
            assertEquals(KernelErrorCode.TOOL, error.code)
            assertEquals("Unknown tool: missing", error.message)
        }
        item.backend.release(RUN_ID)
        try {
            item.run("read", mapOf("path" to "${item.project}/lines.txt"))
            throw AssertionError("expected an unbound session")
        } catch (error: NuumException) {
            assertEquals(KernelErrorCode.INVALID, error.code)
            assertEquals("No tool session is bound for run $RUN_ID.", error.message)
        }
    }
}
