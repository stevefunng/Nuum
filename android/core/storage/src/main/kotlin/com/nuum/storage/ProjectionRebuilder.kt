package com.nuum.storage

import androidx.room.withTransaction
import com.nuum.storage.projection.NuumDatabase
import com.nuum.storage.projection.ProjectionDao
import com.nuum.storage.projection.ProjectionMetaEntity
import com.nuum.storage.projection.SidebarPinEntity
import com.nuum.storage.projection.SidebarSectionEntity
import com.nuum.storage.projection.toEntity
import java.io.File
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * Room holds list rows only. A missing projection, or a `migrations.json` version
 * that does not match the last build, is replaced by a scan of the files.
 * Agent transcripts contribute only their tail window.
 */
internal class ProjectionRebuilder(
    private val root: File,
    private val database: NuumDatabase
) {
    private val dao: ProjectionDao = database.projectionDao()

    suspend fun needsRebuild(): Boolean {
        val version = readMigrationVersion(root)
        val meta = dao.meta()
        if (meta == null || meta.migrationsVersion != version) return true
        if (dao.agentCount() == 0 && countProfiles("agents") > 0) return true
        if (dao.workCount() == 0 && countProfiles("works") > 0) return true
        return false
    }

    suspend fun rebuild() {
        val agents = scanAgents()
        val works = mutableListOf<WorkListEntry>()
        val tasks = mutableListOf<TaskListEntry>()
        for (work in scanWorks()) {
            works += work.entry
            tasks += work.tasks
        }
        val sidebar = readSidebar()
        val version = readMigrationVersion(root)
        database.withTransaction {
            dao.clearAgents()
            dao.clearWorks()
            dao.clearTasks()
            dao.clearSections()
            dao.clearPins()
            agents.forEach { dao.upsertAgent(it.toEntity()) }
            works.forEach { dao.upsertWork(it.toEntity()) }
            if (tasks.isNotEmpty()) dao.upsertTasks(tasks.map { it.toEntity() })
            writeSidebar(sidebar)
            dao.upsertMeta(ProjectionMetaEntity(migrationsVersion = version))
        }
    }

    suspend fun discard() {
        database.withTransaction {
            dao.clearAgents()
            dao.clearWorks()
            dao.clearTasks()
            dao.clearSections()
            dao.clearPins()
            dao.clearMeta()
        }
    }

    suspend fun onWritten(relativePath: String) {
        when {
            relativePath == StoragePaths.settingsPath() -> refreshSidebar()
            agentIdFrom(relativePath, AGENT_PROFILE) != null -> refreshAgent(agentIdFrom(relativePath, AGENT_PROFILE)!!)
            agentIdFrom(relativePath, AGENT_SETTINGS) != null -> refreshAgent(agentIdFrom(relativePath, AGENT_SETTINGS)!!)
            agentIdFrom(relativePath, AGENT_TRANSCRIPT) != null -> refreshAgent(agentIdFrom(relativePath, AGENT_TRANSCRIPT)!!)
            workIdFrom(relativePath, WORK_PROFILE) != null -> refreshWork(workIdFrom(relativePath, WORK_PROFILE)!!)
            workIdFrom(relativePath, WORK_TIMELINE) != null -> refreshWork(workIdFrom(relativePath, WORK_TIMELINE)!!)
        }
    }

    suspend fun onDeleted(relativePath: String) {
        when {
            relativePath == StoragePaths.settingsPath() -> refreshSidebar()
            relativePath == "agents" || relativePath == "works" -> rebuild()
            agentIdFrom(relativePath, AGENT_DIR) != null -> dao.deleteAgent(agentIdFrom(relativePath, AGENT_DIR)!!)
            agentIdFrom(relativePath, AGENT_PROFILE) != null -> dao.deleteAgent(agentIdFrom(relativePath, AGENT_PROFILE)!!)
            workIdFrom(relativePath, WORK_DIR) != null -> deleteWork(workIdFrom(relativePath, WORK_DIR)!!)
            workIdFrom(relativePath, WORK_PROFILE) != null -> deleteWork(workIdFrom(relativePath, WORK_PROFILE)!!)
            agentIdFrom(relativePath, AGENT_SETTINGS) != null -> refreshAgent(agentIdFrom(relativePath, AGENT_SETTINGS)!!)
            agentIdFrom(relativePath, AGENT_TRANSCRIPT) != null -> refreshAgent(agentIdFrom(relativePath, AGENT_TRANSCRIPT)!!)
            workIdFrom(relativePath, WORK_TIMELINE) != null -> refreshWork(workIdFrom(relativePath, WORK_TIMELINE)!!)
        }
    }

    private suspend fun refreshAgent(id: String) {
        val entry = readAgent(id)
        if (entry == null) {
            dao.deleteAgent(id)
        } else {
            dao.upsertAgent(entry.toEntity())
        }
    }

    private suspend fun refreshWork(id: String) {
        val loaded = readWork(id)
        database.withTransaction {
            if (loaded == null) {
                dao.deleteWork(id)
                dao.deleteTasks(id)
            } else {
                dao.upsertWork(loaded.entry.toEntity())
                dao.deleteTasks(id)
                if (loaded.tasks.isNotEmpty()) dao.upsertTasks(loaded.tasks.map { it.toEntity() })
            }
        }
    }

    private suspend fun deleteWork(id: String) {
        database.withTransaction {
            dao.deleteWork(id)
            dao.deleteTasks(id)
        }
    }

    private suspend fun refreshSidebar() {
        val sidebar = readSidebar()
        database.withTransaction {
            dao.clearSections()
            dao.clearPins()
            writeSidebar(sidebar)
        }
    }

    private suspend fun writeSidebar(sidebar: com.nuum.contracts.SidebarOrganization?) {
        sidebar?.pinnedAgentIds?.forEachIndexed { index, agentId ->
            dao.upsertPins(listOf(SidebarPinEntity(agentId = agentId, position = index)))
        }
        sidebar?.sections?.forEachIndexed { index, section ->
            val agentIds = JSONArray()
            section.agentIds.forEach { agentIds.put(it) }
            dao.upsertSections(
                listOf(
                    SidebarSectionEntity(
                        id = section.id,
                        name = section.name,
                        position = index,
                        isCollapsed = section.isCollapsed,
                        agentIdsJson = agentIds.toString()
                    )
                )
            )
        }
    }

    private fun readSidebar(): com.nuum.contracts.SidebarOrganization? {
        val file = File(root, StoragePaths.settingsPath())
        if (!file.isFile) return null
        return SettingsJson.decode(file.readText(Charsets.UTF_8)).sidebar
    }

    private fun scanAgents(): List<AgentListEntry> {
        val dir = File(root, "agents")
        if (!dir.isDirectory) return emptyList()
        return dir.listFiles().orEmpty()
            .filter { it.isDirectory }
            .mapNotNull { child -> readAgent(child.name) }
    }

    private fun scanWorks(): List<LoadedWork> {
        val dir = File(root, "works")
        if (!dir.isDirectory) return emptyList()
        return dir.listFiles().orEmpty()
            .filter { it.isDirectory }
            .mapNotNull { child -> readWork(child.name) }
    }

    private fun readAgent(id: String): AgentListEntry? {
        val profile = File(root, StoragePaths.profilePath(id))
        if (!profile.isFile) return null
        val parsed = parseAgentProfile(id, profile.readText(Charsets.UTF_8)) ?: return null
        val settings = File(root, StoragePaths.agentSettingsPath(id))
        val hidden = if (settings.isFile) parseHiddenFromSidebar(settings.readText(Charsets.UTF_8)) else false
        val activity = JsonlFiles.lastCreatedAt(File(root, StoragePaths.transcriptPath(id)))
        return parsed.copy(
            hiddenFromSidebar = hidden,
            lastActivityAt = maxOf(parsed.createdAt, activity)
        )
    }

    private fun readWork(id: String): LoadedWork? {
        val profile = File(root, StoragePaths.workProfilePath(id))
        if (!profile.isFile) return null
        val parsed = parseWorkProfile(id, profile.readText(Charsets.UTF_8)) ?: return null
        val fold = foldTimeline(id, JsonlFiles.readLines(File(root, StoragePaths.workTimelinePath(id))))
        val entry = parsed.copy(
            lastActivityAt = maxOf(parsed.createdAt, fold.lastActivityAt),
            preview = fold.preview
        )
        return LoadedWork(entry, fold.tasks.values.toList())
    }

    private fun countProfiles(directory: String): Int {
        val dir = File(root, directory)
        if (!dir.isDirectory) return 0
        return dir.listFiles().orEmpty().count { child ->
            child.isDirectory && File(child, "profile.json").isFile
        }
    }

    private data class LoadedWork(val entry: WorkListEntry, val tasks: List<TaskListEntry>)

    private companion object {
        val AGENT_PROFILE = Regex("^agents/([^/]+)/profile\\.json$")
        val AGENT_SETTINGS = Regex("^agents/([^/]+)/settings\\.json$")
        val AGENT_TRANSCRIPT = Regex("^agents/([^/]+)/transcript\\.jsonl$")
        val AGENT_DIR = Regex("^agents/([^/]+)$")
        val WORK_PROFILE = Regex("^works/([^/]+)/profile\\.json$")
        val WORK_TIMELINE = Regex("^works/([^/]+)/timeline\\.jsonl$")
        val WORK_DIR = Regex("^works/([^/]+)$")
    }
}

private fun agentIdFrom(path: String, pattern: Regex): String? = pattern.matchEntire(path)?.groupValues?.get(1)

private fun workIdFrom(path: String, pattern: Regex): String? = pattern.matchEntire(path)?.groupValues?.get(1)

internal fun readMigrationVersion(root: File): Int {
    val marker = File(root, StoragePaths.migrationsPath())
    if (!marker.isFile) return 0
    return try {
        JSONObject(marker.readText(Charsets.UTF_8)).optInt("version", 0)
    } catch (_: JSONException) {
        0
    }
}

internal fun ensureMigrationMarker(root: File, beforeCommit: () -> Unit) {
    val marker = File(root, StoragePaths.migrationsPath())
    if (marker.exists()) return
    if (File(root, "sessions").isDirectory) return
    val body = JSONObject().put("version", StoragePaths.MIGRATION_VERSION).toString(2) + "\n"
    AtomicFiles.write(marker, body.toByteArray(Charsets.UTF_8), beforeCommit)
}

internal fun ensureLayout(root: File) {
    root.mkdirs()
    StoragePaths.topLevelDirectories.forEach { name -> File(root, name).mkdirs() }
}
