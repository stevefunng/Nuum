package com.nuum.storage

import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NuumException
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID

internal data class ResolvedPath(val relative: String, val file: File)

internal fun normalizeRelative(path: String): String {
    val slash = path.replace('\\', '/').trim()
    if (slash.isEmpty()) {
        throw NuumException(KernelErrorCode.INVALID, "Path is empty")
    }
    if (slash.startsWith("/")) {
        throw NuumException(KernelErrorCode.INVALID, "Path must stay relative to the nuum directory")
    }
    val parts = slash.split('/').filter { it.isNotEmpty() && it != "." }
    if (parts.isEmpty() || parts.any { it == ".." || it.contains('\u0000') }) {
        throw NuumException(KernelErrorCode.INVALID, "Path escapes the nuum directory")
    }
    return parts.joinToString("/")
}

internal fun resolveInside(root: File, relativePath: String): ResolvedPath {
    val relative = normalizeRelative(relativePath)
    val rootFile = root.canonicalFile
    val target = File(rootFile, relative).canonicalFile
    val prefix = rootFile.path + File.separator
    if (target.path != rootFile.path && !target.path.startsWith(prefix)) {
        throw NuumException(KernelErrorCode.INVALID, "Path escapes the nuum directory")
    }
    return ResolvedPath(relative, target)
}

/**
 * Writes [bytes] to a temp file in the same directory, then atomically replaces [target].
 * [beforeCommit] runs after the temp file is durable and before the replace. If it throws,
 * [target] is left unchanged and the temp file is removed.
 */
internal object AtomicFiles {
    fun write(target: File, bytes: ByteArray, beforeCommit: () -> Unit) {
        val parent = target.parentFile ?: throw IOException("missing parent for ${target.name}")
        if (!parent.exists() && !parent.mkdirs()) {
            throw IOException("could not create ${parent.path}")
        }
        val temp = File(parent, "${target.name}.${UUID.randomUUID()}.tmp")
        var moved = false
        try {
            FileOutputStream(temp).use { out ->
                out.write(bytes)
                out.fd.sync()
            }
            beforeCommit()
            try {
                Files.move(
                    temp.toPath(),
                    target.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING
                )
            } catch (error: AtomicMoveNotSupportedException) {
                throw IOException("atomic replace is not supported for ${target.name}", error)
            }
            moved = true
        } finally {
            if (!moved) {
                temp.delete()
            }
        }
    }
}
