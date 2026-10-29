package com.nuum.tools

import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.ModelImage
import com.nuum.contracts.NuumException
import com.nuum.contracts.ToolDefinition
import com.nuum.contracts.ToolExecutionResult
import com.nuum.tools.fs.ToolDirEntry
import java.util.Base64

private val IMAGE_MIME_TYPES = mapOf(
    ".jpg" to "image/jpeg",
    ".jpeg" to "image/jpeg",
    ".png" to "image/png",
    ".gif" to "image/gif",
    ".webp" to "image/webp"
)

internal object ReadTool : Tool {
    override val definition = ToolDefinition(
        name = "read",
        description = "Read a UTF-8 file, optionally by one-based line range and with line numbers.",
        inputSchema = objectSchema(
            "path" to mapOf("type" to "string"),
            "offset" to mapOf("type" to "integer", "minimum" to 1),
            "limit" to mapOf("type" to "integer", "minimum" to 1),
            "include_line_numbers" to mapOf("type" to "boolean"),
            required = listOf("path")
        ),
        mutating = false,
        action = LocalToolAction.READ_FILE
    )

    override suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult {
        val filePath = stringField(input, "path")!!
        val mimeType = IMAGE_MIME_TYPES[fileExtension(filePath)]
        if (mimeType != null) {
            if (input["offset"] != null || input["limit"] != null) {
                throw NuumException(KernelErrorCode.INVALID, "offset and limit are not supported for image files.")
            }
            val image = sandbox.readBinary(filePath)
            return ToolExecutionResult(
                ok = true,
                output = "Read image file: ${image.path}",
                images = listOf(
                    ModelImage(
                        mimeType = mimeType,
                        data = Base64.getEncoder().encodeToString(image.data)
                    )
                )
            )
        }
        val offset = integerField(input, "offset", min = 1) ?: 1
        val limit = integerField(input, "limit", min = 1)
        val includeLineNumbers = booleanField(input, "include_line_numbers") ?: false
        val content = sandbox.readText(filePath)
        return ToolExecutionResult(
            ok = true,
            output = renderRead(filePath, content, offset, limit, includeLineNumbers)
        )
    }
}

internal fun renderRead(
    filePath: String,
    content: String,
    offset: Int,
    limit: Int?,
    includeLineNumbers: Boolean
): String {
    if (content.isEmpty()) return "File is empty."
    if (content.contains('\u0000')) {
        throw NuumException(KernelErrorCode.TOOL, "Cannot read binary file as UTF-8 text: $filePath")
    }
    val all = content.split('\n')
    if (offset > all.size) {
        return "[Offset $offset is beyond the end of $filePath (${all.size} lines).]"
    }
    val requestedEnd = minOf(all.size, offset - 1 + (limit ?: all.size))
    val selected = all.subList(offset - 1, requestedEnd)
    val rendered = selected.mapIndexed { index, line ->
        if (includeLineNumbers) "${offset + index}|$line" else line
    }
    val kept = mutableListOf<String>()
    var characters = 0
    for (line in rendered) {
        val next = line.length + if (kept.isNotEmpty()) 1 else 0
        if (characters + next > MAX_READ_CHARS) break
        kept += line
        characters += next
    }
    if (kept.isEmpty()) {
        val slice = rendered[0].take(MAX_READ_CHARS)
        return "$slice\n\n[Line $offset was truncated because it alone exceeds the read budget. Use grep to narrow the content.]"
    }
    val actualEnd = offset + kept.size - 1
    if (kept.size < rendered.size) {
        return kept.joinToString("\n") +
            "\n\n[Output truncated at line $actualEnd of ${all.size}. Call read again with offset=${actualEnd + 1}.]"
    }
    if (offset != 1 || requestedEnd != all.size) {
        val remaining = all.size - requestedEnd
        val shown = if (offset == requestedEnd) "line $offset" else "lines $offset-$requestedEnd"
        val remainder = if (remaining == 1) "1 line remains" else "$remaining lines remain"
        return kept.joinToString("\n") + "\n\n[Showing $shown of ${all.size}. $remainder.]"
    }
    return kept.joinToString("\n")
}

