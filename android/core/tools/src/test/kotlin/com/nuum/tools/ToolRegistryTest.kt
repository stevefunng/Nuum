package com.nuum.tools

import com.nuum.contracts.ToolDefinition
import com.nuum.contracts.ToolExecutionResult
import org.junit.Assert.assertEquals
import org.junit.Test

class ToolRegistryTest {
    @Test
    fun builtinOrderMatchesThePocSurface() {
        assertEquals(
            listOf(
                "read",
                "write",
                "str_replace",
                "multi_str_replace",
                "delete",
                "ls",
                "glob",
                "grep",
                "shell",
                "request_network",
                "external_operation"
            ),
            ToolRegistry.builtin().list().map { it.name }
        )
    }

    @Test
    fun noFilterMeansEveryToolAndAnEmptyFilterMeansNone() {
        val registry = ToolRegistry(listOf(stub("read"), stub("write")))
        assertEquals(listOf("read", "write"), registry.list().map { it.name })
        assertEquals(emptyList<ToolDefinition>(), registry.list(emptyList()))
    }

    @Test
    fun aFilterKeepsRegistryOrderAndDropsUnknownNames() {
        val registry = ToolRegistry(listOf(stub("read"), stub("write"), stub("shell")))
        assertEquals(
            listOf("read", "shell"),
            registry.list(listOf("shell", "ghost", "read")).map { it.name }
        )
    }

    @Test
    fun backendListUsesTheSameEmptyVersusAbsentRule() {
        val backend = LocalToolBackend(MemoryToolFileSystem())
        assertEquals(11, backend.definitions().size)
        assertEquals(backend.definitions().map { it.name }, backend.list().map { it.name })
        assertEquals(emptyList<String>(), backend.list(emptyList()).map { it.name })
    }

    private fun stub(name: String): Tool = object : Tool {
        override val definition = ToolDefinition(
            name = name,
            description = name,
            inputSchema = mapOf<String, Any?>("type" to "object"),
            mutating = false
        )

        override suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult =
            ToolExecutionResult(ok = true, output = name)
    }
}
