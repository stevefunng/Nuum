package com.nuum.graph

import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.PermissionVerdict
import com.nuum.contracts.ToolApproval
import com.nuum.contracts.ToolBackend
import com.nuum.contracts.ToolCall
import com.nuum.contracts.ToolDefinition
import com.nuum.contracts.ToolExecutionResult
import com.nuum.contracts.ToolPermission
import com.nuum.contracts.ToolRoots

/**
 * Keeps [sealed] prefixes, including `noBackupFilesDir` and `secrets.bin`,
 * denied in full. Other denied prefixes are carved so the current scratch,
 * project workspace, and read-only knowledge roots stay usable.
 */
internal class CarvingToolBackend(
    private val delegate: ToolBackend,
    private val sealed: List<String>
) : ToolBackend {
    override fun definitions(): List<ToolDefinition> = delegate.definitions()

    override fun bind(
        runId: String,
        roots: ToolRoots,
        permission: ToolPermission,
        approvals: List<ToolApproval>,
        refused: List<ToolApproval>
    ) {
        val exceptions = buildList {
            add(roots.scratch)
            roots.project?.let(::add)
            addAll(roots.readOnly)
        }
        delegate.bind(
            runId,
            roots.copy(denied = carveDeniedRoots(roots.denied, exceptions, sealed)),
            permission,
            approvals,
            refused
        )
    }

    override suspend fun authorize(runId: String, action: LocalToolAction, target: String): PermissionVerdict =
        delegate.authorize(runId, action, target)

    override fun grantOnce(runId: String, action: LocalToolAction, target: String) {
        delegate.grantOnce(runId, action, target)
    }

    override fun refuse(runId: String, action: LocalToolAction, target: String) {
        delegate.refuse(runId, action, target)
    }

    override fun setPermission(runId: String, permission: ToolPermission) {
        delegate.setPermission(runId, permission)
    }

    override suspend fun execute(runId: String, call: ToolCall): ToolExecutionResult =
        delegate.execute(runId, call)

    override fun release(runId: String) {
        delegate.release(runId)
    }
}
