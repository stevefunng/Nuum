package com.nuum.security

import com.nuum.contracts.DesktopErrorCode
import com.nuum.contracts.NuumException
import com.nuum.contracts.Secrets
import java.io.PrintWriter
import java.io.StringWriter
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM coverage for the failure policy. The writer is a test double, not a Keystore.
 * Device encryption, file placement, and round-trip live in androidTest.
 */
class KeystoreSecretStoreTest {
    @Test
    fun wrappedWriterFailureDoesNotExposeTheKey() {
        val stored = Secrets(openaiApiKey = STORED_KEY)
        val recording = RecordingWriter()
        runBlocking { store(recording).write(stored) }
        val leaking = LeakingWriter(recording)
        val secrets = store(leaking)
        val attempted = Secrets(
            openaiApiKey = OPENAI_KEY,
            anthropicApiKey = ANTHROPIC_KEY,
            deepseekApiKey = DEEPSEEK_KEY
        )

        val readError = assertThrows(NuumException::class.java) {
            runBlocking { secrets.read() }
        }
        val writeError = assertThrows(NuumException::class.java) {
            runBlocking { secrets.write(attempted) }
        }

        assertEquals(DesktopErrorCode.SECRET_STORE, readError.code)
        assertEquals(DesktopErrorCode.SECRET_STORE, writeError.code)
        assertEquals("Couldn't read secrets because decryption failed.", readError.message)
        assertEquals("Couldn't store secrets because encryption failed.", writeError.message)
        assertNull(readError.cause)
        assertNull(writeError.cause)
        assertEquals(0, readError.suppressed.size)
        assertEquals(0, writeError.suppressed.size)
        assertEquals(1, leaking.writes)
        assertEquals(1, recording.writes)
        assertEquals(stored, runBlocking { store(recording).read() })
        listOf(readError, writeError).forEach { error ->
            assertSecretTextOmitted(error, STORED_KEY, OPENAI_KEY, ANTHROPIC_KEY, DEEPSEEK_KEY)
        }
        assertFalse(secrets.toString().contains(OPENAI_KEY))
    }

    @Test
    fun missingFileReadsAsEmptyAndRoundTripsWithoutDroppingEmptyStrings() {
        val recording = RecordingWriter()
        val secrets = store(recording)
        assertEquals(Secrets(), runBlocking { secrets.read() })

        val value = Secrets(
            openaiApiKey = "a\"b\\c\n\u0001尾",
            anthropicApiKey = "",
            deepseekApiKey = null
        )
        runBlocking { secrets.write(value) }
        val raw = recording.stored!!.decodeToString()
        assertTrue(raw.contains("\"openaiApiKey\""))
        assertTrue(raw.contains("\"anthropicApiKey\":\"\""))
        assertFalse(raw.contains("deepseekApiKey"))
        assertEquals(value, runBlocking { secrets.read() })
    }

    @Test
    fun malformedPayloadIsSecretStoreFailure() {
        val recording = RecordingWriter()
        recording.stored = """{"openaiApiKey":"$OPENAI_KEY"""".encodeToByteArray()
        val error = assertThrows(NuumException::class.java) {
            runBlocking { store(recording).read() }
        }
        assertEquals(DesktopErrorCode.SECRET_STORE, error.code)
        assertEquals("Couldn't read secrets because decryption failed.", error.message)
        assertSecretTextOmitted(error, OPENAI_KEY)
    }

    @Test
    fun publicConstructorAcceptsContext() {
        val parameterLists = KeystoreSecretStore::class.java.constructors.map { constructor ->
            constructor.parameterTypes.map { it.name }
        }
        assertTrue(parameterLists.contains(listOf("android.content.Context")))
    }

    private fun store(writer: SecretFileWriter): KeystoreSecretStore =
        KeystoreSecretStore(writer, DirectDispatcher)

    private fun assertSecretTextOmitted(error: Throwable, vararg keys: String) {
        val rendered = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
        keys.forEach { key ->
            assertFalse(rendered.contains(key))
        }
    }

    /**
     * Wraps a committed writer and echoes plaintext into the failure, which is what
     * this test is guarding against in [KeystoreSecretStore].
     */
    private class LeakingWriter(private val inner: SecretFileWriter) : SecretFileWriter {
        var writes: Int = 0

        override fun read(): ByteArray? {
            val bytes = inner.read()
            throw IllegalStateException("decrypt failed ${bytes?.decodeToString()}")
        }

        override fun write(plaintext: ByteArray) {
            writes += 1
            throw IllegalStateException("encrypt failed ${plaintext.decodeToString()}")
        }
    }

    private class RecordingWriter : SecretFileWriter {
        var stored: ByteArray? = null
        var writes: Int = 0

        override fun read(): ByteArray? = stored?.copyOf()

        override fun write(plaintext: ByteArray) {
            writes += 1
            stored = plaintext.copyOf()
        }
    }

    private object DirectDispatcher : CoroutineDispatcher() {
        override fun isDispatchNeeded(context: CoroutineContext): Boolean = false

        override fun dispatch(context: CoroutineContext, block: Runnable) {
            block.run()
        }
    }

    private companion object {
        const val STORED_KEY = "sk-test-stored-key-aaa111"
        const val OPENAI_KEY = "sk-test-openai-9f3c2b"
        const val ANTHROPIC_KEY = "sk-test-anthropic-11aa"
        const val DEEPSEEK_KEY = "sk-test-deepseek-77e0"
    }
}
