package com.nuum.tools.fs

internal class MissingPathException(val path: String) : Exception("No such file: $path")

internal data class ToolDirEntry(
    val name: String,
    val isDirectory: Boolean,
    val isSymlink: Boolean
)

/**
 * Byte port used by the sandbox. Filesystem paths and `content://` trees share this
 * shape so tests can substitute a fake.
 */
internal interface ToolFileSystem {
    fun canonicalize(cwd: String, input: String): String
    fun lacksUriPermission(path: String): Boolean
    fun exists(path: String): Boolean
    fun isDirectory(path: String): Boolean
    fun isSymlink(path: String): Boolean
    fun readBytes(path: String): ByteArray
    fun writeBytes(path: String, bytes: ByteArray)
    fun list(path: String): List<ToolDirEntry>
    fun delete(path: String)
    fun lastModifiedMillis(path: String): Long
}

internal class RoutingToolFileSystem(
    private val local: ToolFileSystem,
    private val documents: ToolFileSystem
) : ToolFileSystem {
    override fun canonicalize(cwd: String, input: String): String = pick(cwd, input).canonicalize(cwd, input)

    override fun lacksUriPermission(path: String): Boolean = pick(path).lacksUriPermission(path)

    override fun exists(path: String): Boolean = pick(path).exists(path)

    override fun isDirectory(path: String): Boolean = pick(path).isDirectory(path)

    override fun isSymlink(path: String): Boolean = pick(path).isSymlink(path)

    override fun readBytes(path: String): ByteArray = pick(path).readBytes(path)

    override fun writeBytes(path: String, bytes: ByteArray) = pick(path).writeBytes(path, bytes)

    override fun list(path: String): List<ToolDirEntry> = pick(path).list(path)

    override fun delete(path: String) = pick(path).delete(path)

    override fun lastModifiedMillis(path: String): Long = pick(path).lastModifiedMillis(path)

    private fun pick(path: String): ToolFileSystem =
        if (path.startsWith("content://")) documents else local

    private fun pick(cwd: String, input: String): ToolFileSystem = when {
        input.startsWith("content://") -> documents
        input.startsWith("/") -> local
        cwd.startsWith("content://") -> documents
        else -> local
    }
}
