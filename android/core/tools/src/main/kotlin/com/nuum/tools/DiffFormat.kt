package com.nuum.tools

internal data class FileMutation(
    val path: String,
    val before: String?,
    val after: String
)

internal fun formatMutation(mutation: FileMutation): String {
    val before = diffLines(mutation.before ?: "")
    val after = diffLines(mutation.after)
    var prefix = 0
    while (prefix < before.size && prefix < after.size && before[prefix] == after[prefix]) prefix += 1
    var suffix = 0
    while (
        suffix < before.size - prefix &&
        suffix < after.size - prefix &&
        before[before.size - suffix - 1] == after[after.size - suffix - 1]
    ) {
        suffix += 1
    }
    val removed = before.subList(prefix, before.size - suffix)
    val added = after.subList(prefix, after.size - suffix)
    val verb = when {
        mutation.before == null -> "Created"
        removed.isEmpty() && added.isEmpty() -> "Unchanged"
        else -> "Updated"
    }
    val headline = "$verb ${mutation.path} (+${added.size}/-${removed.size})"
    if (removed.isEmpty() && added.isEmpty()) return headline
    val preview = buildList {
        add("@@ -${prefix + 1},${removed.size} +${prefix + 1},${added.size} @@")
        if (prefix > 0) add(" ${before[prefix - 1]}")
        removed.forEach { add("-$it") }
        added.forEach { add("+$it") }
        if (suffix > 0) add(" ${before[before.size - suffix]}")
    }.joinToString("\n")
    val output = "$headline\n$preview"
    if (output.length <= MAX_DIFF_CHARS) return output
    return output.take(MAX_DIFF_CHARS) +
        "\n[Diff truncated; read ${mutation.path} to inspect the complete result.]"
}

private fun diffLines(content: String): List<String> =
    if (content.isEmpty()) emptyList() else content.split('\n')
