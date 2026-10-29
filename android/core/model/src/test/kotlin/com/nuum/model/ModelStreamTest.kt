package com.nuum.model

import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.ModelRef
import com.nuum.contracts.NuumException
import com.nuum.contracts.ProviderId
import com.nuum.contracts.Secrets
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.Call
import okhttp3.Connection
import okhttp3.EventListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelStreamTest {
    @Test
    fun non200Becomes1004WithoutTheKey() = runBlocking {
        val server = MockWebServer()
        server.start()
        val log = StringBuilder()
        try {
            server.enqueue(
                MockResponse()
                    .setResponseCode(401)
                    .setBody("""{"error":"rejected $OPENAI_KEY","hint":"Authorization: Bearer $OPENAI_KEY"}""")
            )
            val port = providerModel(
                ProviderId.OPENAI,
                testClient { line -> log.append(line).append('\n') },
                openAiBaseUrl = server.baseUrl()
            )
            val error = runCatching {
                port.streamChat(chatRequest(ProviderId.OPENAI, "gpt-4o", OPENAI_KEY)).toList()
            }.exceptionOrNull()
            assertTrue(error is NuumException)
            val modelError = error as NuumException
            assertEquals(KernelErrorCode.MODEL, modelError.code)
            assertEquals(1004, modelError.code)
            assertTrue(modelError.message.contains("OpenAI HTTP 401"))
            assertTrue(modelError.message.contains("[redacted]"))
            assertFalse(modelError.message.contains(OPENAI_KEY))
            assertFalse(log.toString().contains(OPENAI_KEY))
            assertFalse(log.toString().contains("Authorization", ignoreCase = true))
            assertFalse(log.toString().contains("x-api-key", ignoreCase = true))
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun missingKeyIs1007AndDoesNotConnect() = runBlocking {
        val connected = AtomicBoolean(false)
        val client = testClient().newBuilder()
            .eventListener(object : EventListener() {
                override fun connectStart(call: Call, inetSocketAddress: InetSocketAddress, proxy: Proxy) {
                    connected.set(true)
                }
            })
            .build()
        val error = runCatching {
            OkHttpModelPort(client).streamChat(chatRequest(ProviderId.OPENAI, "gpt-4o", "")).toList()
        }.exceptionOrNull()
        assertTrue(error is NuumException)
        val missing = error as NuumException
        assertEquals(1007, missing.code)
        assertEquals(KernelErrorCode.INVALID, missing.code)
        assertEquals("API key missing for openai", missing.message)
        assertFalse(connected.get())
    }

    @Test
    fun cancelClosesTheConnection() = runBlocking {
        val server = MockWebServer()
        server.start()
        val released = CountDownLatch(1)
        val failure = AtomicReference<IOException?>(null)
        val client = defaultModelHttpClient().newBuilder()
            .connectTimeout(2, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(2, TimeUnit.SECONDS)
            .eventListener(object : EventListener() {
                override fun connectionReleased(call: Call, connection: Connection) {
                    released.countDown()
                }

                override fun callFailed(call: Call, ioe: IOException) {
                    failure.set(ioe)
                }
            })
            .build()
        val port = providerModel(ProviderId.OPENAI, client, openAiBaseUrl = server.baseUrl())
        try {
            server.enqueue(MockResponse().setHeadersDelay(30, TimeUnit.SECONDS))
            val job = launch(Dispatchers.IO) {
                port.streamChat(chatRequest(ProviderId.OPENAI, "gpt-4o", OPENAI_KEY)).toList()
            }
            val recorded = server.takeRequest(5, TimeUnit.SECONDS)
            assertNotNull(recorded)
            assertEquals("Bearer $OPENAI_KEY", recorded!!.headers["Authorization"])
            withTimeout(3_000) { job.cancelAndJoin() }
            assertTrue("connection stayed open after cancel", released.await(2, TimeUnit.SECONDS))
            val failed = failure.get()
            assertNotNull(failed)
            val text = failed.toString()
            assertFalse(text.contains(OPENAI_KEY))
            assertFalse(text.contains("Authorization", ignoreCase = true))
            assertFalse(text.contains("x-api-key", ignoreCase = true))
        } finally {
            server.shutdown()
        }
    }
}

class SelectModelTest {
    @Test
    fun routesLikeTheMacRouterAndRejectsAMissingKey() {
        val deepseek = selectModel(
            ModelRef(ProviderId.DEEPSEEK, "deepseek-reasoner"),
            Secrets(deepseekApiKey = DEEPSEEK_KEY)
        )
        assertEquals(DEEPSEEK_KEY, deepseek.apiKey)
        val deepseekPort = deepseek.port as OpenAIModel
        assertEquals(DEEPSEEK_BASE_URL, deepseekPort.baseUrl)
        assertEquals(DEEPSEEK_LABEL, deepseekPort.label)

        val openai = selectModel(
            ModelRef(ProviderId.OPENAI, "gpt-4o"),
            Secrets(openaiApiKey = OPENAI_KEY)
        )
        val openaiPort = openai.port as OpenAIModel
        assertEquals(OPENAI_BASE_URL, openaiPort.baseUrl)
        assertEquals(OPENAI_LABEL, openaiPort.label)
        assertEquals(OPENAI_KEY, openai.apiKey)

        val anthropic = selectModel(
            ModelRef(ProviderId.ANTHROPIC, "claude-sonnet-4-20250514"),
            Secrets(anthropicApiKey = ANTHROPIC_KEY)
        )
        assertTrue(anthropic.port is AnthropicModel)
        assertEquals(ANTHROPIC_BASE_URL, (anthropic.port as AnthropicModel).baseUrl)
        assertEquals(ANTHROPIC_KEY, anthropic.apiKey)

        val error = runCatching {
            selectModel(
                ModelRef(ProviderId.ANTHROPIC, "claude-sonnet-4-20250514"),
                Secrets(openaiApiKey = OPENAI_KEY, deepseekApiKey = DEEPSEEK_KEY)
            )
        }.exceptionOrNull()
        assertTrue(error is NuumException)
        val missing = error as NuumException
        assertEquals(1007, missing.code)
        assertEquals("API key missing for anthropic", missing.message)
        assertFalse(missing.message.contains(OPENAI_KEY))
        assertFalse(missing.message.contains(DEEPSEEK_KEY))

        val blank = runCatching {
            selectModel(ModelRef(ProviderId.OPENAI, "gpt-4o"), Secrets(openaiApiKey = ""))
        }.exceptionOrNull()
        assertEquals(1007, (blank as NuumException).code)
    }

    @Test
    fun defaultClientHasTimeoutsAndNoLogInterceptor() {
        val client = defaultModelHttpClient()
        assertEquals(20_000, client.connectTimeoutMillis)
        assertEquals(60_000, client.readTimeoutMillis)
        assertEquals(60_000, client.writeTimeoutMillis)
        assertTrue(client.interceptors.isEmpty())
        assertEquals(1, defaultModelHttpClient { }.interceptors.size)
    }
}

class RedactingLogTest {
    @Test
    fun authHeadersNeverAppearInLogFixtures() = runBlocking {
        val fixture = """
            --> POST https://api.openai.com/v1/chat/completions
            Authorization: Bearer $OPENAI_KEY
            authorization: Bearer sk-live-openai-lower
            x-api-key: $ANTHROPIC_KEY
            X-Api-Key: sk-ant-secret-mixed
            content-type: application/json
            --> END POST
        """.trimIndent()
        val redacted = redactLogFixture(fixture)
        assertFalse(redacted.contains("Authorization", ignoreCase = true))
        assertFalse(redacted.contains("x-api-key", ignoreCase = true))
        assertFalse(redacted.contains(OPENAI_KEY))
        assertFalse(redacted.contains(ANTHROPIC_KEY))
        assertFalse(redacted.contains("sk-live-openai-lower"))
        assertFalse(redacted.contains("sk-ant-secret-mixed"))
        assertTrue(redacted.contains("content-type: application/json"))
        assertTrue(redacted.contains("--> POST https://api.openai.com/v1/chat/completions"))

        val server = MockWebServer()
        server.start()
        val log = StringBuilder()
        try {
            server.enqueue(sseResponse("""{"choices":[{"delta":{"content":"hi"}}]}""", "[DONE]"))
            server.enqueue(
                sseResponse(
                    """{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}"""
                )
            )
            val client = testClient { line -> log.append(line).append('\n') }
            val openAi = OpenAIModel(client, server.baseUrl(), OPENAI_LABEL)
            val anthropic = AnthropicModel(client, server.baseUrl())
            openAi.streamChat(
                chatRequest(
                    ProviderId.OPENAI,
                    "gpt-4o",
                    OPENAI_KEY,
                    messages = listOf(chatMessage(com.nuum.contracts.MessageRole.USER, "UNIQUE_PROMPT_TEXT"))
                )
            ).toList()
            anthropic.streamChat(
                chatRequest(ProviderId.ANTHROPIC, "claude-sonnet-4-20250514", ANTHROPIC_KEY)
            ).toList()

            val text = log.toString()
            assertFalse(text.contains("Authorization", ignoreCase = true))
            assertFalse(text.contains("x-api-key", ignoreCase = true))
            assertFalse(text.contains(OPENAI_KEY))
            assertFalse(text.contains(ANTHROPIC_KEY))
            assertFalse(text.contains("UNIQUE_PROMPT_TEXT"))
            assertTrue(text.contains("--> POST"))
            assertTrue(text.contains("<-- 200"))

            assertEquals("Bearer $OPENAI_KEY", server.takeRequest().headers["Authorization"])
            val anthropicRequest = server.takeRequest()
            assertEquals(ANTHROPIC_KEY, anthropicRequest.headers["x-api-key"])
            assertNull(anthropicRequest.headers["Authorization"])
        } finally {
            server.shutdown()
        }
    }
}
