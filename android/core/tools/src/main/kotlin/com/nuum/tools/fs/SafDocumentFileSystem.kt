package com.nuum.tools.fs

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NuumException
import com.nuum.tools.OUTSIDE_ROOT

internal interface DocumentNode {
    val name: String
    val isDirectory: Boolean
    val lastModifiedMillis: Long
    fun children(): List<DocumentNode>
    fun child(name: String): DocumentNode?
    fun readBytes(): ByteArray
    fun writeBytes(bytes: ByteArray)
    fun createFile(name: String): DocumentNode
    fun createDirectory(name: String): DocumentNode
    fun delete()
}

/** Opens a granted tree. Null means the process has no read permission for that URI. */
internal interface DocumentTrees {
    fun open(treeUri: String): DocumentNode?
}

internal class SafDocumentFileSystem(
    private val trees: DocumentTrees
) : ToolFileSystem {
    override fun canonicalize(cwd: String, input: String): String {
        val combined = when {
            input.startsWith("content://") -> input
            cwd.startsWith("content://") && !input.startsWith("/") -> joinContent(cwd, input)
            else -> error("SafDocumentFileSystem only canonicalizes content URIs")
        }
        return normalizeContent(combined)
    }

    override fun lacksUriPermission(path: String): Boolean {
        if (!path.startsWith("content://")) return false
        val (tree, _) = splitTree(path)
        return trees.open(tree) == null
    }

    override fun exists(path: String): Boolean = try {
        resolve(path, create = false)
        true
    } catch (_: MissingPathException) {
        false
    }

    override fun isDirectory(path: String): Boolean = try {
        resolve(path, create = false).isDirectory
    } catch (_: MissingPathException) {
        false
    }

    override fun isSymlink(path: String): Boolean = false

    override fun readBytes(path: String): ByteArray = resolve(path, create = false).readBytes()

    override fun writeBytes(path: String, bytes: ByteArray) {
        resolve(path, create = true).writeBytes(bytes)
    }

    override fun list(path: String): List<ToolDirEntry> {
        val node = resolve(path, create = false)
        if (!node.isDirectory) return emptyList()
        return node.children().map { child ->
            ToolDirEntry(name = child.name, isDirectory = child.isDirectory, isSymlink = false)
        }
    }

    override fun delete(path: String) {
        resolve(path, create = false).delete()
    }

    override fun lastModifiedMillis(path: String): Long = resolve(path, create = false).lastModifiedMillis

    private fun resolve(path: String, create: Boolean): DocumentNode {
        val canonical = normalizeContent(path)
        val (tree, relative) = splitTree(canonical)
        val root = trees.open(tree) ?: throw NuumException(KernelErrorCode.SANDBOX, OUTSIDE_ROOT)
        if (relative.isNullOrEmpty()) return root
        val parts = relative.split('/').filter { it.isNotEmpty() && it != "." }
        var node = root
        for ((index, part) in parts.withIndex()) {
            if (part == "..") throw NuumException(KernelErrorCode.SANDBOX, OUTSIDE_ROOT)
            val child = node.child(part)
            if (child != null) {
                node = child
                continue
            }
            if (!create) throw MissingPathException(canonical)
            val last = index == parts.lastIndex
            node = if (last) node.createFile(part) else node.createDirectory(part)
        }
        return node
    }
}

internal class DocumentFileTrees(private val context: Context) : DocumentTrees {
    override fun open(treeUri: String): DocumentNode? {
        val uri = Uri.parse(treeUri)
        if (!canReadTree(context, uri)) return null
        val root = DocumentFile.fromTreeUri(context, uri) ?: return null
        if (!root.exists() || !root.canRead()) return null
        return DocumentFileNode(context, root)
    }
}

internal fun canReadTree(context: Context, tree: Uri): Boolean {
    val persisted = context.contentResolver.persistedUriPermissions.any { permission ->
        permission.isReadPermission && treeCovers(permission.uri, tree)
    }
    if (persisted) return true
    return context.checkUriPermission(
        tree,
        android.os.Process.myPid(),
        android.os.Process.myUid(),
        Intent.FLAG_GRANT_READ_URI_PERMISSION
    ) == PackageManager.PERMISSION_GRANTED
}

internal fun treeCovers(granted: Uri, requested: Uri): Boolean {
    if (granted == requested) return true
    val grantedText = granted.toString().trimEnd('/')
    val requestedText = requested.toString()
    return requestedText == grantedText || requestedText.startsWith("$grantedText/")
}

private class DocumentFileNode(
    private val context: Context,
    private val file: DocumentFile
) : DocumentNode {
    override val name: String
        get() = file.name ?: file.uri.lastPathSegment ?: ""

    override val isDirectory: Boolean
        get() = file.isDirectory

    override val lastModifiedMillis: Long
        get() = file.lastModified()

    override fun children(): List<DocumentNode> =
        file.listFiles().map { DocumentFileNode(context, it) }

    override fun child(name: String): DocumentNode? {
        val found = file.findFile(name) ?: return null
        if (!found.exists()) return null
        return DocumentFileNode(context, found)
    }

    override fun readBytes(): ByteArray {
        val stream = context.contentResolver.openInputStream(file.uri)
            ?: throw MissingPathException(file.uri.toString())
        return stream.use { it.readBytes() }
    }

    override fun writeBytes(bytes: ByteArray) {
        val stream = context.contentResolver.openOutputStream(file.uri)
            ?: throw NuumException(KernelErrorCode.TOOL, "Cannot write ${file.uri}")
        stream.use { it.write(bytes) }
    }

    override fun createFile(name: String): DocumentNode {
        val created = file.createFile("application/octet-stream", name)
            ?: throw NuumException(KernelErrorCode.TOOL, "Cannot create file $name")
        return DocumentFileNode(context, created)
    }

    override fun createDirectory(name: String): DocumentNode {
        val created = file.createDirectory(name)
            ?: throw NuumException(KernelErrorCode.TOOL, "Cannot create directory $name")
        return DocumentFileNode(context, created)
    }

    override fun delete() {
        if (!file.delete()) {
            throw NuumException(KernelErrorCode.TOOL, "Cannot delete ${file.uri}")
        }
    }
}
