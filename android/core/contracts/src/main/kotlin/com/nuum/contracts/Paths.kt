package com.nuum.contracts

/**
 * Paths relative to `filesDir/nuum`, matching the Mac data directory layout.
 * `secrets.bin` is not in that tree. It lives at `noBackupFilesDir/secrets.bin`.
 */
object NuumPaths {
    fun settingsPath(): String = "settings.json"
    fun agentDir(agentId: String): String = "agents/$agentId"
    fun profilePath(agentId: String): String = "agents/$agentId/profile.json"
    fun agentSettingsPath(agentId: String): String = "agents/$agentId/settings.json"
    fun transcriptPath(agentId: String): String = "agents/$agentId/transcript.jsonl"
    fun readCursorPath(agentId: String): String = "agents/$agentId/read-cursor.json"
    fun toolApprovalsPath(agentId: String): String = "agents/$agentId/tool-approvals.json"
    fun promptCachePath(agentId: String): String = "agents/$agentId/prompt-cache.json"
    fun memoryDir(agentId: String): String = "agents/$agentId/memory"
    fun scratchDir(agentId: String): String = "agents/$agentId/scratch"
    fun terminalsDir(agentId: String): String = "agents/$agentId/terminals"
    fun workDir(workId: String): String = "works/$workId"
    fun workProfilePath(workId: String): String = "works/$workId/profile.json"
    fun workCatalogPath(workId: String): String = "works/$workId/catalog.json"
    fun workTimelinePath(workId: String): String = "works/$workId/timeline.jsonl"
    fun workspaceRecordPath(workspaceId: String): String = "workspaces/$workspaceId.json"
    fun managedWorkspaceDir(workspaceId: String): String = "workspaces/$workspaceId"
    fun secretsFileName(): String = "secrets.bin"
}

/**
 * Byte and text port for the nuum data directory. Not a Room DAO.
 * Implementations create missing parents. [appendLine] writes one `\n`-terminated line.
 * [readText] and [readBytes] return null when the path is absent.
 */
interface AgentStore {
    fun settingsPath(): String = NuumPaths.settingsPath()
    fun agentDir(agentId: String): String = NuumPaths.agentDir(agentId)
    fun profilePath(agentId: String): String = NuumPaths.profilePath(agentId)
    fun agentSettingsPath(agentId: String): String = NuumPaths.agentSettingsPath(agentId)
    fun transcriptPath(agentId: String): String = NuumPaths.transcriptPath(agentId)
    fun readCursorPath(agentId: String): String = NuumPaths.readCursorPath(agentId)
    fun toolApprovalsPath(agentId: String): String = NuumPaths.toolApprovalsPath(agentId)
    fun promptCachePath(agentId: String): String = NuumPaths.promptCachePath(agentId)
    fun memoryDir(agentId: String): String = NuumPaths.memoryDir(agentId)
    fun scratchDir(agentId: String): String = NuumPaths.scratchDir(agentId)
    fun workDir(workId: String): String = NuumPaths.workDir(workId)
    fun workTimelinePath(workId: String): String = NuumPaths.workTimelinePath(workId)

    suspend fun readText(relativePath: String): String?
    suspend fun writeTextAtomic(relativePath: String, text: String)
    suspend fun appendLine(relativePath: String, line: String)
    suspend fun readBytes(relativePath: String): ByteArray?
    suspend fun writeBytesAtomic(relativePath: String, bytes: ByteArray)
    suspend fun readTail(relativePath: String, maxBytes: Int): String
    suspend fun list(relativePath: String): List<String>
    suspend fun delete(relativePath: String)
    suspend fun exists(relativePath: String): Boolean
}
