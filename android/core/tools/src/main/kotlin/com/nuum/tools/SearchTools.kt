package com.nuum.tools

import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.NuumException
import com.nuum.contracts.ToolDefinition
import com.nuum.contracts.ToolExecutionResult
import com.nuum.tools.fs.MissingPathException
import java.util.regex.PatternSyntaxException

internal object GlobTool : Tool {
    override val definition = ToolDefinition(
        name = "glob",
        description = "Find files recursively with a glob pattern and return newest matches first.",
        inputSchema = objectSchema(
            "glob_pattern" to mapOf("type" to "string"),
            "target_directory" to mapOf("type" to "string"),
            required = listOf("glob_pattern")
        ),
        mutating = false,
        action = LocalToolAction.LIST_DIRECTORY
    )

    override suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult {
        val pattern = stringField(input, "glob_pattern")!!
        val target = stringField(input, "target_directory", optional = true) ?: "."
        val root = sandbox.requireAllowed(LocalToolAction.LIST_DIRECTORY, target, withPeriod = true)
        val matches = mutableListOf<FoundFile>()
        collectFiles(sandbox, root) { found ->
            if (matchesGlob(found.relative, pattern)) matches += found
        }
        if (matches.isEmpty()) return ToolExecutionResult(ok = true, output = "No files matched.")
        matches.sortWith(compareByDescending<FoundFile> { it.modifiedMillis }.thenBy { it.path })
        val shown = matches.take(MAX_GLOB_RESULTS).map { it.path }.toMutableList()
        if (matches.size > shown.size) {
            shown += "[${matches.size - shown.size} more matches omitted.]"
        }
        return ToolExecutionResult(ok = true, output = shown.joinToString("\n"))
    }
}

internal object GrepTool : Tool {
    override val definition = ToolDefinition(
        name = "grep",
        description = "Search file contents recursively. Output is capped the same way as ripgrep; no external search program is launched.",
        inputSchema = objectSchema(
            "pattern" to mapOf("type" to "string"),
            "path" to mapOf("type" to "string"),
            "glob" to mapOf("type" to "string"),
            "type" to mapOf("type" to "string"),
            "output_mode" to mapOf("enum" to listOf("content", "files_with_matches", "count")),
            "-i" to mapOf("type" to "boolean"),
            "-A" to mapOf("type" to "integer", "minimum" to 0),
            "-B" to mapOf("type" to "integer", "minimum" to 0),
            "-C" to mapOf("type" to "integer", "minimum" to 0),
            "head_limit" to mapOf("type" to "integer", "minimum" to 1),
            "offset" to mapOf("type" to "integer", "minimum" to 0),
            "multiline" to mapOf("type" to "boolean"),
            required = listOf("pattern")
        ),
        mutating = false,
        action = LocalToolAction.READ_FILE
    )

    override suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult {
        val pattern = stringField(input, "pattern")!!
        val requested = stringField(input, "path", optional = true) ?: "."
        val root = sandbox.requireAllowed(LocalToolAction.READ_FILE, requested, withPeriod = true)
        val mode = enumField(
            input,
            "output_mode",
            listOf("content", "files_with_matches", "count"),
            "content"
        )
        val ignoreCase = booleanField(input, "-i") ?: false
        val multiline = booleanField(input, "multiline") ?: false
        val glob = stringField(input, "glob", optional = true)
        val type = stringField(input, "type", optional = true)
        val typeExtensions = type?.let { extensionsForType(it) }
        var beforeLines = integerField(input, "-B", min = 0) ?: 0
        var afterLines = integerField(input, "-A", min = 0) ?: 0
        val context = integerField(input, "-C", min = 0)
        if (context != null) {
            beforeLines = context
            afterLines = context
        }
        val regex = compilePattern(pattern, ignoreCase, multiline)
        val formatted = when (mode) {
            "files_with_matches" -> filesWithMatches(sandbox, root, regex, multiline, glob, typeExtensions)
            "count" -> counts(sandbox, root, regex, multiline, glob, typeExtensions)
            else -> contentLines(sandbox, root, regex, multiline, glob, typeExtensions, beforeLines, afterLines)
        }
        if (formatted.isEmpty()) return ToolExecutionResult(ok = true, output = "No matches found.")
        return ToolExecutionResult(ok = true, output = pageGrep(formatted, input))
    }
}

