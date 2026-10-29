package com.nuum.graph

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import com.nuum.contracts.DesktopPort
import com.nuum.contracts.MAX_ATTACHMENT_BYTES
import com.nuum.contracts.NuumPaths
import com.nuum.contracts.PickedFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * SAF and share intents. Cancel returns null or an empty list. Missing
 * activities and sealed secret paths do not throw. Plaintext keys are not read.
 */
class AndroidDesktopPort(
    private val context: Context
) : DesktopPort {
    private var directoryLauncher: ActivityResultLauncher<Uri?>? = null
    private var filesLauncher: ActivityResultLauncher<Array<String>>? = null
    private var directoryWaiter: CompletableDeferred<String?>? = null
    private var filesWaiter: CompletableDeferred<List<Uri>>? = null

    fun attach(activity: ComponentActivity) {
        directoryLauncher = activity.registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            if (uri != null) persist(uri)
            finishDirectory(uri?.toString())
        }
        filesLauncher = activity.registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
            uris.forEach(::persist)
            finishFiles(uris)
        }
    }

    override suspend fun pickDirectory(): String? {
        val launcher = directoryLauncher ?: return null
        val waiter = CompletableDeferred<String?>()
        withContext(Dispatchers.Main.immediate) {
            finishDirectory(null)
            directoryWaiter = waiter
            try {
                launcher.launch(null)
            } catch (_: RuntimeException) {
                if (directoryWaiter === waiter) {
                    directoryWaiter = null
                    waiter.complete(null)
                }
            }
        }
        return awaitResult(waiter) {
            if (directoryWaiter === waiter) directoryWaiter = null
        }
    }

    override suspend fun pickFiles(): List<PickedFile> {
        val launcher = filesLauncher ?: return emptyList()
        val waiter = CompletableDeferred<List<Uri>>()
        withContext(Dispatchers.Main.immediate) {
            finishFiles(emptyList())
            filesWaiter = waiter
            try {
                launcher.launch(arrayOf("*/*"))
            } catch (_: RuntimeException) {
                if (filesWaiter === waiter) {
                    filesWaiter = null
                    waiter.complete(emptyList())
                }
            }
        }
        val uris = awaitResult(waiter) {
            if (filesWaiter === waiter) filesWaiter = null
        }
        return withContext(Dispatchers.IO) { uris.mapNotNull(::readPicked) }
    }

    override suspend fun openAttachment(path: String) {
        if (path.isBlank() || isSealed(path)) return
        val uri = uriFor(path) ?: return
        val mime = mimeOf(uri)
        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            launch(view)
        } catch (_: ActivityNotFoundException) {
            try {
                launch(shareIntent(uri, mime))
            } catch (_: ActivityNotFoundException) {
                // Neither a viewer nor a share target is installed.
            }
        }
    }

    override suspend fun share(path: String) {
        if (path.isBlank() || isSealed(path)) return
        val uri = uriFor(path) ?: return
        try {
            launch(shareIntent(uri, mimeOf(uri)))
        } catch (_: ActivityNotFoundException) {
            // No app offered to receive the stream.
        }
    }

    private fun finishDirectory(value: String?) {
        val waiter = directoryWaiter
        directoryWaiter = null
        if (waiter != null && waiter.isActive) waiter.complete(value)
    }

    private fun finishFiles(value: List<Uri>) {
        val waiter = filesWaiter
        filesWaiter = null
        if (waiter != null && waiter.isActive) waiter.complete(value)
    }

    private suspend fun <T> awaitResult(waiter: CompletableDeferred<T>, clear: () -> Unit): T =
        try {
            waiter.await()
        } finally {
            withContext(Dispatchers.Main.immediate) { clear() }
        }

    private fun persist(uri: Uri) {
        val resolver = context.contentResolver
        val readWrite = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        try {
            resolver.takePersistableUriPermission(uri, readWrite)
        } catch (_: SecurityException) {
            try {
                resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: SecurityException) {
                // The picker grant still covers this process for the current session.
            }
        }
    }

    private fun readPicked(uri: Uri): PickedFile? {
        val mime = context.contentResolver.getType(uri) ?: "application/octet-stream"
        val name = displayName(uri)
        val bytes = context.contentResolver.openInputStream(uri)?.use { stream ->
            readLimited(stream, MAX_ATTACHMENT_BYTES + 1)
        } ?: return null
        return PickedFile(name, mime, bytes)
    }

    private fun displayName(uri: Uri): String {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    val name = cursor.getString(index)
                    if (!name.isNullOrBlank()) return name
                }
            }
        }
        return uri.lastPathSegment ?: "file"
    }

    private fun mimeOf(uri: Uri): String = context.contentResolver.getType(uri) ?: "*/*"

    private fun uriFor(path: String): Uri? {
        if (path.startsWith("content://")) return Uri.parse(path)
        val file = File(path)
        if (!file.isFile) return null
        return try {
            FileProvider.getUriForFile(context, authority(), file)
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private fun authority(): String = "${context.packageName}.fileprovider"

    private fun isSealed(path: String): Boolean {
        val target = normalizePath(path)
        val root = normalizePath(context.noBackupFilesDir.absolutePath)
        val secrets = normalizePath(File(context.noBackupFilesDir, NuumPaths.secretsFileName()).absolutePath)
        return deniedCovers(listOf(root, secrets), target)
    }

    private fun shareIntent(uri: Uri, mime: String): Intent {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri("attachment", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private fun launch(intent: Intent) {
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (missing: ActivityNotFoundException) {
            throw missing
        } catch (_: RuntimeException) {
            // No activity can handle the intent. The caller already has a fallback for view.
        }
    }
}

private fun readLimited(stream: InputStream, maxBytes: Int): ByteArray {
    val out = ByteArrayOutputStream()
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    var total = 0
    while (total < maxBytes) {
        val read = stream.read(buffer)
        if (read < 0) break
        val take = minOf(read, maxBytes - total)
        out.write(buffer, 0, take)
        total += take
    }
    return out.toByteArray()
}

private const val DEFAULT_BUFFER_SIZE = 8 * 1024
