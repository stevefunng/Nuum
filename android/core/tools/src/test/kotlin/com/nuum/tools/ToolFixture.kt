package com.nuum.tools

import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.PermissionVerdict
import com.nuum.contracts.ToolApproval
import com.nuum.contracts.ToolCall
import com.nuum.contracts.ToolExecutionResult
import com.nuum.contracts.ToolPermission
import com.nuum.contracts.ToolRoots
import com.nuum.tools.fs.ToolFileSystem
import kotlinx.coroutines.runBlocking

internal const val RUN_ID = "run-1"

internal class ToolFixture(
    val files: MemoryToolFileSystem,
    val backend: LocalToolBackend,
    val home: String,
    val project: String,
    val scratch: String,
    val secret: String,
    val memory: String
) {
    fun run(name: String, args: Map<String, Any?>): ToolExecutionResult = runBlocking {
        backend.execute(RUN_ID, ToolCall(id = "call-1", name = name, arguments = args))
    }

    fun authorize(action: LocalToolAction, target: String): PermissionVerdict = runBlocking {
        backend.authorize(RUN_ID, action, target)
    }
}

internal fun fixture(
    permission: ToolPermission = ToolPermission.NEVER,
    project: String? = "/home/project",
    readOnly: List<String> = emptyList(),
    approvals: List<ToolApproval> = emptyList(),
    refused: List<ToolApproval> = emptyList(),
    files: MemoryToolFileSystem = MemoryToolFileSystem(),
    fileSystem: ToolFileSystem = files
): ToolFixture {
    val home = "/home"
    val scratch = "/home/.nuum/agents/a1/scratch"
    val secret = "/home/.nuum/host-secrets.json"
    val memory = "/home/.nuum/agents/a1/memory/profile.md"
    files.mkdir("/home/project")
    files.mkdir(scratch)
    files.mkdir("/home/.nuum/agents/a1/memory")
    files.seed(secret, "top-secret-value")
    val backend = LocalToolBackend(fileSystem)
    backend.bind(
        runId = RUN_ID,
        roots = ToolRoots(
            home = home,
            project = project,
            scratch = scratch,
            terminals = "/home/.nuum/agents/a1/terminals",
            denied = listOf(secret),
            readOnly = readOnly
        ),
        permission = permission,
        approvals = approvals,
        refused = refused
    )
    return ToolFixture(files, backend, home, project ?: scratch, scratch, secret, memory)
}
