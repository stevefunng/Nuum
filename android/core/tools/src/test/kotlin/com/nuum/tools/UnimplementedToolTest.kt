package com.nuum.tools

import com.nuum.contracts.ToolPermission
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UnimplementedToolTest {
    @Test
    fun shellNetworkAndExternalReturnThePocSentence() {
        val item = fixture(permission = ToolPermission.ALWAYS)
        for (name in listOf("shell", "request_network", "external_operation")) {
            val result = item.run(name, mapOf("command" to "echo hi", "target" to "example.com:443"))
            assertFalse(result.ok)
            assertEquals(POC_NOT_IMPLEMENTED, result.output)
        }
        assertEquals(null, item.files.text("${item.scratch}/echo"))
    }

    @Test
    fun mainSourcesDoNotReferenceProcessLaunchApis() {
        val root = mainKotlinSources()
        val banned = listOf("ProcessBuilder", "Runtime.getRuntime", ".exec(")
        val hits = mutableListOf<String>()
        root.walkTopDown().filter { it.isFile && it.extension == "kt" }.forEach { file ->
            val text = file.readText()
            for (token in banned) {
                if (text.contains(token)) hits += "${file.name} contains $token"
            }
        }
        assertTrue(hits.joinToString("\n"), hits.isEmpty())
    }

    private fun mainKotlinSources(): File {
        val cwd = File(System.getProperty("user.dir"))
        val candidates = listOf(
            File(cwd, "src/main/kotlin"),
            File(cwd, "android/core/tools/src/main/kotlin"),
            File(cwd, "core/tools/src/main/kotlin")
        )
        return candidates.firstOrNull { it.isDirectory }
            ?: error("tools main sources not found from $cwd")
    }
}
