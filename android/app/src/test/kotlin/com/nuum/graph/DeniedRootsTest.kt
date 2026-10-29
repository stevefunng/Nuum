package com.nuum.graph

import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.NuumPaths
import com.nuum.contracts.PermissionDecision
import com.nuum.contracts.PermissionVerdict
import com.nuum.contracts.ToolApproval
import com.nuum.contracts.ToolBackend
import com.nuum.contracts.ToolCall
import com.nuum.contracts.ToolDefinition
import com.nuum.contracts.ToolExecutionResult
import com.nuum.contracts.ToolPermission
import com.nuum.contracts.ToolRoots
import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeniedRootsTest {
    @Test
    fun deniedRootsIncludeNoBackupAndTheNuumTree() {
        val root = tempRoot()
        val noBackup = File(root, "no_backup")
        val nuum = File(root, "files/nuum")
        val denied = hostDeniedRoots(noBackup, nuum)
        assertTrue(denied.any { it.endsWith("no_backup") })
        assertTrue(denied.any { it.endsWith("secrets.bin") })
        assertTrue(denied.any { it.endsWith("files/nuum") || it.endsWith("files\\nuum") })
    }

    @Test
    fun carveKeepsSecretsAndHostFilesAndLeavesScratchWorkspaceAndKnowledge() {
        val root = tempRoot()
        val noBackup = File(root, "no_backup").apply { mkdirs() }
        val secrets = File(noBackup, NuumPaths.secretsFileName()).apply { writeBytes(byteArrayOf(1)) }
        val nuum = File(root, "files/nuum").apply { mkdirs() }
        File(nuum, "settings.json").writeText("{}")
        File(nuum, "migrations.json").writeText("{}")
        val scratch = File(nuum, "agents/a1/scratch").apply { mkdirs() }
        File(scratch, "note.txt").writeText("draft")
        val transcript = File(nuum, "agents/a1/transcript.jsonl").apply { writeText("") }
        File(nuum, "agents/a2").mkdirs()
        val otherAgent = File(nuum, "agents/a2/profile.json").apply { writeText("{}") }
        val project = File(nuum, "workspaces/w1").apply { mkdirs() }
        val otherWorkspace = File(nuum, "workspaces/w2").apply { mkdirs() }
        val works = File(nuum, "works/room").apply { mkdirs() }
        File(nuum, "knowledge").mkdirs()
        val knowledge = File(nuum, "knowledge/guide.md").apply { writeText("docs") }

        val denied = hostDeniedRoots(noBackup, nuum)
        val carved = carveDeniedRoots(
            denied = denied,
            exceptions = listOf(
                scratch.absolutePath,
                project.absolutePath,
                knowledge.absolutePath,
                secrets.absolutePath
            ),
            sealed = listOf(noBackup.absolutePath, secrets.absolutePath)
        )

        assertTrue(deniedCovers(carved, secrets.absolutePath))
        assertTrue(deniedCovers(carved, File(nuum, "settings.json").absolutePath))
        assertTrue(deniedCovers(carved, File(nuum, "migrations.json").absolutePath))
        assertTrue(deniedCovers(carved, transcript.absolutePath))
        assertTrue(deniedCovers(carved, otherAgent.absolutePath))
        assertTrue(deniedCovers(carved, works.absolutePath))
        assertTrue(deniedCovers(carved, otherWorkspace.absolutePath))
        assertFalse(deniedCovers(carved, scratch.absolutePath))
        assertFalse(deniedCovers(carved, File(scratch, "note.txt").absolutePath))
        assertFalse(deniedCovers(carved, project.absolutePath))
        assertFalse(deniedCovers(carved, knowledge.absolutePath))
        assertTrue(deniedCovers(carved, File(noBackup, "other.bin").absolutePath))
    }

    @Test
    fun carvingBackendSealsSecretsWhenTheHostPassesTheNuumPrefix() {
        val root = tempRoot()
        val noBackup = File(root, "no_backup").apply { mkdirs() }
        val secrets = File(noBackup, "secrets.bin")
        val nuum = File(root, "files/nuum").apply { mkdirs() }
        File(nuum, "settings.json").writeText("{}")
        val scratch = File(nuum, "agents/a1/scratch").apply { mkdirs() }
        val project = File(nuum, "workspaces/managed").apply { mkdirs() }
        val recording = RecordingBackend()
        val backend = CarvingToolBackend(
            recording,
            sealed = listOf(noBackup.absolutePath, secrets.absolutePath)
        )
        backend.bind(
            runId = "run",
            roots = ToolRoots(
                home = nuum.absolutePath,
                project = project.absolutePath,
                scratch = scratch.absolutePath,
                terminals = File(nuum, "agents/a1/terminals").absolutePath,
                denied = hostDeniedRoots(noBackup, nuum),
                readOnly = listOf("content://com.android.externalstorage.documents/tree/docs")
            ),
            permission = ToolPermission.ALWAYS,
            approvals = emptyList(),
            refused = emptyList()
        )
        assertTrue(deniedCovers(recording.denied, secrets.absolutePath))
        assertTrue(deniedCovers(recording.denied, File(nuum, "settings.json").absolutePath))
        assertFalse(deniedCovers(recording.denied, scratch.absolutePath))
        assertFalse(deniedCovers(recording.denied, project.absolutePath))
    }

    private fun tempRoot(): File = File(System.getProperty("java.io.tmpdir"), "nuum-graph-${System.nanoTime()}").apply {
        mkdirs()
        deleteOnExit()
    }
}

private class RecordingBackend : ToolBackend {
    var denied: List<String> = emptyList()

    override fun definitions(): List<ToolDefinition> = emptyList()

    override fun bind(
        runId: String,
        roots: ToolRoots,
        permission: ToolPermission,
        approvals: List<ToolApproval>,
        refused: List<ToolApproval>
    ) {
        denied = roots.denied
    }

    override suspend fun authorize(runId: String, action: LocalToolAction, target: String): PermissionVerdict =
        PermissionVerdict(PermissionDecision.DENY, target)

    override fun grantOnce(runId: String, action: LocalToolAction, target: String) = Unit

    override fun refuse(runId: String, action: LocalToolAction, target: String) = Unit

    override fun setPermission(runId: String, permission: ToolPermission) = Unit

    override suspend fun execute(runId: String, call: ToolCall): ToolExecutionResult =
        ToolExecutionResult(ok = false, output = "")

    override fun release(runId: String) = Unit
}
