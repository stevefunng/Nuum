package com.nuum.tools

import com.nuum.tools.fs.MissingPathException
import com.nuum.tools.fs.ToolDirEntry
import com.nuum.tools.fs.ToolFileSystem

/** In-memory tree. Paths are absolute and `/`-separated. Symlinks are not modeled. */
internal class MemoryToolFileSystem : ToolFileSystem {
    private val files = mutableMapOf<String, ByteArray>()
    private val directories = mutableSetOf("/")
    private val modified = mutableMapOf<String, Long>()
    private var clock = 1L

    fun seed(path: String, text: String, modifiedAt: Long? = null) {
        seedBytes(path, text.toByteArray(Charsets.UTF_8), modifiedAt)
    }

    fun seedBytes(path: String, bytes: ByteArray, modifiedAt: Long? = null) {
        val normalized = normalize(path)
        addParents(normalized)
        directories.remove(normalized)
        files[normalized] = bytes
        modified[normalized] = modifiedAt ?: clock++
    }

    fun mkdir(path: String) {
        val normalized = normalize(path)
        addParents(normalized)
        if (normalized !in files) directories.add(normalized)
    }

    fun text(path: String): String? = files[normalize(path)]?.toString(Charsets.UTF_8)

    override fun canonicalize(cwd: String, input: String): String {
        val raw = if (input.startsWith("/")) input else "${cwd.trimEnd('/')}/$input"
        return normalize(raw)
    }

    override fun lacksUriPermission(path: String): Boolean = false

    override fun exists(path: String): Boolean {
        val normalized = normalize(path)
        return normalized in files || normalized in directories
    }

    override fun isDirectory(path: String): Boolean {
        val normalized = normalize(path)
        return normalized in directories && normalized !in files
    }

    override fun isSymlink(path: String): Boolean = false

    override fun readBytes(path: String): ByteArray =
        files[normalize(path)] ?: throw MissingPathException(normalize(path))

    override fun writeBytes(path: String, bytes: ByteArray) {
        val normalized = normalize(path)
        addParents(normalized)
        directories.remove(normalized)
        files[normalized] = bytes
        modified[normalized] = clock++
    }

    override fun list(path: String): List<ToolDirEntry> {
        val normalized = normalize(path)
        if (normalized !in directories && normalized !in files) throw MissingPathException(normalized)
        if (normalized !in directories) return emptyList()
        val prefix = if (normalized == "/") "/" else "$normalized/"
        val names = linkedSetOf<String>()
        fun consider(candidate: String) {
            if (candidate == normalized || !candidate.startsWith(prefix)) return
            val name = candidate.removePrefix(prefix).substringBefore('/')
            if (name.isNotEmpty()) names.add(name)
        }
        directories.forEach(::consider)
        files.keys.forEach(::consider)
        return names.map { name ->
            val child = if (normalized == "/") "/$name" else "$normalized/$name"
            ToolDirEntry(
                name = name,
                isDirectory = child in directories && child !in files,
                isSymlink = false
            )
        }
    }

    override fun delete(path: String) {
        val normalized = normalize(path)
        if (normalized !in files && normalized !in directories) throw MissingPathException(normalized)
        val prefix = "$normalized/"
        files.keys.filter { it == normalized || it.startsWith(prefix) }.toList().forEach {
            files.remove(it)
            modified.remove(it)
        }
        directories.filter { it == normalized || it.startsWith(prefix) }.toList().forEach {
            directories.remove(it)
        }
    }

    override fun lastModifiedMillis(path: String): Long = modified[normalize(path)] ?: 0L

    private fun addParents(path: String) {
        var cursor = parentPath(path)
        val pending = mutableListOf<String>()
        while (cursor.isNotEmpty() && cursor != "/" && cursor !in directories && cursor !in files) {
            pending += cursor
            cursor = parentPath(cursor)
        }
        directories.add("/")
        pending.asReversed().forEach { directories.add(it) }
    }

    private fun normalize(path: String): String {
        val parts = ArrayDeque<String>()
        for (part in path.split('/')) {
            when (part) {
                "", "." -> Unit
                ".." -> if (parts.isNotEmpty()) parts.removeLast()
                else -> parts.addLast(part)
            }
        }
        return "/" + parts.joinToString("/")
    }
}
