package com.nuum.graph

import com.nuum.contracts.NuumPaths
import java.io.File

/**
 * Protected prefixes passed to [com.nuum.agent.HostRuntime].
 * `secrets.bin` lives under [noBackupDir] and is listed on its own so a later
 * edit that drops the directory still keeps the file unreadable.
 */
internal fun hostDeniedRoots(noBackupDir: File, nuumRoot: File): List<String> = listOf(
    noBackupDir.absolutePath,
    File(noBackupDir, NuumPaths.secretsFileName()).absolutePath,
    nuumRoot.absolutePath
)

internal val NUUM_HOST_CHILDREN: List<String> = listOf(
    "settings.json",
    "migrations.json",
    "agents",
    "works",
    "work-sessions",
    "workspaces"
)

internal val AGENT_HOST_CHILDREN: List<String> = listOf(
    "profile.json",
    "settings.json",
    "transcript.jsonl",
    "read-cursor.json",
    "tool-approvals.json",
    "prompt-cache.json",
    "memory",
    "terminals"
)

/**
 * The sandbox checks `denied` before scratch, project, and read-only roots.
 * A prefix of `filesDir/nuum` would also hide those exceptions, so each denied
 * directory is rewritten as the host children around the exception paths.
 * [sealed] prefixes are never carved. `content://` exceptions are ignored
 * because they are not filesystem children of the nuum tree.
 */
internal fun carveDeniedRoots(
    denied: List<String>,
    exceptions: List<String>,
    sealed: List<String> = emptyList(),
    childrenOf: (String) -> List<String> = ::directoryChildren
): List<String> {
    val sealedNorm = sealed.map(::normalizePath).filter { it.isNotEmpty() }
    fun sealedPath(path: String): Boolean = sealedNorm.any { samePath(it, path) || pathInside(it, path) }
    val usable = exceptions
        .asSequence()
        .filter { it.isNotBlank() && !it.startsWith("content://") }
        .map(::normalizePath)
        .filterNot(::sealedPath)
        .distinct()
        .toList()
    val out = LinkedHashSet<String>()
    for (root in denied) {
        if (root.isBlank()) continue
        val normalized = normalizePath(root)
        if (sealedPath(normalized)) {
            out += normalized
            continue
        }
        val hits = usable.filter { samePath(normalized, it) || pathInside(normalized, it) }
        out += expandDenied(normalized, hits, childrenOf, ::sealedPath)
    }
    return out.toList()
}

internal fun deniedCovers(denied: List<String>, path: String): Boolean {
    val target = normalizePath(path)
    return denied.any { root ->
        val normalized = normalizePath(root)
        samePath(normalized, target) || pathInside(normalized, target)
    }
}

internal fun normalizePath(path: String): String {
    val slash = File(path).absolutePath.replace('\\', '/')
    val leading = slash.startsWith("/")
    val parts = ArrayDeque<String>()
    for (part in slash.split('/')) {
        when {
            part.isEmpty() || part == "." -> Unit
            part == ".." -> if (parts.isNotEmpty()) parts.removeLast()
            else -> parts.addLast(part)
        }
    }
    return buildString {
        if (leading) append('/')
        append(parts.joinToString("/"))
    }
}

private fun expandDenied(
    root: String,
    exceptions: List<String>,
    childrenOf: (String) -> List<String>,
    sealedPath: (String) -> Boolean
): List<String> {
    if (exceptions.isEmpty()) return listOf(root)
    if (sealedPath(root)) return listOf(root)
    if (exceptions.any { samePath(it, root) }) return emptyList()
    val nested = exceptions.filter { pathInside(root, it) }
    if (nested.isEmpty()) return listOf(root)
    val names = linkedSetOf<String>()
    childrenOf(root).forEach { child ->
        val name = child.trimEnd('/').substringAfterLast('/')
        if (name.isNotEmpty()) names += name
    }
    nested.forEach { names += nextSegment(root, it) }
    if (nested.any { nextSegment(root, it) == "agents" || nextSegment(root, it) == "workspaces" }) {
        names += NUUM_HOST_CHILDREN
    }
    if (nested.any { nextSegment(root, it) == "scratch" }) {
        names += AGENT_HOST_CHILDREN
    }
    val result = mutableListOf<String>()
    for (name in names) {
        val child = joinPath(root, name)
        if (sealedPath(child)) {
            result += child
            continue
        }
        val under = nested.filter { samePath(it, child) || pathInside(child, it) }
        result += expandDenied(child, under, childrenOf, sealedPath)
    }
    return result
}

private fun directoryChildren(path: String): List<String> {
    val dir = File(path)
    if (!dir.isDirectory) return emptyList()
    return dir.listFiles()?.map { normalizePath(it.path) }?.sorted().orEmpty()
}

private fun nextSegment(root: String, descendant: String): String {
    val rest = descendant.removePrefix(root.trimEnd('/') + "/")
    return rest.substringBefore('/')
}

private fun joinPath(parent: String, name: String): String =
    if (parent == "/") "/$name" else parent.trimEnd('/') + "/" + name

private fun samePath(left: String, right: String): Boolean = left.trimEnd('/') == right.trimEnd('/')

private fun pathInside(root: String, path: String): Boolean {
    val base = root.trimEnd('/')
    val target = path.trimEnd('/')
    return base.isNotEmpty() && target.length > base.length && target.startsWith("$base/")
}
