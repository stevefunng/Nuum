package com.nuum.model

import com.nuum.contracts.ChatMessage
import com.nuum.contracts.MessageRole
import com.nuum.contracts.ModelPort
import com.nuum.contracts.NormalizedChatRequest
import com.nuum.contracts.NormalizedChunk
import com.nuum.contracts.ProviderId
import java.util.UUID
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSource

const val OPENAI_BASE_URL = "https://api.openai.com/v1"
const val DEEPSEEK_BASE_URL = "https://api.deepseek.com/v1"
const val OPENAI_LABEL = "OpenAI"
const val DEEPSEEK_LABEL = "DeepSeek"

/**
 * 和 Mac 一样的省略句。DeepSeek 路径只放这句话，不放图片字节。
 */
internal const val IMAGE_OMITTED_SUFFIX =
    "\n[Image content omitted because this model provider does not accept image input.]"

private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()

/**
 * OpenAI 与 DeepSeek 共用 chat completions。DeepSeek 的 [label] 是 [DEEPSEEK_LABEL]，不上传图片。
 */
class OpenAIModel(
    private val client: OkHttpClient = defaultModelHttpClient(),
    val baseUrl: String = OPENAI_BASE_URL,
    val label: String = OPENAI_LABEL
) : ModelPort {
    private val supportsImages: Boolean get() = label != DEEPSEEK_LABEL

    override fun streamChat(request: NormalizedChatRequest) = streamModel(
        client = client,
        apiKey = request.apiKey,
        providerWire = if (supportsImages) ProviderId.OPENAI.wire else ProviderId.DEEPSEEK.wire,
        label = label,
        request = {
            Request.Builder()
                .url(joinUrl(baseUrl, "/chat/completions"))
                .header("Authorization", "Bearer ${request.apiKey}")
                .post(openAiPayload(request, supportsImages).encode().toRequestBody(JSON_MEDIA))
                .build()
        },
        read = { source, emit -> readOpenAi(source, emit) }
    )
}

private fun openAiPayload(request: NormalizedChatRequest, supportsImages: Boolean): JsonObject = buildJsonObject {
    put("model", request.model.model)
    put("stream", true)
    val maxTokens = request.maxOutputTokens
    if (maxTokens != null && maxTokens != 0) put("max_tokens", maxTokens)
    put("messages", buildJsonArray {
        request.messages.forEach { add(it.toOpenAiMessage(supportsImages)) }
    })
    put("tools", buildJsonArray {
        request.tools.forEach { tool ->
            add(buildJsonObject {
                put("type", "function")
                put("function", buildJsonObject {
                    put("name", tool.name)
                    put("description", tool.description)
                    put("parameters", tool.inputSchema.toJsonObject())
                })
            })
        }
    })
}

internal fun ChatMessage.toOpenAiMessage(supportsImages: Boolean): JsonObject {
    if (role == MessageRole.TOOL) {
        return buildJsonObject {
            put("role", "tool")
            put("tool_call_id", toolCallId.toJsonElement())
            put("content", content)
        }
    }
    if (role == MessageRole.ASSISTANT) {
        return buildJsonObject {
            put("role", "assistant")
            val contentValue = when {
                content.isNotEmpty() -> JsonPrimitive(content)
                !toolCalls.isNullOrEmpty() -> JsonNull
                else -> JsonPrimitive("")
            }
            put("content", contentValue)
            if (!thinking.isNullOrEmpty()) put("reasoning_content", thinking)
            val calls = toolCalls
            if (!calls.isNullOrEmpty()) {
                put("tool_calls", buildJsonArray {
                    calls.forEach { call ->
                        add(buildJsonObject {
                            put("id", call.id)
                            put("type", "function")
                            put("function", buildJsonObject {
                                put("name", call.name)
                                put("arguments", call.arguments.toJsonObject().encode())
                            })
                        })
                    }
                })
            }
        }
    }
    val pictures = images
    if (role == MessageRole.USER && !pictures.isNullOrEmpty() && supportsImages) {
        return buildJsonObject {
            put("role", "user")
            put("content", buildJsonArray {
                add(buildJsonObject {
                    put("type", "text")
                    put("text", content)
                })
                pictures.forEach { image ->
                    add(buildJsonObject {
                        put("type", "image_url")
                        put("image_url", buildJsonObject {
                            put("url", "data:${image.mimeType};base64,${image.data}")
                        })
                    })
                }
            })
        }
    }
    val suffix = if (!pictures.isNullOrEmpty() && !supportsImages) IMAGE_OMITTED_SUFFIX else ""
    return buildJsonObject {
        put("role", role.wire)
        put("content", content + suffix)
    }
}

private data class AccumulatedTool(
    var id: String = "",
    var name: String = "",
    var args: String = ""
)

private suspend fun readOpenAi(
    source: BufferedSource,
    emit: suspend (NormalizedChunk) -> Unit
) {
    val tools = linkedMapOf<Int, AccumulatedTool>()
    while (true) {
        currentCoroutineContext().ensureActive()
        val line = source.readUtf8Line() ?: break
        val data = sseData(line) ?: continue
        if (data.isEmpty()) continue
        if (data == "[DONE]") break
        val delta = openAiDelta(data) ?: continue
        for (chunk in textChunksFromDelta(delta)) emit(chunk)
        accumulateToolCalls(tools, delta)
    }
    for (call in tools.values) {
        emit(
            NormalizedChunk.ToolCallChunk(
                id = call.id.ifEmpty { UUID.randomUUID().toString() },
                name = call.name,
                arguments = parseArgumentObject(call.args)
            )
        )
    }
}

internal fun textChunksFromDelta(delta: JsonObject): List<NormalizedChunk> {
    val out = mutableListOf<NormalizedChunk>()
    val reasoning = delta["reasoning_content"]?.stringOrNull()
    if (!reasoning.isNullOrEmpty()) out += NormalizedChunk.Thinking(reasoning)
    val content = delta["content"]?.stringOrNull()
    if (!content.isNullOrEmpty()) out += NormalizedChunk.Text(content)
    return out
}

private fun openAiDelta(data: String): JsonObject? {
    val root = try {
        ModelJson.parseToJsonElement(data) as? JsonObject
    } catch (_: Exception) {
        throw com.nuum.contracts.NuumException(
            com.nuum.contracts.KernelErrorCode.MODEL,
            "OpenAI returned a malformed stream event"
        )
    } ?: return null
    val choices = root["choices"] as? JsonArray ?: return null
    val first = choices.firstOrNull() as? JsonObject ?: return null
    return first["delta"] as? JsonObject
}

private fun accumulateToolCalls(tools: MutableMap<Int, AccumulatedTool>, delta: JsonObject) {
    val calls = delta["tool_calls"] as? JsonArray ?: return
    for (element in calls) {
        val call = element as? JsonObject ?: continue
        val index = call["index"]?.intOrNull() ?: continue
        val current = tools.getOrPut(index) { AccumulatedTool() }
        call["id"]?.stringOrNull()?.takeIf { it.isNotEmpty() }?.let { current.id = it }
        val function = call["function"] as? JsonObject ?: continue
        function["name"]?.stringOrNull()?.takeIf { it.isNotEmpty() }?.let { current.name += it }
        function["arguments"]?.stringOrNull()?.takeIf { it.isNotEmpty() }?.let { current.args += it }
    }
}
