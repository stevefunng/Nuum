package com.nuum.tools

import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.PermissionDecision
import com.nuum.contracts.ToolApproval
import com.nuum.contracts.ToolPermission
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PathPolicyTest {
    @Test
    fun alwaysStillCannotReadTheSecretsPath() {
        val item = fixture(permission = ToolPermission.ALWAYS)
        val verdict = item.authorize(LocalToolAction.READ_FILE, item.secret)
        assertEquals(PermissionDecision.DENY, verdict.decision)
        assertEquals("Path is inside a protected host-only store.", verdict.reason)
        val read = item.run("read", mapOf("path" to item.secret))
        assertFalse(read.ok)
        assertEquals("Path is inside a protected host-only store.", read.output)
        assertFalse(read.output.contains("top-secret-value"))
    }

    @Test
    fun aParentTraversalIntoSecretsIsStillDenied() {
        val item = fixture(permission = ToolPermission.ALWAYS)
        val verdict = item.authorize(
            LocalToolAction.READ_FILE,
            "/home/project/../.nuum/host-secrets.json"
        )
        assertEquals(PermissionDecision.DENY, verdict.decision)
        assertTrue(verdict.reason!!.contains("protected host-only"))
    }

    @Test
    fun scratchIsWritableEvenWhenStandingPermissionIsNever() {
        val item = fixture(permission = ToolPermission.NEVER)
        val path = "${item.scratch}/note.txt"
        val written = item.run("write", mapOf("path" to path, "content" to "draft"))
        assertTrue(written.ok)
        assertTrue(written.output.contains("Created"))
        assertEquals("draft", item.files.text(path))
        assertEquals(PermissionDecision.ALLOW, item.authorize(LocalToolAction.WRITE_FILE, path).decision)
    }

    @Test
    fun agentMemoryPathIsNotWritable() {
        val item = fixture(permission = ToolPermission.ALWAYS)
        val write = item.authorize(LocalToolAction.WRITE_FILE, item.memory)
        assertEquals(PermissionDecision.DENY, write.decision)
        assertEquals(
            "Agent stores are read-only; use update_state for your own state.",
            write.reason
        )
        val result = item.run("write", mapOf("path" to item.memory, "content" to "nope"))
        assertFalse(result.ok)
        assertTrue(result.output.contains("read-only"))
        assertEquals(null, item.files.text(item.memory))
        assertEquals(PermissionDecision.ALLOW, item.authorize(LocalToolAction.READ_FILE, item.memory).decision)
    }

    @Test
    fun projectPathsArePreApprovedAndPathsOutsideHomeAreDenied() {
        val item = fixture(permission = ToolPermission.NEVER)
        assertEquals(
            PermissionDecision.ALLOW,
            item.authorize(LocalToolAction.WRITE_FILE, "${item.project}/x").decision
        )
        val outside = item.authorize(LocalToolAction.READ_FILE, "/tmp/outside/x")
        assertEquals(PermissionDecision.DENY, outside.decision)
        assertEquals(OUTSIDE_ROOT, outside.reason)
    }

    @Test
    fun knowledgeRootsAreReadableAndNotWritable() {
        val knowledge = "/home/knowledge/guide.md"
        val item = fixture(
            permission = ToolPermission.ALWAYS,
            readOnly = listOf("/home/knowledge")
        )
        assertEquals(PermissionDecision.ALLOW, item.authorize(LocalToolAction.READ_FILE, knowledge).decision)
        assertEquals(
            PermissionDecision.ALLOW,
            item.authorize(LocalToolAction.LIST_DIRECTORY, "/home/knowledge").decision
        )
        val write = item.authorize(LocalToolAction.WRITE_FILE, knowledge)
        assertEquals(PermissionDecision.DENY, write.decision)
        assertEquals("Path is a Work read-only knowledge root.", write.reason)
    }

    @Test
    fun approvalsAndRefusalsMatchTheExactActionAndPath() {
        val asked = fixture(permission = ToolPermission.ASK)
        val target = asked.authorize(LocalToolAction.READ_FILE, "/home/notes/one.txt").target
        assertEquals(PermissionDecision.ASK, asked.authorize(LocalToolAction.READ_FILE, target).decision)

        val approved = fixture(
            permission = ToolPermission.ASK,
            approvals = listOf(ToolApproval(LocalToolAction.READ_FILE, target))
        )
        assertEquals(PermissionDecision.ALLOW, approved.authorize(LocalToolAction.READ_FILE, target).decision)
        assertEquals(
            PermissionDecision.ASK,
            approved.authorize(LocalToolAction.READ_FILE, "/home/notes").decision
        )
        assertEquals(
            PermissionDecision.ASK,
            approved.authorize(LocalToolAction.WRITE_FILE, target).decision
        )

        approved.backend.grantOnce(RUN_ID, LocalToolAction.WRITE_FILE, target)
        assertEquals(PermissionDecision.ALLOW, approved.authorize(LocalToolAction.WRITE_FILE, target).decision)

        val refused = fixture(
            permission = ToolPermission.ASK,
            refused = listOf(ToolApproval(LocalToolAction.READ_FILE, target))
        )
        val verdict = refused.authorize(LocalToolAction.READ_FILE, "/home/notes/one.txt")
        assertEquals(PermissionDecision.DENY, verdict.decision)
        assertTrue(verdict.reason!!.contains("previously refused"))
    }

    @Test
    fun commandAuthorizationUsesTheExecutableTokenAndDoesNotLaunchAnything() {
        val item = fixture(
            permission = ToolPermission.ASK,
            approvals = listOf(ToolApproval(LocalToolAction.RUN_COMMAND, "git"))
        )
        val git = item.authorize(LocalToolAction.RUN_COMMAND, "FOO=1 /usr/bin/git status")
        assertEquals(PermissionDecision.ALLOW, git.decision)
        assertEquals("git", git.target)
        val npm = item.authorize(LocalToolAction.RUN_COMMAND, "npm test")
        assertEquals(PermissionDecision.ASK, npm.decision)
        assertEquals("npm", npm.target)
        val empty = item.authorize(LocalToolAction.RUN_COMMAND, "   ")
        assertEquals(PermissionDecision.DENY, empty.decision)
        assertEquals("(empty)", empty.target)
        assertEquals("Command is empty.", empty.reason)
    }

    @Test
    fun aSymlinkCannotEscapeTheHomeRoot() {
        val root = Files.createTempDirectory("nuum-tools-link-")
        try {
            val home = root.resolve("home")
            val project = home.resolve("project")
            val scratch = home.resolve(".nuum/agents/a1/scratch")
            Files.createDirectories(project)
            Files.createDirectories(scratch)
            val outside = Files.createTempDirectory("nuum-tools-outside-")
            Files.createSymbolicLink(project.resolve("escape"), outside)
            val backend = LocalToolBackend()
            backend.bind(
                runId = RUN_ID,
                roots = com.nuum.contracts.ToolRoots(
                    home = home.toString(),
                    project = project.toString(),
                    scratch = scratch.toString(),
                    terminals = scratch.parent.resolve("terminals").toString(),
                    denied = emptyList()
                ),
                permission = ToolPermission.ALWAYS,
                approvals = emptyList(),
                refused = emptyList()
            )
            val verdict = kotlinx.coroutines.runBlocking {
                backend.authorize(
                    RUN_ID,
                    LocalToolAction.WRITE_FILE,
                    project.resolve("escape").resolve("x.txt").toString()
                )
            }
            assertEquals(PermissionDecision.DENY, verdict.decision)
            assertTrue(verdict.reason!!.contains("outside the allowed local execution root"))
            outside.toFile().deleteRecursively()
        } finally {
            root.toFile().deleteRecursively()
        }
    }
}
