package com.nuum.security

/**
 * Blocking ciphertext port used by [KeystoreSecretStore].
 * [read] returns null when no secrets file has been committed.
 * [write] must persist ciphertext only, and must leave the previous file intact when it throws.
 */
internal interface SecretFileWriter {
    fun read(): ByteArray?

    fun write(plaintext: ByteArray)
}