internal object WriteTool : Tool {
    override val definition = ToolDefinition(
        name = "write",
        description = "Create or overwrite a UTF-8 file and return a compact diff.",
        inputSchema = objectSchema(
            "path" to mapOf("type" to "string"),
            "content" to mapOf("type" to "string"),
            required = listOf("path", "content")
        ),
        mutating = true,
        action = LocalToolAction.WRITE_FILE
    )

    override suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult {
        val mutation = sandbox.writeText(
            stringField(input, "path")!!,
            stringField(input, "content", allowEmpty = true)!!
        )
        return ToolExecutionResult(ok = true, output = formatMutation(mutation))
    }
}

internal object StrReplaceTool : Tool {
    override val definition = ToolDefinition(
        name = "str_replace",
        description = "Replace exact text in a file; the match must be unique unless replace_all is true.",
        inputSchema = objectSchema(
            "path" to mapOf("type" to "string"),
            "old_string" to mapOf("type" to "string"),
            "new_string" to mapOf("type" to "string"),
            "replace_all" to mapOf("type" to "boolean"),
            required = listOf("path", "old_string", "new_string")
        ),
        mutating = true,
        action = LocalToolAction.WRITE_FILE
    )

    override suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult {
        val filePath = stringField(input, "path")!!
        val oldString = stringField(input, "old_string")!!
        val newString = stringField(input, "new_string", allowEmpty = true)!!
        val replaceAll = booleanField(input, "replace_all") ?: false
        var replaced = 0
        val mutation = sandbox.mutateText(filePath) { current ->
            replaced = occurrenceCount(current, oldString)
            assertReplaceable(filePath, replaced, replaceAll)
            replaceLiteral(current, oldString, newString, replaceAll)
        }
        val noun = if (replaced == 1) "occurrence" else "occurrences"
        return ToolExecutionResult(
            ok = true,
            output = "Replaced $replaced $noun.\n${formatMutation(mutation)}"
        )
    }
}

internal object MultiStrReplaceTool : Tool {
    override val definition = ToolDefinition(
        name = "multi_str_replace",
        description = "Apply several exact replacements to one file in a single atomic write.",
        inputSchema = jsonMap(
            "type" to "object",
            "properties" to jsonMap(
                "path" to jsonMap("type" to "string"),
                "edits" to jsonMap(
                    "type" to "array",
                    "minItems" to 1,
                    "items" to jsonMap(
                        "type" to "object",
                        "properties" to jsonMap(
                            "old_string" to jsonMap("type" to "string"),
                            "new_string" to jsonMap("type" to "string"),
                            "replace_all" to jsonMap("type" to "boolean")
                        ),
                        "required" to listOf("old_string", "new_string")
                    )
                )
            ),
            "required" to listOf("path", "edits")
        ),
        mutating = true,
        action = LocalToolAction.WRITE_FILE
    )

    override suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult {
        val filePath = stringField(input, "path")!!
        val edits = parseEdits(input["edits"])
        val mutation = sandbox.mutateText(filePath) { original ->
            var next = original
            for ((index, edit) in edits.withIndex()) {
                val matches = occurrenceCount(next, edit.oldString)
                try {
                    assertReplaceable(filePath, matches, edit.replaceAll)
                } catch (error: NuumException) {
                    throw NuumException(error.code, "Edit ${index + 1}: ${error.message}")
                }
                next = replaceLiteral(next, edit.oldString, edit.newString, edit.replaceAll)
            }
            next
        }
        return ToolExecutionResult(ok = true, output = "Applied ${edits.size} edits.\n${formatMutation(mutation)}")
    }
}

internal object DeleteTool : Tool {
    override val definition = ToolDefinition(
        name = "delete",
        description = "Delete a file or directory tree.",
        inputSchema = objectSchema(
            "path" to mapOf("type" to "string"),
            required = listOf("path")
        ),
        mutating = true,
        action = LocalToolAction.WRITE_FILE
    )

