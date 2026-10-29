package com.nuum.tools

import android.content.Context
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.NuumException
import com.nuum.contracts.PermissionVerdict
import com.nuum.contracts.ToolApproval
import com.nuum.contracts.ToolBackend
import com.nuum.contracts.ToolCall
import com.nuum.contracts.ToolDefinition
import com.nuum.contracts.ToolExecutionResult
import com.nuum.contracts.ToolPermission
import com.nuum.contracts.ToolRoots
import com.nuum.tools.fs.DocumentFileTrees
import com.nuum.tools.fs.NioToolFileSystem
import com.nuum.tools.fs.RoutingToolFileSystem
import com.nuum.tools.fs.SafDocumentFileSystem
import com.nuum.tools.fs.ToolFileSystem
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class LocalToolBackend internal constructor(
    private val files: ToolFileSystem,
    private val registry: ToolRegistry = ToolRegistry.builtin()
) : ToolBackend {
    constructor() : this(NioToolFileSystem())

    private val sessions = ConcurrentHashMap<String, RunSandbox>()

    override fun definitions(): List<ToolDefinition> = registry.list()

    fun list(names: List<String>? = null): List<ToolDefinition> = registry.list(names)

    override fun bind(
        runId: String,
        roots: ToolRoots,
        permission: ToolPermission,
        approvals: List<ToolApproval>,
        refused: List<ToolApproval>
    ) {
        sessions[runId] = RunSandbox(files, roots, permission, approvals, refused)
    }

    override suspend fun authorize(runId: String, action: LocalToolAction, target: String): PermissionVerdict =
        withContext(Dispatchers.IO) {
            session(runId).authorize(action, target)
        }

    override fun grantOnce(runId: String, action: LocalToolAction, target: String) {
        session(runId).grantOnce(action, target)
    }

    override fun refuse(runId: String, action: LocalToolAction, target: String) {
        session(runId).refuse(action, target)
    }

    override fun setPermission(runId: String, permission: ToolPermission) {
        session(runId).setPermission(permission)
    }

    override suspend fun execute(runId: String, call: ToolCall): ToolExecutionResult = withContext(Dispatchers.IO) {
        val tool = registry.get(call.name)
            ?: throw NuumException(KernelErrorCode.TOOL, "Unknown tool: ${call.name}")
        val sandbox = session(runId)
        try {
            tool.execute(call.arguments, sandbox)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: NuumException) {
            ToolExecutionResult(ok = false, output = error.message)
        }
    }

    override fun release(runId: String) {
        sessions.remove(runId)
    }

    private fun session(runId: String): RunSandbox =
        sessions[runId] ?: throw NuumException(
            KernelErrorCode.INVALID,
            "No tool session is bound for run $runId."
        )

    companion object {
        fun create(context: Context): LocalToolBackend =
            LocalToolBackend(
                RoutingToolFileSystem(
                    NioToolFileSystem(),
                    SafDocumentFileSystem(DocumentFileTrees(context))
                )
            )
    }
}
