package com.nuum.model

import com.nuum.contracts.MessageRole
import com.nuum.contracts.NormalizedChunk
import com.nuum.contracts.ProviderId
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AnthropicSseTest {
    @Test
    fun thinkingDeltaAndInputJsonDelta() = runBlocking {
        val server = MockWebServer()
        server.start()
        try {
            server.enqueue(
                sseResponse(
                    """{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"plan"}}""",
                    """{"type":"content_block_delta","delta":{"type":"text_delta","text":"hello"}}""",
                    """{"type":"content_block_start","content_block":{"type":"tool_use","id":"toolu_1","name":"read"}}""",
                    """{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}""",
                    """{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"\"notes.md\"}"}}""",
                    """{"type":"content_block_stop"}"""
                )
            )
            val port = providerModel(
                ProviderId.ANTHROPIC,
                testClient(),
                anthropicBaseUrl = server.baseUrl()
            )
            val chunks = port.streamChat(
                chatRequest(
                    provider = ProviderId.ANTHROPIC,
                    model = "claude-sonnet-4-20250514",
                    apiKey = ANTHROPIC_KEY,
                    messages = listOf(
                        chatMessage(MessageRole.SYSTEM, "You are Nuum", id = "s1"),
                        chatMessage(MessageRole.SYSTEM, "Be brief", id = "s2"),
                        chatMessage(MessageRole.USER, "look", images = listOf(pngImage()))
                    )
                )
            ).toList()

            assertEquals(NormalizedChunk.Thinking("plan"), chunks[0])
            assertEquals(NormalizedChunk.Text("hello"), chunks[1])
            val tool = chunks[2] as NormalizedChunk.ToolCallChunk
            assertEquals("toolu_1", tool.id)
            assertEquals("read", tool.name)
            assertEquals("notes.md", tool.arguments["path"])
            assertEquals(3, chunks.size)

            val recorded = server.takeRequest()
            assertEquals("/v1/messages", recorded.path)
            assertEquals(ANTHROPIC_KEY, recorded.headers["x-api-key"])
            assertEquals(ANTHROPIC_VERSION, recorded.headers["anthropic-version"])
            assertTrue(recorded.headers["Authorization"] == null)
            val root = Json.parseToJsonElement(recorded.body.readUtf8()).jsonObject
            assertEquals("You are Nuum\n\nBe brief", root.getValue("system").jsonPrimitive.content)
            assertEquals(4096, root.getValue("max_tokens").jsonPrimitive.content.toInt())
            val messages = root.getValue("messages").jsonArray
            assertEquals(1, messages.size)
            assertEquals("user", messages[0].jsonObject.getValue("role").jsonPrimitive.content)
            val raw = root.toString()
            assertTrue(raw.contains(IMAGE_PAYLOAD))
            assertTrue(raw.contains("base64"))
            assertFalse(messages.toString().contains("\"role\":\"system\""))
            val schema = root.getValue("tools").jsonArray[0].jsonObject.getValue("input_schema").jsonObject
            assertEquals("object", schema.getValue("type").jsonPrimitive.content)
        } finally {
            server.shutdown()
        }
    }
}
