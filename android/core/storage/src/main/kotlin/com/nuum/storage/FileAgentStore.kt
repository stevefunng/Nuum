package com.nuum.storage

import android.content.Context
import androidx.room.Room
import androidx.room.RoomDatabase
import com.nuum.contracts.AgentStore
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NuumException
import com.nuum.contracts.Settings
import com.nuum.storage.projection.NuumDatabase
import com.nuum.storage.projection.toEntry
import java.io.File
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * File layout under [root] (`filesDir/nuum` in the app). JSON is replaced atomically.
 * JSONL is append-only, and a truncated last line is dropped. Room is a list
 * projection rebuilt from those files. DataStore holds sidebar width and the
 * identity-edited set only. Markdown memory is stored as bytes and not interpreted.
 *
 * Write order: the file replace or append finishes, then the projection is updated.
 * If the process dies between the two, the next [open] or [rebuildListProjection]
 * trusts the files.
 */
class FileAgentStore(
    val root: File,
    private val database: NuumDatabase,
    preferencesFile: File,
    private val beforeCommit: () -> Unit = {},
    private val io: CoroutineDispatcher = Dispatchers.IO
) : AgentStore, AutoCloseable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val uiPreferences = UiPreferences.create(preferencesFile, scope)
    private val rebuilder = ProjectionRebuilder(root, database)
    private val gate = Mutex()
    private val closed = AtomicBoolean(false)

    val sidebarLayout: Flow<SidebarLayout> = uiPreferences.sidebarLayout
    val identityEdited: Flow<Set<String>> = uiPreferences.identityEdited

    /**
     * Creates the directory layout and rebuilds the list projection when it is
     * missing or [StoragePaths.migrationsPath] no longer matches.
     */
    suspend fun open() = ioLock {
        ensureLayout(root)
        ensureMigrationMarker(root, beforeCommit)
        if (rebuilder.needsRebuild()) rebuilder.rebuild()
    }

    suspend fun readSettings(): Settings = ioLock {
        val file = resolveInside(root, StoragePaths.settingsPath()).file
        if (!file.isFile) return@ioLock com.nuum.contracts.DEFAULT_SETTINGS
        SettingsJson.decode(file.readText(Charsets.UTF_8))
    }

    suspend fun writeSettings(settings: Settings) {
        writeTextAtomic(StoragePaths.settingsPath(), SettingsJson.encode(settings))
    }

    suspend fun agentList(): List<AgentListEntry> = ioLock {
        database.projectionDao().agents().map { it.toEntry() }
    }

    suspend fun workList(): List<WorkListEntry> = ioLock {
        database.projectionDao().works().map { it.toEntry() }
    }

    suspend fun taskList(workId: String): List<TaskListEntry> = ioLock {
        database.projectionDao().tasks(workId).map { it.toEntry() }
    }

    suspend fun sidebarSections(): List<SidebarSectionEntry> = ioLock {
        database.projectionDao().sections().map { it.toEntry() }
    }

    suspend fun sidebarPins(): List<String> = ioLock {
        database.projectionDao().pins().map { it.agentId }
    }

    /** Drops Room rows. Files stay. [rebuildListProjection] or [open] fills the rows again. */
    suspend fun discardListProjection() = ioLock {
        rebuilder.discard()
    }

    suspend fun rebuildListProjection() = ioLock {
        ensureLayout(root)
        rebuilder.rebuild()
    }

    /** Complete JSONL lines. A truncated final line is removed from the file first. */
    suspend fun readJsonLines(relativePath: String): List<String> = ioLock {
        JsonlFiles.readLines(resolveInside(root, relativePath).file)
    }

    suspend fun readSidebarLayout(): SidebarLayout = withContext(io) {
        uiPreferences.readSidebarLayout()
    }

    suspend fun writeSidebarLayout(layout: SidebarLayout) = withContext(io) {
        uiPreferences.writeSidebarLayout(layout)
    }

    suspend fun hasEditedIdentity(agentId: String): Boolean = withContext(io) {
        uiPreferences.hasEditedIdentity(agentId)
    }

    suspend fun markIdentityEdited(agentId: String) = withContext(io) {
        uiPreferences.markIdentityEdited(agentId)
    }

    override suspend fun readText(relativePath: String): String? = ioLock {
        val file = resolveInside(root, relativePath).file
        if (!file.isFile) null else file.readText(Charsets.UTF_8)
    }

    override suspend fun writeTextAtomic(relativePath: String, text: String) {
        writeBytes(relativePath, text.toByteArray(Charsets.UTF_8))
    }

    override suspend fun appendLine(relativePath: String, line: String) = ioLock {
        val normalized = normalizeRelative(relativePath)
        val clean = normalizeJsonlLine(line)
        val file = resolveInside(root, normalized).file
        JsonlFiles.appendLine(file, clean)
        updateProjection(normalized)
    }

    override suspend fun readBytes(relativePath: String): ByteArray? = ioLock {
        val file = resolveInside(root, relativePath).file
        if (!file.isFile) null else file.readBytes()
    }

    override suspend fun writeBytesAtomic(relativePath: String, bytes: ByteArray) {
        writeBytes(relativePath, bytes)
    }

    override suspend fun readTail(relativePath: String, maxBytes: Int): String = ioLock {
        JsonlFiles.readTail(resolveInside(root, relativePath).file, maxBytes)
    }

    override suspend fun list(relativePath: String): List<String> = ioLock {
        val file = resolveInside(root, relativePath).file
        if (!file.isDirectory) emptyList() else file.list().orEmpty().sorted()
    }

    override suspend fun delete(relativePath: String) = ioLock {
        val resolved = resolveInside(root, relativePath)
        val file = resolved.file
        if (!file.exists()) return@ioLock
        if (file.isDirectory) {
            if (!file.deleteRecursively()) throw IOException("could not delete ${resolved.relative}")
        } else if (!file.delete()) {
            throw IOException("could not delete ${resolved.relative}")
        }
        updateProjectionDeleted(resolved.relative)
    }

    override suspend fun exists(relativePath: String): Boolean = ioLock {
        resolveInside(root, relativePath).file.exists()
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        scope.cancel()
        database.close()
    }

    private suspend fun writeBytes(relativePath: String, bytes: ByteArray) = ioLock {
        val normalized = normalizeRelative(relativePath)
        val payload = payloadFor(normalized, bytes)
        AtomicFiles.write(resolveInside(root, normalized).file, payload, beforeCommit)
        updateProjection(normalized)
    }

    private fun payloadFor(relativePath: String, bytes: ByteArray): ByteArray {
        val text = bytes.toString(Charsets.UTF_8)
        return when {
            relativePath == StoragePaths.settingsPath() ->
                SettingsJson.canonical(text).toByteArray(Charsets.UTF_8)
            relativePath.endsWith("/settings.json") ->
                SettingsJson.stripSecretFields(text).toByteArray(Charsets.UTF_8)
            else -> bytes
        }
    }

    private suspend fun updateProjection(relativePath: String) {
        try {
            rebuilder.onWritten(relativePath)
        } catch (error: Exception) {
            runCatching { rebuilder.discard() }
            throw error
        }
    }

    private suspend fun updateProjectionDeleted(relativePath: String) {
        try {
            rebuilder.onDeleted(relativePath)
        } catch (error: Exception) {
            runCatching { rebuilder.discard() }
            throw error
        }
    }

    private suspend fun <T> ioLock(block: suspend () -> T): T = withContext(io) {
        gate.withLock { block() }
    }

    companion object {
        fun create(
            context: Context,
            root: File = File(context.filesDir, "nuum"),
            beforeCommit: () -> Unit = {}
        ): FileAgentStore {
            val appContext = context.applicationContext
            val database = Room.databaseBuilder(appContext, NuumDatabase::class.java, DATABASE_NAME)
                .fallbackToDestructiveMigration(dropAllTables = true)
                .setJournalMode(RoomDatabase.JournalMode.WRITE_AHEAD_LOGGING)
                .build()
            return FileAgentStore(
                root = root,
                database = database,
                preferencesFile = uiPreferencesFile(appContext.filesDir),
                beforeCommit = beforeCommit
            )
        }

        fun migrationsPath(): String = StoragePaths.migrationsPath()

        fun workSessionDir(
            workId: String,
            taskId: String,
            agentId: String,
            membershipRevision: Int
        ): String = StoragePaths.workSessionDir(workId, taskId, agentId, membershipRevision)

        fun workSessionRecordPath(
            workId: String,
            taskId: String,
            agentId: String,
            membershipRevision: Int
        ): String = StoragePaths.workSessionRecordPath(workId, taskId, agentId, membershipRevision)

        fun workSessionTranscriptPath(
            workId: String,
            taskId: String,
            agentId: String,
            membershipRevision: Int
        ): String = StoragePaths.workSessionTranscriptPath(workId, taskId, agentId, membershipRevision)

        fun cardSessionId(
            workId: String,
            taskId: String,
            agentId: String,
            membershipRevision: Int
        ): String = StoragePaths.cardSessionId(workId, taskId, agentId, membershipRevision)

        fun workspaceIdForOwner(owner: String): String = StoragePaths.workspaceIdForOwner(owner)

        private const val DATABASE_NAME = "nuum-projection"
    }
}

private fun normalizeJsonlLine(line: String): String {
    val clean = line.removeSuffix("\n").removeSuffix("\r")
    if (clean.isEmpty() || clean.contains('\n') || clean.contains('\r')) {
        throw NuumException(KernelErrorCode.INVALID, "JSONL line must be a single non-empty line")
    }
    return clean
}