private data class FoundFile(val path: String, val relative: String, val modifiedMillis: Long)

private fun collectFiles(sandbox: RunSandbox, root: String, visit: (FoundFile) -> Unit) {
    if (!sandbox.exists(root)) {
        throw NuumException(KernelErrorCode.TOOL, "No such file: $root")
    }
    if (!sandbox.isDirectory(root)) {
        visit(FoundFile(root, root.substringAfterLast('/'), sandbox.lastModifiedMillis(root)))
        return
    }
    fun walk(directory: String) {
        val entries = try {
            sandbox.list(directory)
        } catch (_: MissingPathException) {
            return
        }
        for (entry in entries) {
            if (entry.isSymlink) continue
            val child = joinPath(directory, entry.name)
            if (entry.isDirectory) {
                walk(child)
            } else {
                visit(
                    FoundFile(
                        path = child,
                        relative = relativePath(root, child),
                        modifiedMillis = sandbox.lastModifiedMillis(child)
                    )
                )
            }
        }
    }
    walk(root)
}

private fun filesWithMatches(
    sandbox: RunSandbox,
    root: String,
    regex: Regex,
    multiline: Boolean,
    glob: String?,
    typeExtensions: Set<String>?
): List<String> {
    val paths = mutableListOf<String>()
    collectFiles(sandbox, root) { found ->
        if (acceptsFile(found.relative, glob, typeExtensions)) {
            val text = readSearchText(sandbox, found.path)
            if (text != null && hasMatch(text, regex, multiline)) paths += found.path
        }
    }
    paths.sort()
    return paths
}

private fun counts(
    sandbox: RunSandbox,
    root: String,
    regex: Regex,
    multiline: Boolean,
    glob: String?,
    typeExtensions: Set<String>?
): List<String> {
    val lines = mutableListOf<String>()
    collectFiles(sandbox, root) { found ->
        if (acceptsFile(found.relative, glob, typeExtensions)) {
            val text = readSearchText(sandbox, found.path)
            if (text != null) {
                val count = matchLineNumbers(text, regex, multiline).size
                if (count > 0) lines += "${found.path}:$count"
            }
        }
    }
    lines.sort()
    return lines
}

private fun contentLines(
    sandbox: RunSandbox,
    root: String,
    regex: Regex,
    multiline: Boolean,
    glob: String?,
    typeExtensions: Set<String>?,
    beforeLines: Int,
    afterLines: Int
): List<String> {
    val files = mutableListOf<FoundFile>()
    collectFiles(sandbox, root) { found ->
        if (acceptsFile(found.relative, glob, typeExtensions)) files += found
    }
    files.sortBy { it.path }
    val output = mutableListOf<String>()
    for (found in files) {
        val text = readSearchText(sandbox, found.path) ?: continue
        val fileLines = searchLines(text)
        val matches = matchLineNumbers(text, regex, multiline)
        if (matches.isEmpty()) continue
        val selected = contextIndexes(matches, beforeLines, afterLines, fileLines.size)
        var previous: Int? = null
        for (index in selected) {
            if (previous != null && index > previous + 1 && (beforeLines > 0 || afterLines > 0)) {
                output += "--"
            }
            val separator = if (index in matches) ":" else "-"
            output += "${found.path}$separator${index + 1}$separator${fileLines[index]}"
            previous = index
        }
    }
    return output
}

