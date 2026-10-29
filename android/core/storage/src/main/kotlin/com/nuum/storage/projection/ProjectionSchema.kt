package com.nuum.storage.projection

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.RoomDatabase
import com.nuum.storage.AgentListEntry
import com.nuum.storage.SidebarSectionEntry
import com.nuum.storage.TaskListEntry
import com.nuum.storage.WorkListEntry
import org.json.JSONArray
import org.json.JSONException

@Entity(tableName = "agent_list")
data class AgentListEntity(
    @PrimaryKey val id: String,
    val name: String,
    val description: String,
    val createdAt: Long,
    val tagsJson: String,
    val avatarColor: String?,
    val avatarShape: String?,
    val avatarMaterial: String?,
    val hiddenFromSidebar: Boolean,
    val lastActivityAt: Long
)

@Entity(tableName = "work_list")
data class WorkListEntity(
    @PrimaryKey val id: String,
    val name: String,
    val description: String,
    val projectRoot: String?,
    val createdAt: Long,
    val kind: String?,
    val avatar: String?,
    val workspaceId: String?,
    val lastActivityAt: Long,
    val preview: String?
)

@Entity(tableName = "task_rows", primaryKeys = ["workId", "taskId"])
data class TaskRowEntity(
    val workId: String,
    val taskId: String,
    val title: String,
    val state: String,
    val updatedAt: Long,
    val assigneeIdsJson: String,
    val ownerAgentId: String?,
    val revision: Int
)

@Entity(tableName = "sidebar_sections")
data class SidebarSectionEntity(
    @PrimaryKey val id: String,
    val name: String,
    val position: Int,
    val isCollapsed: Boolean,
    val agentIdsJson: String
)

@Entity(tableName = "sidebar_pins")
data class SidebarPinEntity(
    @PrimaryKey val agentId: String,
    val position: Int
)

@Entity(tableName = "projection_meta")
data class ProjectionMetaEntity(
    @PrimaryKey val id: Int = 1,
    val migrationsVersion: Int
)

fun AgentListEntity.toEntry(): AgentListEntry = AgentListEntry(
    id = id,
    name = name,
    description = description,
    createdAt = createdAt,
    tags = decodeStringList(tagsJson),
    avatarColor = avatarColor,
    avatarShape = avatarShape,
    avatarMaterial = avatarMaterial,
    hiddenFromSidebar = hiddenFromSidebar,
    lastActivityAt = lastActivityAt
)

fun AgentListEntry.toEntity(): AgentListEntity = AgentListEntity(
    id = id,
    name = name,
    description = description,
    createdAt = createdAt,
    tagsJson = encodeStringList(tags),
    avatarColor = avatarColor,
    avatarShape = avatarShape,
    avatarMaterial = avatarMaterial,
    hiddenFromSidebar = hiddenFromSidebar,
    lastActivityAt = lastActivityAt
)

fun WorkListEntity.toEntry(): WorkListEntry = WorkListEntry(
    id = id,
    name = name,
    description = description,
    projectRoot = projectRoot,
    createdAt = createdAt,
    kind = kind,
    avatar = avatar,
    workspaceId = workspaceId,
    lastActivityAt = lastActivityAt,
    preview = preview
)

fun WorkListEntry.toEntity(): WorkListEntity = WorkListEntity(
    id = id,
    name = name,
    description = description,
    projectRoot = projectRoot,
    createdAt = createdAt,
    kind = kind,
    avatar = avatar,
    workspaceId = workspaceId,
    lastActivityAt = lastActivityAt,
    preview = preview
)

fun TaskRowEntity.toEntry(): TaskListEntry = TaskListEntry(
    workId = workId,
    taskId = taskId,
    title = title,
    state = state,
    updatedAt = updatedAt,
    assigneeIds = decodeStringList(assigneeIdsJson),
    ownerAgentId = ownerAgentId,
    revision = revision
)

fun TaskListEntry.toEntity(): TaskRowEntity = TaskRowEntity(
    workId = workId,
    taskId = taskId,
    title = title,
    state = state,
    updatedAt = updatedAt,
    assigneeIdsJson = encodeStringList(assigneeIds),
    ownerAgentId = ownerAgentId,
    revision = revision
)

fun SidebarSectionEntity.toEntry(): SidebarSectionEntry = SidebarSectionEntry(
    id = id,
    name = name,
    agentIds = decodeStringList(agentIdsJson),
    isCollapsed = isCollapsed
)

private fun encodeStringList(values: List<String>): String {
    val array = JSONArray()
    values.forEach { array.put(it) }
    return array.toString()
}

private fun decodeStringList(raw: String): List<String> {
    val array = try {
        JSONArray(raw)
    } catch (_: JSONException) {
        return emptyList()
    }
    val values = mutableListOf<String>()
    for (index in 0 until array.length()) {
        val text = array.optString(index)
        if (text.isNotEmpty()) values += text
    }
    return values
}

@Dao
interface ProjectionDao {
    @Query("SELECT * FROM agent_list ORDER BY lastActivityAt DESC, id ASC")
    suspend fun agents(): List<AgentListEntity>

    @Query("SELECT COUNT(*) FROM agent_list")
    suspend fun agentCount(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAgent(row: AgentListEntity)

    @Query("DELETE FROM agent_list WHERE id = :id")
    suspend fun deleteAgent(id: String)

    @Query("DELETE FROM agent_list")
    suspend fun clearAgents()

    @Query("SELECT * FROM work_list ORDER BY lastActivityAt DESC, id ASC")
    suspend fun works(): List<WorkListEntity>

    @Query("SELECT COUNT(*) FROM work_list")
    suspend fun workCount(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertWork(row: WorkListEntity)

    @Query("DELETE FROM work_list WHERE id = :id")
    suspend fun deleteWork(id: String)

    @Query("DELETE FROM work_list")
    suspend fun clearWorks()

    @Query("SELECT * FROM task_rows WHERE workId = :workId ORDER BY updatedAt DESC, taskId ASC")
    suspend fun tasks(workId: String): List<TaskRowEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertTasks(rows: List<TaskRowEntity>)

    @Query("DELETE FROM task_rows WHERE workId = :workId")
    suspend fun deleteTasks(workId: String)

    @Query("DELETE FROM task_rows")
    suspend fun clearTasks()

    @Query("SELECT * FROM sidebar_sections ORDER BY position ASC")
    suspend fun sections(): List<SidebarSectionEntity>

    @Query("SELECT * FROM sidebar_pins ORDER BY position ASC")
    suspend fun pins(): List<SidebarPinEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSections(rows: List<SidebarSectionEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertPins(rows: List<SidebarPinEntity>)

    @Query("DELETE FROM sidebar_sections")
    suspend fun clearSections()

    @Query("DELETE FROM sidebar_pins")
    suspend fun clearPins()

    @Query("SELECT * FROM projection_meta WHERE id = 1")
    suspend fun meta(): ProjectionMetaEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMeta(row: ProjectionMetaEntity)

    @Query("DELETE FROM projection_meta")
    suspend fun clearMeta()
}

@Database(
    entities = [
        AgentListEntity::class,
        WorkListEntity::class,
        TaskRowEntity::class,
        SidebarSectionEntity::class,
        SidebarPinEntity::class,
        ProjectionMetaEntity::class
    ],
    version = 1,
    exportSchema = false
)
abstract class NuumDatabase : RoomDatabase() {
    abstract fun projectionDao(): ProjectionDao
}
