package com.nuum.model

import com.nuum.contracts.MessageRole
import com.nuum.contracts.NormalizedChunk
import com.nuum.contracts.ProviderId
import com.nuum.contracts.ToolCall
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenAISseTest {
    @Test
    fun stitchesToolCallDeltasAndSendsImages() = runBlocking {
        val server = MockWebServer()
        server.start()
        try {
            server.enqueue(
                sseResponse(
                    """{"choices":[{"delta":{"content":"On it"}}]}""",
                    """{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_read","function":{"name":"re"}}]}}]}""",
                    """{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"ad","arguments":"{\"path\":"}}]}}]}""",
                    """{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"notes.txt\",\"force\":true}"}}]}}]}""",
                    """{"choices":[{"delta":{"tool_calls":[{"index":1,"id":"call_list","function":{"name":"list","arguments":"{}"}}]}}]}""",
                    "[DONE]"
                )
            )
            val port = providerModel(
                ProviderId.OPENAI,
                testClient(),
                openAiBaseUrl = server.baseUrl()
            )
            val chunks = port.streamChat(
                chatRequest(
                    provider = ProviderId.OPENAI,
                    model = "gpt-4o",
                    apiKey = OPENAI_KEY,
                    messages = listOf(
                        chatMessage(
                            MessageRole.USER,
                            "look",
                            images = listOf(pngImage())
                        ),
                        chatMessage(
                            MessageRole.ASSISTANT,
                            "",
                            id = "a1",
                            thinking = "plan",
                            toolCalls = listOf(ToolCall("call_old", "read", mapOf("path" to "old.txt")))
                        )
                    ),
                    maxOutputTokens = 128
                )
            ).toList()

            assertEquals(NormalizedChunk.Text("On it"), chunks[0])
            val readCall = chunks[1] as NormalizedChunk.ToolCallChunk
            assertEquals("call_read", readCall.id)
            assertEquals("read", readCall.name)
            assertEquals("notes.txt", readCall.arguments["path"])
            assertEquals(true, readCall.arguments["force"])
            val listCall = chunks[2] as NormalizedChunk.ToolCallChunk
            assertEquals("call_list", listCall.id)
            assertEquals("list", listCall.name)
            assertEquals(emptyMap<String, Any?>(), listCall.arguments)
            assertEquals(3, chunks.size)

            val recorded = server.takeRequest()
            assertEquals("/v1/chat/completions", recorded.path)
            assertEquals("Bearer $OPENAI_KEY", recorded.headers["Authorization"])
            val body = recorded.body.readUtf8()
            assertTrue(body.contains("data:image/png;base64,$IMAGE_PAYLOAD"))
            val root = Json.parseToJsonElement(body).jsonObject
            assertEquals("gpt-4o", root.string("model"))
            assertEquals(128, root["max_tokens"]!!.jsonPrimitive.content.toInt())
            val assistant = root["messages"]!!.jsonArray[1].jsonObject
            assertTrue(assistant["content"] is JsonNull)
            assertEquals("plan", assistant.string("reasoning_content"))
            val replayArgs = assistant["tool_calls"]!!.jsonArray[0].jsonObject["function"]!!
                .jsonObject.string("arguments")
            assertTrue(replayArgs.contains("old.txt"))
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun reasoningContentBecomesThinkingBeforeText() = runBlocking {
        val server = MockWebServer()
        server.start()
        try {
            server.enqueue(
                sseResponse(
                    """{"choices":[{"delta":{"reasoning_content":"plan","content":"hello"}}]}""",
                    "[DONE]"
                )
            )
            val model = OpenAIModel(testClient(), server.baseUrl(), OPENAI_LABEL)
            val chunks = model.streamChat(
                chatRequest(ProviderId.OPENAI, "gpt-4o", OPENAI_KEY)
            ).toList()
            assertEquals(
                listOf(NormalizedChunk.Thinking("plan"), NormalizedChunk.Text("hello")),
                chunks
            )
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun deepSeekOmitsImages() = runBlocking {
        val server = MockWebServer()
        server.start()
        try {
            server.enqueue(
                sseResponse(
                    """{"choices":[{"delta":{"reasoning_content":"skip the picture"}}]}""",
                    "[DONE]"
                )
            )
            val port = providerModel(
                ProviderId.DEEPSEEK,
                testClient(),
                deepSeekBaseUrl = server.baseUrl()
            )
            val chunks = port.streamChat(
                chatRequest(
                    provider = ProviderId.DEEPSEEK,
                    model = "deepseek-chat",
                    apiKey = DEEPSEEK_KEY,
                    messages = listOf(
                        chatMessage(MessageRole.USER, "look", images = listOf(pngImage()))
                    )
                )
            ).toList()
            assertEquals(listOf(NormalizedChunk.Thinking("skip the picture")), chunks)

            val recorded = server.takeRequest()
            assertEquals("Bearer $DEEPSEEK_KEY", recorded.headers["Authorization"])
            val body = recorded.body.readUtf8()
            assertFalse(body.contains(IMAGE_PAYLOAD))
            assertFalse(body.contains("image_url"))
            assertFalse(body.contains("base64"))
            assertTrue(body.contains("does not accept image input"))
            assertTrue(body.contains("look"))
        } finally {
            server.shutdown()
        }
    }
}

private fun JsonObject.string(name: String): String = getValue(name).jsonPrimitive.content
