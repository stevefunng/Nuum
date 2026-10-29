package com.nuum.protocol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Zod object schemas strip unknown keys. [StrictProtocolJson] is for the few
 * `.strict()` schemas (`ExternalOperation`, `WorkSendMessageParams`).
 *
 * `encodeDefaults = false` omits Kotlin default values, matching Zod
 * `.optional()` / `.default()` when the value was not set. Required nullable
 * fields have no Kotlin default, so `null` is still written (`binding`,
 * `defaultAgentId`, `projectRoot`).
 */
val ProtocolJson: Json = Json {
    ignoreUnknownKeys = true
    encodeDefaults = false
    explicitNulls = true
    classDiscriminator = "type"
}

val StrictProtocolJson: Json = Json {
    ignoreUnknownKeys = false
    encodeDefaults = false
    explicitNulls = true
    classDiscriminator = "type"
}

data class ProtocolIssue(val path: List<String>, val message: String)

class ProtocolParseException(val issues: List<ProtocolIssue>) : IllegalArgumentException(compact(issues)) {
    companion object {
        fun compact(issues: List<ProtocolIssue>): String = issues.joinToString("; ") { issue ->
            val path = issue.path.joinToString(".").ifEmpty { "(root)" }
            "$path: ${issue.message}"
        }
    }
}

/** Same shape the host returns to the model: `Tool: invalid arguments — path: message`. */
fun toolArgumentError(toolName: String, error: ProtocolParseException): String =
    "$toolName: invalid arguments — ${error.message}"

internal fun jsonObject(vararg pairs: Pair<String, Any?>): JsonObject =
    JsonObject(linkedMapOf(*pairs).mapValues { (_, value) -> value.toJsonElement() })

internal fun Any?.toJsonElement(): JsonElement = when (this) {
    null -> JsonNull
    is JsonElement -> this
    is String -> JsonPrimitive(this)
    is Boolean -> JsonPrimitive(this)
    is Int -> JsonPrimitive(this)
    is Long -> JsonPrimitive(this)
    is Double -> JsonPrimitive(this)
    is Float -> JsonPrimitive(this)
    is Map<*, *> -> JsonObject(entries.associate { (key, value) -> key.toString() to value.toJsonElement() })
    is Iterable<*> -> JsonArray(map { it.toJsonElement() })
    else -> JsonPrimitive(toString())
}
