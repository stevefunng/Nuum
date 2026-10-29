package com.nuum.tools

import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.NuumException
import com.nuum.contracts.PermissionDecision
import com.nuum.contracts.PermissionVerdict
import com.nuum.contracts.ToolApproval
import com.nuum.contracts.ToolPermission
import com.nuum.contracts.ToolRoots
import com.nuum.tools.fs.MissingPathException
import com.nuum.tools.fs.ToolDirEntry
import com.nuum.tools.fs.ToolFileSystem

internal class RunSandbox(
    private val files: ToolFileSystem,
    roots: ToolRoots,
    permission: ToolPermission,
    approvals: List<ToolApproval>,
    refused: List<ToolApproval>
) {
    private val lock = Any()
    private var permission = permission
    private val approvals = approvals.map(::approvalKey).toMutableSet()
    private val refused = refused.map(::approvalKey).toMutableSet()

    val cwd: String = roots.project ?: roots.scratch
    private val home = files.canonicalize(roots.home, roots.home)
    private val scratch = files.canonicalize(roots.scratch, roots.scratch)
    private val project = roots.project?.let { files.canonicalize(it, it) }
    private val denied = roots.denied.map { files.canonicalize(it, it) }
    private val readOnly = roots.readOnly.map { files.canonicalize(it, it) }
    private val agentsRoot = parentPath(parentPath(scratch))

    fun authorize(action: LocalToolAction, input: String): PermissionVerdict = synchronized(lock) {
        if (action == LocalToolAction.RUN_COMMAND) return authorizeCommand(input)
        if (action == LocalToolAction.NETWORK) return standingDecision(action, input.ifBlank { "(empty)" })
        authorizePath(action, input)
    }

    fun grantOnce(action: LocalToolAction, target: String) = synchronized(lock) {
        approvals += approvalKey(ToolApproval(action, target))
    }

    fun refuse(action: LocalToolAction, target: String) = synchronized(lock) {
        refused += approvalKey(ToolApproval(action, target))
    }

    fun setPermission(permission: ToolPermission) = synchronized(lock) {
        this.permission = permission
    }

    fun requireAllowed(action: LocalToolAction, input: String, withPeriod: Boolean = false): String {
        val verdict = authorize(action, input)
        if (verdict.decision == PermissionDecision.ALLOW) return verdict.target
        val fallback = if (withPeriod) {
            "Approval is required for ${action.wire} ${verdict.target}."
        } else {
            "Approval is required for ${action.wire} ${verdict.target}"
        }
        throw NuumException(KernelErrorCode.SANDBOX, verdict.reason ?: fallback)
    }

    fun readText(inputPath: String): String {
        val resolved = requireAllowed(LocalToolAction.READ_FILE, inputPath)
        return readResolved(resolved).toString(Charsets.UTF_8)
    }

    fun readBinary(inputPath: String): BinaryFile {
        val resolved = requireAllowed(LocalToolAction.READ_FILE, inputPath)
        return BinaryFile(resolved, readResolved(resolved))
    }

    fun writeText(inputPath: String, content: String): FileMutation {
        val resolved = requireAllowed(LocalToolAction.WRITE_FILE, inputPath)
        val before = try {
            files.readBytes(resolved).toString(Charsets.UTF_8)
        } catch (_: MissingPathException) {
            null
        }
        files.writeBytes(resolved, content.toByteArray(Charsets.UTF_8))
        return FileMutation(resolved, before, content)
    }

    fun mutateText(inputPath: String, transform: (String) -> String): FileMutation {
        val resolved = requireAllowed(LocalToolAction.WRITE_FILE, inputPath)
        val current = try {
            files.readBytes(resolved).toString(Charsets.UTF_8)
        } catch (_: MissingPathException) {
            throw NuumException(KernelErrorCode.TOOL, "No such file: $inputPath")
        }
        val next = transform(current)
        files.writeBytes(resolved, next.toByteArray(Charsets.UTF_8))
        return FileMutation(resolved, current, next)
    }

    fun deletePath(inputPath: String): DeletedPath {
        val resolved = requireAllowed(LocalToolAction.WRITE_FILE, inputPath)
        if (!files.exists(resolved)) throw NuumException(KernelErrorCode.TOOL, "No such file: $inputPath")
        val kind = if (files.isDirectory(resolved)) "directory" else "file"
        files.delete(resolved)
        return DeletedPath(resolved, kind)
    }

    fun list(resolved: String): List<ToolDirEntry> {
        if (!files.isDirectory(resolved)) {
            throw NuumException(KernelErrorCode.TOOL, "Not a directory: $resolved")
        }
        return files.list(resolved)
    }

    fun exists(resolved: String): Boolean = files.exists(resolved)

    fun isDirectory(resolved: String): Boolean = files.isDirectory(resolved)

    fun lastModifiedMillis(resolved: String): Long = files.lastModifiedMillis(resolved)

    /** Already-authorized path. Callers must not follow symlinks out of the root they checked. */
    fun readBytes(resolved: String): ByteArray = readResolved(resolved)

    private fun readResolved(resolved: String): ByteArray = try {
        files.readBytes(resolved)
    } catch (_: MissingPathException) {
        throw NuumException(KernelErrorCode.TOOL, "No such file: $resolved")
    }

    /**
     * 判定顺序与 create-sandbox.ts 相同：denied、readOnly、必须在 home 或 scratch 下、
     * project 与 scratch 预批准、agent 目录只读、其余 always | ask | never。
     * 没有 URI 权限时按「路径在允许根之外」拒绝。授权过的 SAF project 不在文件系统 home 下，
     * 仍然走 project 预批准。
     */
    private fun authorizePath(action: LocalToolAction, input: String): PermissionVerdict {
        val target = files.canonicalize(cwd, input)
        if (files.lacksUriPermission(target)) {
            return deny(action, target, OUTSIDE_ROOT)
        }
        if (denied.any { pathContains(it, target) }) {
            return deny(action, target, "Path is inside a protected host-only store.")
        }
        if (readOnly.any { pathContains(it, target) }) {
            return if (action == LocalToolAction.READ_FILE || action == LocalToolAction.LIST_DIRECTORY) {
                allow(action, target)
            } else {
                deny(action, target, "Path is a Work read-only knowledge root.")
            }
        }
        val underHome = pathContains(home, target)
        val underScratch = pathContains(scratch, target)
        val underProject = project != null && pathContains(project, target)
        val grantedSafProject = target.startsWith("content://") && underProject
        if (!underHome && !underScratch && !grantedSafProject) {
            return deny(action, target, OUTSIDE_ROOT)
        }
        if (underScratch || underProject) {
            return allow(action, target)
        }
        if (pathContains(agentsRoot, target)) {
            return if (action == LocalToolAction.READ_FILE || action == LocalToolAction.LIST_DIRECTORY) {
                allow(action, target)
            } else {
                deny(action, target, "Agent stores are read-only; use update_state for your own state.")
            }
        }
        return standingDecision(action, target)
    }

    private fun authorizeCommand(command: String): PermissionVerdict {
        val target = commandToken(command)
        if (target.isEmpty()) return deny(LocalToolAction.RUN_COMMAND, "(empty)", "Command is empty.")
        return standingDecision(LocalToolAction.RUN_COMMAND, target)
    }

    private fun standingDecision(action: LocalToolAction, target: String): PermissionVerdict {
        val key = approvalKey(ToolApproval(action, target))
        if (approvals.contains(key)) return allow(action, target)
        if (refused.contains(key)) {
            return deny(action, target, "The same action was previously refused.")
        }
        return when (permission) {
            ToolPermission.ALWAYS -> allow(action, target)
            ToolPermission.NEVER -> deny(action, target, "Local tools are disabled for this agent.")
            ToolPermission.ASK -> PermissionVerdict(decision = PermissionDecision.ASK, target = target)
        }
    }

    private fun allow(action: LocalToolAction, target: String): PermissionVerdict =
        PermissionVerdict(decision = PermissionDecision.ALLOW, target = target)

    private fun deny(action: LocalToolAction, target: String, reason: String): PermissionVerdict =
        PermissionVerdict(decision = PermissionDecision.DENY, target = target, reason = reason)

    private fun approvalKey(approval: ToolApproval): String = "${approval.action.wire}\u0000${approval.target}"
}

internal data class BinaryFile(val path: String, val data: ByteArray)

internal data class DeletedPath(val path: String, val kind: String)
