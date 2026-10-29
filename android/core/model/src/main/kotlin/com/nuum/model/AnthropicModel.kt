package com.nuum.model

import com.nuum.contracts.ChatMessage
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.MessageRole
import com.nuum.contracts.ModelPort
import com.nuum.contracts.NormalizedChatRequest
import com.nuum.contracts.NormalizedChunk
import com.nuum.contracts.NuumException
import com.nuum.contracts.ProviderId
import java.util.UUID
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSource

const val ANTHROPIC_BASE_URL = "https://api.anthropic.com/v1"
const val ANTHROPIC_LABEL = "Anthropic"
internal const val ANTHROPIC_VERSION = "2023-06-01"
private const val DEFAULT_MAX_TOKENS = 4096

private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()

class AnthropicModel(
    private val client: OkHttpClient = defaultModelHttpClient(),
    val baseUrl: String = ANTHROPIC_BASE_URL
) : ModelPort {
    override fun streamChat(request: NormalizedChatRequest) = streamModel(
        client = client,
        apiKey = request.apiKey,
        providerWire = ProviderId.ANTHROPIC.wire,
        label = ANTHROPIC_LABEL,
        request = {
            Request.Builder()
                .url(joinUrl(baseUrl, "/messages"))
                .header("x-api-key", request.apiKey)
                .header("anthropic-version", ANTHROPIC_VERSION)
                .post(anthropicPayload(request).encode().toRequestBody(JSON_MEDIA))
                .build()
        },
        read = { source, emit -> readAnthropic(source, emit) }
    )
}

private fun anthropicPayload(request: NormalizedChatRequest): JsonObject {
    val system = request.messages
        .filter { it.role == MessageRole.SYSTEM }
        .joinToString("\n\n") { it.content }
    return buildJsonObject {
        put("model", request.model.model)
        put("max_tokens", request.maxOutputTokens ?: DEFAULT_MAX_TOKENS)
        put("stream", true)
        if (system.isNotEmpty()) put("system", system)
        put("messages", buildJsonArray {
            toAnthropicMessages(request.messages.filter { it.role != MessageRole.SYSTEM })
                .forEach { add(it) }
        })
        put("tools", buildJsonArray {
            request.tools.forEach { tool ->
                add(buildJsonObject {
                    put("name", tool.name)
                    put("description", tool.description)
                    put("input_schema", tool.inputSchema.toJsonObject())
                })
            }
        })
    }
}

private fun toAnthropicMessages(messages: List<ChatMessage>): List<JsonObject> {
    val out = mutableListOf<JsonObject>()
    for (message in messages) {
        when (message.role) {
            MessageRole.USER -> out += buildJsonObject {
                put("role", "user")
                val pictures = message.images
                if (!pictures.isNullOrEmpty()) {
                    put("content", buildJsonArray {
                        add(buildJsonObject {
                            put("type", "text")
                            put("text", message.content)
                        })
                        pictures.forEach { image ->
                            add(buildJsonObject {
                                put("type", "image")
                                put("source", buildJsonObject {
                                    put("type", "base64")
                                    put("media_type", image.mimeType)
                                    put("data", image.data)
                                })
                            })
                        }
                    })
                } else {
                    put("content", message.content)
                }
            }
            MessageRole.ASSISTANT -> out += buildJsonObject {
                put("role", "assistant")
                val blocks = buildJsonArray {
                    if (!message.thinking.isNullOrEmpty()) {
                        add(buildJsonObject {
                            put("type", "thinking")
                            put("thinking", message.thinking)
                        })
                    }
                    if (message.content.isNotEmpty()) {
                        add(buildJsonObject {
                            put("type", "text")
                            put("text", message.content)
                        })
                    }
                    val calls = message.toolCalls
                    calls.orEmpty().forEach { call ->
                        add(buildJsonObject {
                            put("type", "tool_use")
                            put("id", call.id)
                            put("name", call.name)
                            put("input", call.arguments.toJsonObject())
                        })
                    }
                }
                if (blocks.isNotEmpty()) put("content", blocks) else put("content", message.content)
            }
            MessageRole.TOOL -> out += buildJsonObject {
                put("role", "user")
                put("content", buildJsonArray {
                    add(buildJsonObject {
                        put("type", "tool_result")
                        put("tool_use_id", message.toolCallId.toJsonElement())
                        put("content", message.content)
                    })
                })
            }
            MessageRole.SYSTEM -> Unit
        }
    }
    return out
}

private suspend fun readAnthropic(
    source: BufferedSource,
    emit: suspend (NormalizedChunk) -> Unit
) {
    var toolId = ""
    var toolName = ""
    var toolArgs = ""
    while (true) {
        currentCoroutineContext().ensureActive()
        val line = source.readUtf8Line() ?: break
        val data = sseData(line) ?: continue
        if (data.isEmpty() || data == "[DONE]") continue
        val event = anthropicEvent(data)
        when (event["type"]?.stringOrNull()) {
            "content_block_delta" -> {
                val delta = event["delta"] as? JsonObject ?: continue
                when (delta["type"]?.stringOrNull()) {
                    "thinking_delta" -> {
                        val thinking = delta["thinking"]?.stringOrNull()
                        if (!thinking.isNullOrEmpty()) emit(NormalizedChunk.Thinking(thinking))
                    }
                    "text_delta" -> {
                        val text = delta["text"]?.stringOrNull()
                        if (!text.isNullOrEmpty()) emit(NormalizedChunk.Text(text))
                    }
                    "input_json_delta" -> {
                        toolArgs += delta["partial_json"]?.stringOrNull().orEmpty()
                    }
                }
            }
            "content_block_start" -> {
                val block = event["content_block"] as? JsonObject ?: continue
                if (block["type"]?.stringOrNull() == "tool_use") {
                    toolId = block["id"]?.stringOrNull()?.takeIf { it.isNotEmpty() }
                        ?: UUID.randomUUID().toString()
                    toolName = block["name"]?.stringOrNull().orEmpty()
                    toolArgs = ""
                }
            }
            "content_block_stop" -> {
                if (toolName.isNotEmpty()) {
                    emit(
                        NormalizedChunk.ToolCallChunk(
                            id = toolId,
                            name = toolName,
                            arguments = parseArgumentObject(toolArgs)
                        )
                    )
                    toolName = ""
                }
            }
        }
    }
}

private fun anthropicEvent(data: String): JsonObject {
    return try {
        ModelJson.parseToJsonElement(data) as? JsonObject
            ?: throw NuumException(KernelErrorCode.MODEL, "Anthropic returned a malformed stream event")
    } catch (e: NuumException) {
        throw e
    } catch (_: Exception) {
        throw NuumException(KernelErrorCode.MODEL, "Anthropic returned a malformed stream event")
    }
}
