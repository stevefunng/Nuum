package com.nuum.graph

import com.nuum.contracts.ProviderId
import com.nuum.contracts.SecretStore
import com.nuum.contracts.SecretWriter
import com.nuum.contracts.Secrets
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Settings-page writer. Reads the stored record, replaces one provider, and
 * writes it back. Empty or null deletes that provider's key. This type has no
 * read method and its [toString] does not include key material.
 */
class SecretStoreWriter(
    private val store: SecretStore
) : SecretWriter {
    private val gate = Mutex()

    override suspend fun write(provider: ProviderId, apiKey: String?) {
        gate.withLock {
            val current = store.read()
            store.write(current.withProvider(provider, apiKey.blankToNull()))
        }
    }

    override fun toString(): String = "SecretStoreWriter"
}

private fun Secrets.withProvider(provider: ProviderId, apiKey: String?): Secrets = when (provider) {
    ProviderId.OPENAI -> copy(openaiApiKey = apiKey)
    ProviderId.ANTHROPIC -> copy(anthropicApiKey = apiKey)
    ProviderId.DEEPSEEK -> copy(deepseekApiKey = apiKey)
}

private fun String?.blankToNull(): String? = if (this.isNullOrEmpty()) null else this
