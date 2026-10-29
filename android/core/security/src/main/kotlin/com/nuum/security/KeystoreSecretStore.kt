package com.nuum.security

import android.content.Context
import com.nuum.contracts.DesktopErrorCode
import com.nuum.contracts.NuumException
import com.nuum.contracts.SecretStore
import com.nuum.contracts.Secrets
import java.util.concurrent.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * [SecretStore] backed by Android Keystore alias [KEY_ALIAS] and
 * `noBackupFilesDir/secrets.bin`. Encryption or decryption failure throws
 * [NuumException] [DesktopErrorCode.SECRET_STORE] and does not write plaintext.
 * The thrown message is a fixed sentence: it never includes the key, the JSON,
 * or the underlying error text.
 */
class KeystoreSecretStore internal constructor(
    private val writer: SecretFileWriter,
    private val ioDispatcher: CoroutineDispatcher
) : SecretStore {
    constructor(context: Context) : this(KeystoreSecretFileWriter(context), Dispatchers.IO)

    override suspend fun read(): Secrets = withContext(ioDispatcher) {
        try {
            val bytes = writer.read() ?: return@withContext Secrets()
            try {
                SecretsCodec.decode(bytes)
            } finally {
                bytes.fill(0)
            }
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            throw readFailure()
        }
    }

    override suspend fun write(secrets: Secrets) {
        val plaintext = try {
            SecretsCodec.encode(secrets)
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            throw writeFailure()
        }
        try {
            withContext(ioDispatcher) {
                try {
                    writer.write(plaintext)
                } catch (error: Exception) {
                    if (error is CancellationException) throw error
                    throw writeFailure()
                }
            }
        } finally {
            plaintext.fill(0)
        }
    }

    override fun toString(): String = "KeystoreSecretStore"

    private fun readFailure(): NuumException = NuumException(
        DesktopErrorCode.SECRET_STORE,
        "Couldn't read secrets because decryption failed."
    )

    private fun writeFailure(): NuumException = NuumException(
        DesktopErrorCode.SECRET_STORE,
        "Couldn't store secrets because encryption failed."
    )

    companion object {
        const val KEY_ALIAS = "nuum.secrets"
    }
}
