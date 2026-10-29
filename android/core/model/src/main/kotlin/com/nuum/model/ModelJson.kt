package com.nuum.model

import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NuumException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.longOrNull

internal val ModelJson = Json { ignoreUnknownKeys = true }

internal fun JsonElement.encode(): String = ModelJson.encodeToString(JsonElement.serializer(), this)

internal fun Map<String, Any?>.toJsonObject(): JsonObject = buildJsonObject {
    for ((key, value) in this@toJsonObject) {
        put(key, value.toJsonElement())
    }
}

internal fun Any?.toJsonElement(): JsonElement = when (this) {
    null -> JsonNull
    is JsonElement -> this
    is String -> JsonPrimitive(this)
    is Boolean -> JsonPrimitive(this)
    is Int -> JsonPrimitive(this)
    is Long -> JsonPrimitive(this)
    is Float -> JsonPrimitive(this)
    is Double -> JsonPrimitive(this)
    is Number -> JsonPrimitive(toDouble())
    is Map<*, *> -> buildJsonObject {
        for ((key, value) in this@toJsonElement) {
            put(key.toString(), value.toJsonElement())
        }
    }
    is Iterable<*> -> buildJsonArray {
        for (item in this@toJsonElement) add(item.toJsonElement())
    }
    else -> JsonPrimitive(toString())
}

internal fun JsonElement.toKotlinValue(): Any? = when (this) {
    is JsonNull -> null
    is JsonPrimitive -> toPrimitive()
    is JsonObject -> toKotlinMap()
    is JsonArray -> map { it.toKotlinValue() }
}

internal fun JsonObject.toKotlinMap(): Map<String, Any?> {
    val map = linkedMapOf<String, Any?>()
    for ((key, value) in this) {
        map[key] = value.toKotlinValue()
    }
    return map
}

internal fun parseArgumentObject(raw: String): Map<String, Any?> {
    if (raw.isBlank()) return emptyMap()
    val element = try {
        ModelJson.parseToJsonElement(raw)
    } catch (_: Exception) {
        throw NuumException(KernelErrorCode.MODEL, "Model tool arguments were not valid JSON")
    }
    val obj = element as? JsonObject ?: return emptyMap()
    return obj.toKotlinMap()
}

private fun JsonPrimitive.toPrimitive(): Any {
    if (isString) return content
    booleanOrNull?.let { return it }
    if ('.' in content || 'e' in content || 'E' in content) {
        return content.toDoubleOrNull() ?: content
    }
    val asLong = longOrNull ?: return content
    return if (asLong in Int.MIN_VALUE..Int.MAX_VALUE) asLong.toInt() else asLong
}

internal fun JsonElement.stringOrNull(): String? = when (this) {
    is JsonNull -> null
    is JsonPrimitive -> if (isString) content else null
    else -> null
}

internal fun JsonElement.intOrNull(): Int? {
    val primitive = this as? JsonPrimitive ?: return null
    if (primitive.isString) return null
    val asLong = primitive.longOrNull ?: return null
    return if (asLong in Int.MIN_VALUE..Int.MAX_VALUE) asLong.toInt() else null
}