    override suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult {
        val result = sandbox.deletePath(stringField(input, "path")!!)
        return ToolExecutionResult(ok = true, output = "Deleted ${result.kind}: ${result.path}")
    }
}

internal object LsTool : Tool {
    override val definition = ToolDefinition(
        name = "ls",
        description = "Render a directory tree within a bounded output budget.",
        inputSchema = objectSchema("path" to mapOf("type" to "string")),
        mutating = false,
        action = LocalToolAction.LIST_DIRECTORY
    )

    override suspend fun execute(input: Map<String, Any?>, sandbox: RunSandbox): ToolExecutionResult {
        val requested = stringField(input, "path", optional = true) ?: "."
        val root = sandbox.requireAllowed(LocalToolAction.LIST_DIRECTORY, requested, withPeriod = true)
        val label = root.substringAfterLast('/').ifEmpty { root }
        val output = mutableListOf("$label/")
        var used = output[0].length
        var truncated = false

        fun visit(directory: String, prefix: String) {
            if (truncated) return
            val entries = sandbox.list(directory).sortedWith(directoryOrder)
            for ((index, entry) in entries.withIndex()) {
                val last = index == entries.lastIndex
                val suffix = when {
                    entry.isDirectory -> "/"
                    entry.isSymlink -> "@"
                    else -> ""
                }
                val connector = if (last) "└── " else "├── "
                val line = "$prefix$connector${entry.name}$suffix"
                if (used + line.length + 1 > MAX_TREE_CHARS) {
                    truncated = true
                    return
                }
                output += line
                used += line.length + 1
                if (entry.isDirectory) {
                    val nextPrefix = prefix + if (last) "    " else "│   "
                    visit(joinPath(directory, entry.name), nextPrefix)
                }
            }
        }

        visit(root, "")
        if (truncated) output += "[Directory tree truncated at $MAX_TREE_CHARS characters.]"
        return ToolExecutionResult(ok = true, output = output.joinToString("\n"))
    }
}

private val directoryOrder = compareBy<ToolDirEntry> { !it.isDirectory }.thenBy { it.name }

private fun assertReplaceable(filePath: String, matches: Int, replaceAll: Boolean) {
    if (matches == 0) {
        throw NuumException(
            KernelErrorCode.TOOL,
            "old_string matched 0 times in $filePath. Read the file again and copy the exact text before retrying."
        )
    }
    if (!replaceAll && matches != 1) {
        throw NuumException(
            KernelErrorCode.TOOL,
            "old_string matched $matches times in $filePath. Include more surrounding context to make it unique, or set replace_all=true."
        )
    }
}

private data class TextEdit(val oldString: String, val newString: String, val replaceAll: Boolean)

private fun parseEdits(raw: Any?): List<TextEdit> {
    if (raw !is List<*> || raw.isEmpty()) {
        throw NuumException(KernelErrorCode.INVALID, "edits must be a non-empty array.")
    }
    return raw.mapIndexed { index, value ->
        val edit = asStringKeyMap(value)
            ?: throw NuumException(KernelErrorCode.INVALID, "edits[$index] must be an object.")
        TextEdit(
            oldString = stringField(edit, "old_string")!!,
            newString = stringField(edit, "new_string", allowEmpty = true)!!,
            replaceAll = booleanField(edit, "replace_all") ?: false
        )
    }
}

internal fun asStringKeyMap(value: Any?): Map<String, Any?>? {
    if (value !is Map<*, *>) return null
    val out = LinkedHashMap<String, Any?>()
    for ((key, item) in value) {
        if (key !is String) return null
        out[key] = item
    }
    return out
}

internal fun jsonMap(vararg pairs: Pair<String, Any?>): Map<String, Any?> = mapOf(*pairs)

internal fun objectSchema(
    vararg properties: Pair<String, Any?>,
    required: List<String> = emptyList()
): Map<String, Any?> {
    val body = linkedMapOf<String, Any?>(
        "type" to "object",
        "properties" to mapOf(*properties)
    )
    if (required.isNotEmpty()) body["required"] = required
    return body
}
