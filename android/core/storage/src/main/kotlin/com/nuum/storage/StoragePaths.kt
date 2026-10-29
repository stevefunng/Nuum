package com.nuum.storage

import com.nuum.contracts.NuumPaths
import java.security.MessageDigest

/**
 * Relative paths under `filesDir/nuum`, comparable to the Mac data directory.
 *
 * Shared layout comes from [NuumPaths]. Session directories and the migration
 * marker are not on that contract yet; their strings match
 * `packages/host/src/session-store.ts` and `agent-store.ts`.
 */
object StoragePaths {
    const val MIGRATION_VERSION = 3

    /** Same tail window as Mac `TAIL_WINDOW` in `agent-store.ts`. */
    const val TAIL_WINDOW_BYTES = 64 * 1024

    /** DataStore name for UI prefs. The file lives outside the nuum tree. */
    const val UI_PREFERENCES_NAME = "nuum-ui"

    fun settingsPath(): String = NuumPaths.settingsPath()
    fun migrationsPath(): String = "migrations.json"
    fun agentDir(agentId: String): String = NuumPaths.agentDir(agentId)
    fun profilePath(agentId: String): String = NuumPaths.profilePath(agentId)
    fun agentSettingsPath(agentId: String): String = NuumPaths.agentSettingsPath(agentId)
    fun transcriptPath(agentId: String): String = NuumPaths.transcriptPath(agentId)
    fun readCursorPath(agentId: String): String = NuumPaths.readCursorPath(agentId)
    fun toolApprovalsPath(agentId: String): String = NuumPaths.toolApprovalsPath(agentId)
    fun promptCachePath(agentId: String): String = NuumPaths.promptCachePath(agentId)
    fun memoryDir(agentId: String): String = NuumPaths.memoryDir(agentId)
    fun scratchDir(agentId: String): String = NuumPaths.scratchDir(agentId)
    fun terminalsDir(agentId: String): String = NuumPaths.terminalsDir(agentId)
    fun workDir(workId: String): String = NuumPaths.workDir(workId)
    fun workProfilePath(workId: String): String = NuumPaths.workProfilePath(workId)
    fun workCatalogPath(workId: String): String = NuumPaths.workCatalogPath(workId)
    fun workTimelinePath(workId: String): String = NuumPaths.workTimelinePath(workId)
    fun workspaceRecordPath(workspaceId: String): String = NuumPaths.workspaceRecordPath(workspaceId)
    fun managedWorkspaceDir(workspaceId: String): String = NuumPaths.managedWorkspaceDir(workspaceId)
    fun secretsFileName(): String = NuumPaths.secretsFileName()

    /** `sha256(owner)`, the Mac workspace record id. */
    fun workspaceIdForOwner(owner: String): String = sha256Hex(owner)

    fun workspaceRecordPathForOwner(owner: String): String =
        workspaceRecordPath(workspaceIdForOwner(owner))

    /**
     * `JSON.stringify([workId, taskId, agentId, membershipRevision])` as Node emits it,
     * which is the input to the card session id.
     */
    fun cardSessionPayload(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ): String = "[${jsonString(workId)},${jsonString(taskId)},${jsonString(agentId)},$membershipRevision]"

    fun cardSessionId(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ): String = sha256Hex(cardSessionPayload(workId, taskId, agentId, membershipRevision))

    /** `sha256(workId)`, the first path component under `work-sessions/`. */
    fun workSessionRoom(workId: String): String = sha256Hex(workId)

    fun workSessionDir(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ): String {
        val room = workSessionRoom(workId)
        val id = cardSessionId(workId, taskId, agentId, membershipRevision)
        return "work-sessions/$room/$id"
    }

    fun workSessionRecordPath(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ): String = workSessionDir(workId, taskId, agentId, membershipRevision) + "/session.json"

    fun workSessionTranscriptPath(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ): String = workSessionDir(workId, taskId, agentId, membershipRevision) + "/transcript.jsonl"

    fun sha256Hex(text: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
        val alphabet = "0123456789abcdef"
        val out = CharArray(digest.size * 2)
        digest.forEachIndexed { index, byte ->
            val value = byte.toInt() and 0xff
            out[index * 2] = alphabet[value ushr 4]
            out[index * 2 + 1] = alphabet[value and 0x0f]
        }
        return String(out)
    }

    val topLevelDirectories: List<String> = listOf(
        "agents",
        "works",
        "work-sessions",
        "workspaces"
    )

    private fun jsonString(value: String): String = buildString {
        append('"')
        value.forEach { char ->
            when (char) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (char.code < 0x20) {
                    append("\\u")
                    append(char.code.toString(16).padStart(4, '0'))
                } else {
                    append(char)
                }
            }
        }
        append('"')
    }
}
