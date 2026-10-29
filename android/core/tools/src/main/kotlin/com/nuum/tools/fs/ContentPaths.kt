package com.nuum.tools.fs

private val CONTENT_TREE = Regex("""^(content://[^/]+/tree/[^/]+)(?:/(.*))?$""")

internal fun splitTree(uri: String): Pair<String, String?> {
    val match = CONTENT_TREE.matchEntire(uri) ?: return uri to null
    val relative = match.groupValues[2].ifEmpty { null }
    return match.groupValues[1] to relative
}

internal fun normalizeContent(uri: String): String {
    val (root, relative) = splitTree(uri)
    if (relative == null) return root
    val parts = ArrayDeque<String>()
    for (part in relative.split('/')) {
        when (part) {
            "", "." -> Unit
            ".." -> if (parts.isEmpty()) return root else parts.removeLast()
            else -> parts.addLast(part)
        }
    }
    return if (parts.isEmpty()) root else root + "/" + parts.joinToString("/")
}

internal fun joinContent(cwd: String, input: String): String {
    if (input.isEmpty() || input == ".") return normalizeContent(cwd)
    val (root, relative) = splitTree(normalizeContent(cwd))
    val combined = listOfNotNull(relative, input.trimStart('/'))
        .filter { it.isNotEmpty() }
        .joinToString("/")
    return normalizeContent("$root/$combined")
}
