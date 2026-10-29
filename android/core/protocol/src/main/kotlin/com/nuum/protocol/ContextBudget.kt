package com.nuum.protocol

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.math.ceil

private const val IMAGE_TOKEN_COST = 8192

/**
 * Conservative budget, not a provider tokenizer.
 * Image bytes are removed from the JSON, then each image adds [IMAGE_TOKEN_COST].
 * ASCII is about 3 characters per token; non-ASCII is about 2 characters per token.
 */
fun estimateModelTokens(messages: List<ChatMessage>, tools: List<ToolDefinition> = emptyList()): Int {
    val payload = buildJsonObject {
        put("messages", JsonArray(messages.map { it.toBudgetJson() }))
        put("tools", JsonArray(tools.map { it.toBudgetJson() }))
    }
    val text = payload.toString()
    val wide = text.count { it.code > 0x7f }
    val body = ceil((text.length - wide) / 3.0 + wide * 2.0).toInt()
    val images = messages.sumOf { message -> (message.images?.size ?: 0) * IMAGE_TOKEN_COST }
    return body + images
}

private fun ChatMessage.toBudgetJson(): JsonObject = buildJsonObject {
    put("id", id)
    put("role", ProtocolJson.encodeToString(MessageRole.serializer(), role).trim('"'))
    put("content", content)
    thinking?.let { put("thinking", it) }
    toolCalls?.let { calls ->
        put("toolCalls", JsonArray(calls.map { call ->
            buildJsonObject {
                put("id", call.id)
                put("name", call.name)
                put("arguments", call.arguments)
            }
        }))
    }
    toolCallId?.let { put("toolCallId", it) }
    name?.let { put("name", it) }
    put("seq", seq)
    put("createdAt", createdAt)
}

private fun ToolDefinition.toBudgetJson(): JsonObject = buildJsonObject {
    put("name", name)
    put("description", description)
    put("inputSchema", inputSchema)
    put("mutating", mutating)
    action?.let { put("action", ProtocolJson.encodeToString(LocalToolAction.serializer(), it).trim('"')) }
}
