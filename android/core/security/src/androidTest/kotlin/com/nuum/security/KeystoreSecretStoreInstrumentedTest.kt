package com.nuum.security

import android.content.Context
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import com.nuum.contracts.DesktopErrorCode
import com.nuum.contracts.NuumException
import com.nuum.contracts.NuumPaths
import com.nuum.contracts.Secrets
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.security.KeyStore
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Device or emulator only. Robolectric's Keystore is not a stand-in.
 * `./gradlew :core:security:connectedDebugAndroidTest`
 */
class KeystoreSecretStoreInstrumentedTest {
    private val context: Context
        get() = SecretStoreInstrumentation.instance.targetContext

    @Before
    fun wipeSecretFiles() = deleteSecretFiles()

    @After
    fun wipeSecretFilesAfter() = deleteSecretFiles()

    @Test
    fun writeThenReadRoundTripsAndFileIsNotPlaintextJson() {
        val secrets = Secrets(
            openaiApiKey = OPENAI_KEY,
            anthropicApiKey = ANTHROPIC_KEY,
            deepseekApiKey = DEEPSEEK_KEY
        )
        val store = KeystoreSecretStore(context)
        assertEquals(Secrets(), runBlocking { store.read() })

        runBlocking { store.write(secrets) }
        val file = File(context.noBackupFilesDir, NuumPaths.secretsFileName())
        assertTrue(file.isFile)
        assertEquals(context.noBackupFilesDir.canonicalPath, file.parentFile?.canonicalPath)
        assertFalse(file.canonicalFile.toPath().startsWith(context.filesDir.canonicalFile.toPath()))

        val ciphertext = file.readBytes()
        val plaintext = SecretsCodec.encode(secrets)
        assertFalse(ciphertext.contentEquals(plaintext))
        assertTrue(ciphertext.size > plaintext.size)
        val latin1 = ciphertext.toString(Charsets.ISO_8859_1)
        assertFalse(latin1.contains("openaiApiKey"))
        assertFalse(latin1.contains("anthropicApiKey"))
        assertFalse(latin1.contains("deepseekApiKey"))
        assertFalse(latin1.contains(OPENAI_KEY))
        assertFalse(latin1.contains(ANTHROPIC_KEY))
        assertFalse(latin1.contains(DEEPSEEK_KEY))

        assertEquals(secrets, runBlocking { store.read() })
        assertEquals(secrets, runBlocking { KeystoreSecretStore(context).read() })
        assertEquals(
            listOf(file.canonicalPath),
            context.noBackupFilesDir.walkTopDown()
                .filter { it.isFile && it.name == NuumPaths.secretsFileName() }
                .map { it.canonicalPath }
                .toList()
        )

        val replaced = Secrets(openaiApiKey = REPLACED_KEY)
        runBlocking { store.write(replaced) }
        assertEquals(replaced, runBlocking { store.read() })
        val replacedBytes = file.readBytes()
        assertFalse(replacedBytes.toString(Charsets.ISO_8859_1).contains(REPLACED_KEY))
        assertFalse(replacedBytes.toString(Charsets.ISO_8859_1).contains(OPENAI_KEY))

        assertKeystoreKey()
        assertPlaintextAbsent(OPENAI_KEY, ANTHROPIC_KEY, DEEPSEEK_KEY, REPLACED_KEY)
        assertNoSecretsBinUnderFilesDir()
    }

    @Test
    fun plaintextFileIsRejectedAndNotRewritten() {
        val planted = """{"openaiApiKey":"$OPENAI_KEY","anthropicApiKey":"$ANTHROPIC_KEY"}"""
        val file = File(context.noBackupFilesDir, NuumPaths.secretsFileName())
        file.writeText(planted)
        val before = file.readBytes()
        val error = assertThrows(NuumException::class.java) {
            runBlocking { KeystoreSecretStore(context).read() }
        }
        assertEquals(DesktopErrorCode.SECRET_STORE, error.code)
        assertEquals("Couldn't read secrets because decryption failed.", error.message)
        assertSecretTextOmitted(error, OPENAI_KEY, ANTHROPIC_KEY)
        assertTrue(before.contentEquals(file.readBytes()))
        assertNoSecretsBinUnderFilesDir()
    }

    private fun assertKeystoreKey() {
        val keystore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        assertTrue(keystore.containsAlias(KeystoreSecretStore.KEY_ALIAS))
        val secretKey = keystore.getKey(KeystoreSecretStore.KEY_ALIAS, null) as SecretKey
        assertEquals("AES", secretKey.algorithm)
        val info = SecretKeyFactory.getInstance(secretKey.algorithm, "AndroidKeyStore")
            .getKeySpec(secretKey, KeyInfo::class.java) as KeyInfo
        assertEquals(256, info.keySize)
        assertFalse(info.isUserAuthenticationRequired)
        assertTrue(info.blockModes.contains(KeyProperties.BLOCK_MODE_GCM))
        assertTrue(info.encryptionPaddings.contains(KeyProperties.ENCRYPTION_PADDING_NONE))
        assertTrue((info.purposes and KeyProperties.PURPOSE_ENCRYPT) != 0)
        assertTrue((info.purposes and KeyProperties.PURPOSE_DECRYPT) != 0)
    }

    private fun assertNoSecretsBinUnderFilesDir() {
        context.filesDir.walkTopDown().filter { it.isFile }.forEach { file ->
            assertFalse(file.name == NuumPaths.secretsFileName())
        }
    }

    private fun assertPlaintextAbsent(vararg keys: String) {
        context.dataDir.walkTopDown().filter { it.isFile }.forEach { file ->
            val text = file.readBytes().toString(Charsets.ISO_8859_1)
            keys.forEach { key ->
                assertFalse("plaintext key in ${file.absolutePath}", text.contains(key))
            }
        }
    }

    private fun assertSecretTextOmitted(error: Throwable, vararg keys: String) {
        val rendered = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
        keys.forEach { key -> assertFalse(rendered.contains(key)) }
    }

    private fun deleteSecretFiles() {
        listOf(context.noBackupFilesDir, context.filesDir).forEach { root ->
            if (!root.exists()) return@forEach
            root.walkBottomUp().forEach { file ->
                if (file.isFile && file.name == NuumPaths.secretsFileName()) file.delete()
            }
        }
    }

    private companion object {
        const val OPENAI_KEY = "nuum-test-openai-key-7f3c1a"
        const val ANTHROPIC_KEY = "nuum-test-anthropic-key-91ab"
        const val DEEPSEEK_KEY = "nuum-test-deepseek-key-e04d"
        const val REPLACED_KEY = "nuum-test-openai-key-replaced"
    }
}