private fun pageGrep(lines: List<String>, input: Map<String, Any?>): String {
    val joined = lines.joinToString("\n")
    val truncated = joined.length > MAX_GREP_OUTPUT
    val capped = if (truncated) joined.take(MAX_GREP_OUTPUT) else joined
    val withNote = if (truncated) {
        "$capped\n[rg output truncated; narrow the pattern, glob, or result range.]"
    } else {
        capped
    }
    val outputLines = withNote.trimEnd().split('\n')
    val offset = integerField(input, "offset", min = 0) ?: 0
    val headLimit = integerField(input, "head_limit", min = 1)
    val end = if (headLimit == null) outputLines.size else (offset + headLimit).coerceAtMost(outputLines.size)
    if (offset >= outputLines.size || offset >= end) return "No matches in the requested result range."
    return outputLines.subList(offset, end).joinToString("\n")
}

private fun acceptsFile(relative: String, glob: String?, typeExtensions: Set<String>?): Boolean {
    if (glob != null && !matchesRgGlob(relative, glob)) return false
    if (typeExtensions != null && fileExtension(relative).removePrefix(".") !in typeExtensions) return false
    return true
}

private fun readSearchText(sandbox: RunSandbox, path: String): String? = try {
    val bytes = sandbox.readBytes(path)
    if (bytes.any { it == 0.toByte() }) null else bytes.toString(Charsets.UTF_8)
} catch (_: NuumException) {
    null
} catch (_: MissingPathException) {
    null
}

private fun hasMatch(text: String, regex: Regex, multiline: Boolean): Boolean {
    if (multiline) return regex.containsMatchIn(text)
    return searchLines(text).any { regex.containsMatchIn(it) }
}

private fun matchLineNumbers(text: String, regex: Regex, multiline: Boolean): List<Int> {
    if (!multiline) {
        return searchLines(text).mapIndexedNotNull { index, line ->
            if (regex.containsMatchIn(line)) index else null
        }
    }
    val found = mutableListOf<Int>()
    for (match in regex.findAll(text)) {
        val line = text.substring(0, match.range.first).count { it == '\n' }
        if (found.lastOrNull() != line) found += line
    }
    return found
}

private fun searchLines(text: String): List<String> {
    if (text.isEmpty()) return emptyList()
    val parts = text.split('\n')
    return if (text.endsWith('\n') && parts.last().isEmpty()) parts.dropLast(1) else parts
}

private fun contextIndexes(matches: List<Int>, before: Int, after: Int, lineCount: Int): List<Int> {
    val selected = sortedSetOf<Int>()
    for (match in matches) {
        val start = (match - before).coerceAtLeast(0)
        val end = (match + after).coerceAtMost(lineCount - 1)
        for (index in start..end) selected += index
    }
    return selected.toList()
}

private fun compilePattern(pattern: String, ignoreCase: Boolean, multiline: Boolean): Regex {
    val options = buildSet {
        if (ignoreCase) add(RegexOption.IGNORE_CASE)
        if (multiline) add(RegexOption.DOT_MATCHES_ALL)
    }
    return try {
        Regex(pattern, options)
    } catch (error: PatternSyntaxException) {
        throw NuumException(KernelErrorCode.TOOL, "Invalid regular expression: ${error.message}")
    }
}

private fun extensionsForType(type: String): Set<String> =
    FILE_TYPES[type] ?: throw NuumException(KernelErrorCode.TOOL, "Unrecognized file type: $type.")

private val FILE_TYPES: Map<String, Set<String>> = mapOf(
    "kt" to setOf("kt", "kts"),
    "kotlin" to setOf("kt", "kts"),
    "java" to setOf("java"),
    "js" to setOf("js", "mjs", "cjs", "jsx"),
    "ts" to setOf("ts", "tsx"),
    "py" to setOf("py"),
    "md" to setOf("md", "markdown"),
    "json" to setOf("json"),
    "xml" to setOf("xml"),
    "html" to setOf("html", "htm"),
    "css" to setOf("css"),
    "txt" to setOf("txt"),
    "yaml" to setOf("yaml", "yml"),
    "sh" to setOf("sh", "bash")
)
