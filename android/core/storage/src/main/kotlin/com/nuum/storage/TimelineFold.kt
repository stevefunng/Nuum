package com.nuum.storage

import org.json.JSONException
import org.json.JSONObject

/**
 * Folds a work timeline into task rows and the sidebar preview.
 * Memory markdown is not read here. Chat text stays in the timeline file;
 * Room only keeps the list fields.
 */
internal class TimelineFold(private val workId: String) {
    val tasks = LinkedHashMap<String, TaskListEntry>()
    var lastActivityAt: Long = 0
    var preview: String? = null

    fun apply(line: String) {
        val json = try {
            JSONObject(line)
        } catch (_: JSONException) {
            return
        }
        val createdAt = if (json.has("createdAt") && !json.isNull("createdAt")) json.optLong("createdAt") else 0L
        if (createdAt > lastActivityAt) lastActivityAt = createdAt
        when (json.optString("type")) {
            "chat.posted" -> updatePreview(json.optString("body"))
            "task.created" -> applyCreated(json, createdAt)
            "task.claimed" -> applyClaimed(json, createdAt)
            "task.assigned" -> applyAssigned(json, createdAt)
            "task.delegated" -> applyDelegated(json, createdAt)
            "task.transitioned" -> applyTransitioned(json, createdAt)
            "task.handed_off" -> applyHandedOff(json, createdAt)
        }
    }

    private fun applyCreated(json: JSONObject, createdAt: Long) {
        val task = json.optJSONObject("task") ?: return
        val taskId = task.optString("id")
        val title = task.optString("title")
        if (taskId.isEmpty() || title.isEmpty() || tasks.containsKey(taskId)) return
        var owner = nullableString(task, "ownerAgentId")
        val actor = json.optJSONObject("actor")
        if (owner == null && actor?.optString("kind") == "agent") {
            owner = nullableString(actor, "id")
        }
        tasks[taskId] = TaskListEntry(
            workId = workId,
            taskId = taskId,
            title = title,
            state = task.optString("state").ifEmpty { "proposed" },
            updatedAt = if (task.has("updatedAt") && !task.isNull("updatedAt")) task.optLong("updatedAt") else createdAt,
            assigneeIds = stringList(task.optJSONArray("assigneeIds")),
            ownerAgentId = owner,
            revision = if (task.has("revision")) task.optInt("revision") else 1
        )
    }

    private fun applyClaimed(json: JSONObject, createdAt: Long) {
        val current = newer(json) ?: return
        tasks[current.taskId] = current.copy(
            assigneeIds = stringList(json.optJSONArray("assigneeIds")),
            state = "in_progress",
            revision = json.optInt("revision"),
            updatedAt = createdAt
        )
    }

    private fun applyAssigned(json: JSONObject, createdAt: Long) {
        val current = newer(json) ?: return
        tasks[current.taskId] = current.copy(
            assigneeIds = stringList(json.optJSONArray("assigneeIds")),
            revision = json.optInt("revision"),
            updatedAt = createdAt
        )
    }

    private fun applyDelegated(json: JSONObject, createdAt: Long) {
        val current = newer(json) ?: return
        val agentId = json.optString("agentId")
        val assignees = if (agentId.isEmpty() || agentId in current.assigneeIds) {
            current.assigneeIds
        } else {
            current.assigneeIds + agentId
        }
        tasks[current.taskId] = current.copy(
            state = "in_progress",
            assigneeIds = assignees,
            revision = json.optInt("revision"),
            updatedAt = createdAt
        )
    }

    private fun applyTransitioned(json: JSONObject, createdAt: Long) {
        val current = newer(json) ?: return
        if (current.state != json.optString("from")) return
        val to = json.optString("to")
        if (to.isEmpty()) return
        tasks[current.taskId] = current.copy(
            state = to,
            revision = json.optInt("revision"),
            updatedAt = createdAt
        )
    }

    private fun applyHandedOff(json: JSONObject, createdAt: Long) {
        if (json.has("messageId") && !json.isNull("messageId")) {
            updatePreview(json.optString("summary"))
        }
        val current = newer(json) ?: return
        val next = json.optString("nextStatus")
        if (next.isEmpty()) return
        tasks[current.taskId] = current.copy(
            state = next,
            revision = json.optInt("revision"),
            updatedAt = createdAt
        )
    }

    private fun newer(json: JSONObject): TaskListEntry? {
        val taskId = json.optString("taskId")
        val current = tasks[taskId] ?: return null
        val revision = json.optInt("revision")
        if (revision <= current.revision) return null
        return current
    }

    private fun updatePreview(raw: String) {
        val text = raw.replace(WHITESPACE, " ").trim().take(PREVIEW_LIMIT)
        if (text.isNotEmpty()) preview = text
    }

    private companion object {
        val WHITESPACE = Regex("\\s+")
        const val PREVIEW_LIMIT = 160
    }
}

internal fun foldTimeline(workId: String, lines: List<String>): TimelineFold {
    val fold = TimelineFold(workId)
    lines.forEach { fold.apply(it) }
    return fold
}
