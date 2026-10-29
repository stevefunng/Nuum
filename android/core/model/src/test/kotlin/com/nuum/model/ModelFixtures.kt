package com.nuum.model

import com.nuum.contracts.ChatMessage
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.MessageRole
import com.nuum.contracts.ModelImage
import com.nuum.contracts.ModelRef
import com.nuum.contracts.NormalizedChatRequest
import com.nuum.contracts.ProviderId
import com.nuum.contracts.ToolDefinition
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer

internal const val OPENAI_KEY = "sk-test-openai-key"
internal const val ANTHROPIC_KEY = "sk-ant-test-key"
internal const val DEEPSEEK_KEY = "sk-test-deepseek-key"
internal const val IMAGE_PAYLOAD = "NUUM_IMAGE_PAYLOAD_9f3c"

internal fun MockWebServer.baseUrl(): String = url("/v1").toString().trimEnd('/')

internal fun testClient(debugLog: ((String) -> Unit)? = null): OkHttpClient {
    return defaultModelHttpClient(debugLog).newBuilder()
        .connectTimeout(2, TimeUnit.SECONDS)
        .readTimeout(2, TimeUnit.SECONDS)
        .writeTimeout(2, TimeUnit.SECONDS)
        .build()
}

internal fun sseResponse(vararg dataLines: String): MockResponse {
    val payload = buildString {
        for (line in dataLines) {
            append("data: ")
            append(line)
            append("\n\n")
        }
    }
    return MockResponse()
        .addHeader("Content-Type", "text/event-stream; charset=utf-8")
        .setBody(payload)
}

internal fun chatMessage(
    role: MessageRole,
    content: String,
    id: String = "m-$role",
    images: List<ModelImage>? = null,
    thinking: String? = null,
    toolCalls: List<com.nuum.contracts.ToolCall>? = null,
    toolCallId: String? = null
) = ChatMessage(
    id = id,
    role = role,
    content = content,
    seq = 1,
    createdAt = 0L,
    images = images,
    thinking = thinking,
    toolCalls = toolCalls,
    toolCallId = toolCallId
)

internal fun readTool() = ToolDefinition(
    name = "read",
    description = "Read a file",
    inputSchema = mapOf(
        "type" to "object",
        "properties" to mapOf("path" to mapOf("type" to "string"))
    ),
    mutating = false,
    action = LocalToolAction.READ_FILE
)

internal fun chatRequest(
    provider: ProviderId,
    model: String,
    apiKey: String,
    messages: List<ChatMessage> = listOf(chatMessage(MessageRole.USER, "hello")),
    maxOutputTokens: Int? = null
) = NormalizedChatRequest(
    model = ModelRef(provider, model),
    messages = messages,
    tools = listOf(readTool()),
    apiKey = apiKey,
    maxOutputTokens = maxOutputTokens
)

internal fun pngImage() = ModelImage(mimeType = "image/png", data = IMAGE_PAYLOAD)
