package com.nuum.security

import com.nuum.contracts.Secrets
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * `{ openaiApiKey, anthropicApiKey, deepseekApiKey }` JSON, same shape as `Secrets`.
 * Null fields are omitted. Parser failures stay on a fixed message so a bad payload
 * cannot echo a key into the exception we surface.
 */
internal object SecretsCodec {
    private const val OPENAI = "openaiApiKey"
    private const val ANTHROPIC = "anthropicApiKey"
    private const val DEEPSEEK = "deepseekApiKey"

    fun encode(secrets: Secrets): ByteArray {
        val payload = buildJsonObject {
            secrets.openaiApiKey?.let { put(OPENAI, JsonPrimitive(it)) }
            secrets.anthropicApiKey?.let { put(ANTHROPIC, JsonPrimitive(it)) }
            secrets.deepseekApiKey?.let { put(DEEPSEEK, JsonPrimitive(it)) }
        }
        return Json.encodeToString(JsonObject.serializer(), payload).encodeToByteArray()
    }

    fun decode(bytes: ByteArray): Secrets {
        val element = try {
            Json.parseToJsonElement(bytes.decodeToString())
        } catch (_: SerializationException) {
            throw IllegalArgumentException("secrets payload is unreadable")
        }
        if (element !is JsonObject) {
            throw IllegalArgumentException("secrets payload is not an object")
        }
        return Secrets(
            openaiApiKey = element.optionalString(OPENAI),
            anthropicApiKey = element.optionalString(ANTHROPIC),
            deepseekApiKey = element.optionalString(DEEPSEEK)
        )
    }

    private fun JsonObject.optionalString(name: String): String? {
        val value = this[name] ?: return null
        if (value === JsonNull) return null
        if (value !is JsonPrimitive || !value.isString) {
            throw IllegalArgumentException("secrets field is not a string")
        }
        return value.content
    }
}
