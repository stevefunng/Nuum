package com.nuum.tools

internal fun parentPath(path: String): String {
    val trimmed = path.trimEnd('/')
    val slash = trimmed.lastIndexOf('/')
    if (slash <= 0) return if (trimmed.startsWith("/")) "/" else ""
    return trimmed.substring(0, slash)
}

internal fun pathContains(root: String, target: String): Boolean {
    if (root.isEmpty() || target.isEmpty()) return false
    if (root == "/") return target.startsWith("/")
    val normalizedRoot = root.trimEnd('/')
    val normalizedTarget = if (target.length > 1) target.trimEnd('/') else target
    return normalizedTarget == normalizedRoot || normalizedTarget.startsWith("$normalizedRoot/")
}

internal fun joinPath(parent: String, name: String): String {
    val base = if (parent == "/") "" else parent.trimEnd('/')
    return "$base/$name"
}

internal fun relativePath(root: String, full: String): String {
    if (full == root) return ""
    val prefix = if (root.endsWith("/")) root else "$root/"
    return if (full.startsWith(prefix)) full.removePrefix(prefix) else full
}

/** Extension including the leading dot, or empty when there is none. */
internal fun fileExtension(path: String): String {
    val name = path.substringAfterLast('/')
    val dot = name.lastIndexOf('.')
    if (dot <= 0) return ""
    return name.substring(dot).lowercase()
}

internal fun replaceLiteral(content: String, needle: String, replacement: String, all: Boolean): String {
    if (needle.isEmpty()) return content
    if (!all) {
        val index = content.indexOf(needle)
        if (index < 0) return content
        return content.substring(0, index) + replacement + content.substring(index + needle.length)
    }
    val out = StringBuilder()
    var cursor = 0
    while (cursor <= content.length) {
        val index = content.indexOf(needle, cursor)
        if (index < 0) {
            out.append(content, cursor, content.length)
            break
        }
        out.append(content, cursor, index)
        out.append(replacement)
        cursor = index + needle.length
    }
    return out.toString()
}

internal fun occurrenceCount(content: String, needle: String): Int {
    if (needle.isEmpty()) return 0
    var count = 0
    var cursor = 0
    while (true) {
        val index = content.indexOf(needle, cursor)
        if (index < 0) return count
        count += 1
        cursor = index + needle.length
    }
}

/**
 * First executable token, skipping `env` and leading `NAME=value` assignments.
 * Shell is not executed; this only shapes the approval target.
 */
internal fun commandToken(command: String): String {
    val tokens = Regex("""(?:[^\s"']+|"[^"]*"|'[^']*')+""")
        .findAll(command.trim())
        .map { it.value }
        .toList()
    val first = tokens.firstOrNull { token ->
        token != "env" && !Regex("""^[A-Za-z_][A-Za-z0-9_]*=""").containsMatchIn(token)
    } ?: return ""
    val stripped = first.replace(Regex("""^["']|["']$"""), "")
    return stripped.substringAfterLast('/').substringAfterLast('\\')
}
