package com.nuum.kernel

import com.nuum.contracts.ChatMessage
import com.nuum.contracts.ToolCall
import com.nuum.contracts.ToolDefinition
import kotlin.math.ceil

/**
 * Conservative fallback, not a provider tokenizer. Mirrors
 * `packages/protocol/src/context-budget.ts`: images are stripped from the JSON
 * envelope and each one adds 8192 tokens.
 *
 * Lives here until `:core:protocol` owns the same function. Key order does not
 * change the count; null optional fields are omitted the way `JSON.stringify`
 * omits `undefined`.
 */
internal fun estimateModelTokens(
    messages: List<ChatMessage>,
    tools: List<ToolDefinition> = emptyList()
): Int {
    val text = buildString {
        append("{\"messages\":")
        append('[')
        messages.forEachIndexed { index, message ->
            if (index > 0) append(',')
            appendEstimateMessage(message)
        }
        append("],\"tools\":")
        append('[')
        tools.forEachIndexed { index, tool ->
            if (index > 0) append(',')
            appendEstimateTool(tool)
        }
        append("]}")
    }
    val wide = text.count { it.code > 0x7f }
    val textTokens = ceil((text.length - wide) / 3.0 + wide * 2.0).toInt()
    val imageTokens = messages.sumOf { message -> (message.images?.size ?: 0) * 8192 }
    return textTokens + imageTokens
}

private fun StringBuilder.appendEstimateMessage(message: ChatMessage) {
    append("{\"id\":")
    appendJsonString(message.id)
    append(",\"role\":")
    appendJsonString(message.role.wire)
    append(",\"content\":")
    appendJsonString(message.content)
    val thinking = message.thinking
    if (thinking != null) {
        append(",\"thinking\":")
        appendJsonString(thinking)
    }
    val calls = message.toolCalls?.takeIf { it.isNotEmpty() }
    if (calls != null) {
        append(",\"toolCalls\":[")
        calls.forEachIndexed { index, call ->
            if (index > 0) append(',')
            appendEstimateToolCall(call)
        }
        append(']')
    }
    val toolCallId = message.toolCallId
    if (toolCallId != null) {
        append(",\"toolCallId\":")
        appendJsonString(toolCallId)
    }
    val name = message.name
    if (name != null) {
        append(",\"name\":")
        appendJsonString(name)
    }
    append(",\"seq\":")
    append(message.seq)
    append(",\"createdAt\":")
    append(message.createdAt)
    append('}')
}

private fun StringBuilder.appendEstimateToolCall(call: ToolCall) {
    append("{\"id\":")
    appendJsonString(call.id)
    append(",\"name\":")
    appendJsonString(call.name)
    append(",\"arguments\":")
    appendJson(call.arguments)
    append('}')
}

private fun StringBuilder.appendEstimateTool(tool: ToolDefinition) {
    append("{\"name\":")
    appendJsonString(tool.name)
    append(",\"description\":")
    appendJsonString(tool.description)
    append(",\"inputSchema\":")
    appendJson(tool.inputSchema)
    append(",\"mutating\":")
    append(if (tool.mutating) "true" else "false")
    val action = tool.action
    if (action != null) {
        append(",\"action\":")
        appendJsonString(action.wire)
    }
    append('}')
}

private fun StringBuilder.appendJson(value: Any?) {
    when (value) {
        null -> append("null")
        is String -> appendJsonString(value)
        is Boolean -> append(if (value) "true" else "false")
        is Int, is Long, is Short, is Byte -> append(value.toString())
        is Double -> appendJsonNumber(value)
        is Float -> appendJsonNumber(value.toDouble())
        is Map<*, *> -> {
            append('{')
            var first = true
            for ((key, nested) in value) {
                if (!first) append(',')
                first = false
                appendJsonString(key.toString())
                append(':')
                appendJson(nested)
            }
            append('}')
        }
        is List<*> -> {
            append('[')
            value.forEachIndexed { index, nested ->
                if (index > 0) append(',')
                appendJson(nested)
            }
            append(']')
        }
        is Array<*> -> appendJson(value.asList())
        else -> throw IllegalArgumentException("Unsupported JSON value: ${value.javaClass.name}")
    }
}

private fun StringBuilder.appendJsonNumber(value: Double) {
    if (!value.isFinite()) {
        append("null")
        return
    }
    if (value % 1.0 == 0.0 && value <= MAX_SAFE_INTEGER && value >= -MAX_SAFE_INTEGER) {
        append(value.toLong())
    } else {
        append(value.toString())
    }
}

private fun StringBuilder.appendJsonString(value: String) {
    append('"')
    for (ch in value) {
        when (ch) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\b' -> append("\\b")
            '\u000C' -> append("\\f")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> if (ch.code < 0x20) {
                append("\\u")
                append(ch.code.toString(16).padStart(4, '0'))
            } else {
                append(ch)
            }
        }
    }
    append('"')
}

private const val MAX_SAFE_INTEGER = 9007199254740991.0
