package com.nuum.tools

import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.PermissionDecision
import com.nuum.contracts.ToolPermission
import com.nuum.contracts.ToolRoots
import com.nuum.tools.fs.DocumentNode
import com.nuum.tools.fs.DocumentTrees
import com.nuum.tools.fs.MissingPathException
import com.nuum.tools.fs.RoutingToolFileSystem
import com.nuum.tools.fs.SafDocumentFileSystem
import com.nuum.tools.fs.normalizeContent
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SafDocumentTest {
    @Test
    fun parentSegmentsCannotEscapeAContentTree() {
        assertEquals(
            "content://auth/tree/docs",
            normalizeContent("content://auth/tree/docs/../etc/passwd")
        )
        assertEquals(
            "content://auth/tree/docs/notes/a.txt",
            normalizeContent("content://auth/tree/docs/notes/./a.txt")
        )
    }

    @Test
    fun missingUriPermissionIsOutsideTheAllowedRoot() {
        val store = FakeDocumentStore(permit = false)
        val item = safFixture(store)
        val verdict = item.authorize(LocalToolAction.READ_FILE, "$TREE/notes.md")
        assertEquals(PermissionDecision.DENY, verdict.decision)
        assertEquals(OUTSIDE_ROOT, verdict.reason)
        val read = item.run("read", mapOf("path" to "$TREE/notes.md"))
        assertFalse(read.ok)
        assertEquals(OUTSIDE_ROOT, read.output)
        assertTrue(store.files.isEmpty())
    }

    @Test
    fun aGrantedTreeIsWritableOutsideTheFilesystemHome() {
        val store = FakeDocumentStore(permit = true)
        val item = safFixture(store, permission = ToolPermission.NEVER)
        val path = "$TREE/notes/a.txt"
        val written = item.run("write", mapOf("path" to path, "content" to "hello"))
        assertTrue(written.output, written.ok)
        assertEquals("hello", store.files["notes/a.txt"]?.toString(Charsets.UTF_8))
        val read = item.run("read", mapOf("path" to path))
        assertEquals("hello", read.output)
        assertEquals(PermissionDecision.ALLOW, item.authorize(LocalToolAction.WRITE_FILE, path).decision)
    }

    private fun safFixture(
        store: FakeDocumentStore,
        permission: ToolPermission = ToolPermission.ALWAYS
    ): ToolFixture {
        val files = MemoryToolFileSystem()
        val routing = RoutingToolFileSystem(files, SafDocumentFileSystem(store))
        return fixture(permission = permission, project = TREE, files = files, fileSystem = routing)
    }
}

private const val TREE = "content://auth/tree/docs"

private class FakeDocumentStore(var permit: Boolean) : DocumentTrees {
    val files = mutableMapOf<String, ByteArray>()
    private val directories = mutableSetOf("")
    private val modified = mutableMapOf<String, Long>()
    private var clock = 1L

    override fun open(treeUri: String): DocumentNode? {
        if (!permit || treeUri != TREE) return null
        return Node("")
    }

    private inner class Node(private val relative: String) : DocumentNode {
        override val name: String
            get() = if (relative.isEmpty()) "docs" else relative.substringAfterLast('/')

        override val isDirectory: Boolean
            get() = relative in directories && relative !in files

        override val lastModifiedMillis: Long
            get() = modified[relative] ?: 0L

        override fun children(): List<DocumentNode> {
            val names = linkedSetOf<String>()
            fun consider(path: String) {
                if (path.isEmpty() || path == relative) return
                val rest = when {
                    relative.isEmpty() -> path
                    path.startsWith("$relative/") -> path.removePrefix("$relative/")
                    else -> return
                }
                val name = rest.substringBefore('/')
                if (name.isNotEmpty()) names += name
            }
            files.keys.forEach(::consider)
            directories.forEach(::consider)
            return names.map { Node(childPath(it)) }
        }

        override fun child(name: String): DocumentNode? {
            val path = childPath(name)
            if (path !in files && path !in directories) return null
            return Node(path)
        }

        override fun readBytes(): ByteArray = files[relative] ?: throw MissingPathException(relative)

        override fun writeBytes(bytes: ByteArray) {
            files[relative] = bytes
            directories.remove(relative)
            modified[relative] = clock++
        }

        override fun createFile(name: String): DocumentNode {
            val path = childPath(name)
            files.putIfAbsent(path, ByteArray(0))
            directories.remove(path)
            return Node(path)
        }

        override fun createDirectory(name: String): DocumentNode {
            directories.add(childPath(name))
            return Node(childPath(name))
        }

        override fun delete() {
            val prefix = if (relative.isEmpty()) "" else "$relative/"
            files.keys.filter { it == relative || (prefix.isNotEmpty() && it.startsWith(prefix)) }
                .toList()
                .forEach { files.remove(it) }
            directories.filter { it == relative || (prefix.isNotEmpty() && it.startsWith(prefix)) }
                .toList()
                .forEach { directories.remove(it) }
        }

        private fun childPath(name: String): String = if (relative.isEmpty()) name else "$relative/$name"
    }
}
