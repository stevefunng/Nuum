package com.nuum.tools.fs

import java.io.IOException
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.SimpleFileVisitor
import java.nio.file.attribute.BasicFileAttributes

internal class NioToolFileSystem : ToolFileSystem {
    override fun canonicalize(cwd: String, input: String): String {
        val base = Path.of(cwd).toAbsolutePath()
        val raw = Path.of(input)
        val combined = if (raw.isAbsolute) raw else base.resolve(raw)
        return realpathExistingPrefix(combined).toString()
    }

    override fun lacksUriPermission(path: String): Boolean = false

    override fun exists(path: String): Boolean =
        Files.exists(Path.of(path), LinkOption.NOFOLLOW_LINKS)

    override fun isDirectory(path: String): Boolean =
        Files.isDirectory(Path.of(path), LinkOption.NOFOLLOW_LINKS)

    override fun isSymlink(path: String): Boolean = Files.isSymbolicLink(Path.of(path))

    override fun readBytes(path: String): ByteArray {
        val target = Path.of(path)
        if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)) throw MissingPathException(path)
        return Files.readAllBytes(target)
    }

    override fun writeBytes(path: String, bytes: ByteArray) {
        val target = Path.of(path)
        val parent = target.parent
        if (parent != null) Files.createDirectories(parent)
        Files.write(target, bytes)
    }

    override fun list(path: String): List<ToolDirEntry> {
        val dir = Path.of(path)
        if (!Files.exists(dir, LinkOption.NOFOLLOW_LINKS)) throw MissingPathException(path)
        if (!Files.isDirectory(dir, LinkOption.NOFOLLOW_LINKS)) return emptyList()
        return Files.newDirectoryStream(dir).use { stream ->
            stream.map { child ->
                val symlink = Files.isSymbolicLink(child)
                ToolDirEntry(
                    name = child.fileName.toString(),
                    isDirectory = !symlink && Files.isDirectory(child),
                    isSymlink = symlink
                )
            }.toList()
        }
    }

    override fun delete(path: String) {
        val target = Path.of(path)
        if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)) throw MissingPathException(path)
        if (Files.isSymbolicLink(target) || !Files.isDirectory(target, LinkOption.NOFOLLOW_LINKS)) {
            Files.delete(target)
            return
        }
        Files.walkFileTree(
            target,
            object : SimpleFileVisitor<Path>() {
                override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult {
                    Files.delete(file)
                    return FileVisitResult.CONTINUE
                }

                override fun postVisitDirectory(dir: Path, exc: IOException?): FileVisitResult {
                    if (exc != null) throw exc
                    Files.delete(dir)
                    return FileVisitResult.CONTINUE
                }
            }
        )
    }

    override fun lastModifiedMillis(path: String): Long =
        Files.getLastModifiedTime(Path.of(path)).toMillis()
}

/**
 * Resolve the longest existing prefix, then append the missing suffix.
 * Symlinks in the existing prefix are followed, so a link cannot hide an escape.
 */
internal fun realpathExistingPrefix(target: Path): Path {
    val normalized = target.toAbsolutePath().normalize()
    var cursor = normalized
    while (true) {
        try {
            val existing = cursor.toRealPath()
            val rest = cursor.relativize(normalized).normalize()
            return if (rest.toString().isEmpty()) existing else existing.resolve(rest).normalize()
        } catch (_: IOException) {
            val parent = cursor.parent ?: return normalized
            if (parent == cursor) return normalized
            cursor = parent
        }
    }
}
