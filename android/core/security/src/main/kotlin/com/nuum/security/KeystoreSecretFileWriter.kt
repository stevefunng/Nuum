package com.nuum.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.MasterKey
import com.nuum.contracts.NuumPaths
import java.io.File
import java.io.IOException

/**
 * AES-256-GCM via the Android Keystore alias [KeystoreSecretStore.KEY_ALIAS].
 * Ciphertext is [NuumPaths.secretsFileName] under [Context.getNoBackupFilesDir].
 *
 * EncryptedFile binds AES-GCM associated data to the file name only. Staging and
 * backup copies are also named `secrets.bin`, or a rename could not be decrypted.
 * This class never opens a plaintext [java.io.FileOutputStream] on the secrets file.
 */
internal class KeystoreSecretFileWriter(
    private val context: Context
) : SecretFileWriter {
    private val lock = Any()

    override fun read(): ByteArray? = synchronized(lock) {
        val target = committedFile() ?: return null
        val bytes = encrypted(target).openFileInput().use { it.readBytes() }
        discardStaging()
        discardBackup()
        bytes
    }

    override fun write(plaintext: ByteArray) = synchronized(lock) {
        val stagingDir = File(context.noBackupFilesDir, STAGING_DIR)
        if (!stagingDir.isDirectory && !stagingDir.mkdirs()) {
            throw IOException("secrets directory is unavailable")
        }
        val staging = File(stagingDir, NuumPaths.secretsFileName())
        if (staging.exists() && !staging.delete()) {
            throw IOException("could not replace secrets")
        }
        try {
            encrypted(staging).openFileOutput().use { stream ->
                stream.write(plaintext)
                stream.flush()
            }
            promote(staging)
        } catch (error: Exception) {
            staging.delete()
            throw error
        } finally {
            discardEmpty(stagingDir)
        }
    }

    override fun toString(): String = "KeystoreSecretFileWriter"

    private fun committedFile(): File? {
        val target = targetFile()
        if (target.exists()) return target
        val backup = File(File(context.noBackupFilesDir, BACKUP_DIR), NuumPaths.secretsFileName())
        if (!backup.exists()) return null
        if (!backup.renameTo(target)) throw IOException("could not read secrets")
        discardEmpty(backup.parentFile)
        return target
    }

    private fun promote(staging: File) {
        val target = targetFile()
        if (!target.exists()) {
            if (!staging.renameTo(target)) throw IOException("could not replace secrets")
            return
        }
        val backupDir = File(context.noBackupFilesDir, BACKUP_DIR)
        if (!backupDir.isDirectory && !backupDir.mkdirs()) {
            throw IOException("could not replace secrets")
        }
        val backup = File(backupDir, NuumPaths.secretsFileName())
        if (backup.exists() && !backup.delete()) {
            throw IOException("could not replace secrets")
        }
        if (!target.renameTo(backup)) throw IOException("could not replace secrets")
        if (!staging.renameTo(target)) {
            if (!target.exists()) backup.renameTo(target)
            throw IOException("could not replace secrets")
        }
        backup.delete()
        discardEmpty(backupDir)
    }

    private fun discardStaging() {
        val staging = File(File(context.noBackupFilesDir, STAGING_DIR), NuumPaths.secretsFileName())
        if (staging.exists()) staging.delete()
        discardEmpty(staging.parentFile)
    }

    private fun discardBackup() {
        val backupDir = File(context.noBackupFilesDir, BACKUP_DIR)
        val backup = File(backupDir, NuumPaths.secretsFileName())
        if (backup.exists()) backup.delete()
        discardEmpty(backupDir)
    }

    private fun discardEmpty(directory: File?) {
        if (directory == null || directory == context.noBackupFilesDir) return
        if (directory.isDirectory && directory.list().isNullOrEmpty()) directory.delete()
    }

    private fun targetFile(): File = File(context.noBackupFilesDir, NuumPaths.secretsFileName())

    @Suppress("DEPRECATION")
    private fun encrypted(file: File): EncryptedFile {
        val spec = KeyGenParameterSpec.Builder(
            KeystoreSecretStore.KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(MasterKey.DEFAULT_AES_GCM_MASTER_KEY_SIZE)
            .setUserAuthenticationRequired(false)
            .build()
        val masterKey = MasterKey.Builder(context, KeystoreSecretStore.KEY_ALIAS)
            .setKeyGenParameterSpec(spec)
            .build()
        return EncryptedFile.Builder(
            context,
            file,
            masterKey,
            EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB
        ).build()
    }

    private companion object {
        const val STAGING_DIR = "secrets-staging"
        const val BACKUP_DIR = "secrets-backup"
    }
}
