package com.nuum.storage

import org.json.JSONException
import org.json.JSONObject

internal fun parseAgentProfile(directoryName: String, text: String): AgentListEntry? {
    val json = try {
        JSONObject(text)
    } catch (_: JSONException) {
        return null
    }
    val id = json.optString("id")
    if (id.isEmpty() || id != directoryName || !json.has("name") || !json.has("createdAt")) return null
    val createdAt = json.optLong("createdAt")
    return AgentListEntry(
        id = id,
        name = json.optString("name"),
        description = if (json.has("description") && !json.isNull("description")) json.optString("description") else "",
        createdAt = createdAt,
        tags = stringList(json.optJSONArray("tags")),
        avatarColor = nullableString(json, "avatarColor"),
        avatarShape = nullableString(json, "avatarShape"),
        avatarMaterial = nullableString(json, "avatarMaterial"),
        hiddenFromSidebar = false,
        lastActivityAt = createdAt
    )
}

internal fun parseHiddenFromSidebar(text: String): Boolean {
    val json = try {
        JSONObject(text)
    } catch (_: JSONException) {
        return false
    }
    return json.optBoolean("hiddenFromSidebar", false)
}

internal fun parseWorkProfile(directoryName: String, text: String): WorkListEntry? {
    val json = try {
        JSONObject(text)
    } catch (_: JSONException) {
        return null
    }
    val id = json.optString("id")
    val name = json.optString("name")
    if (id.isEmpty() || id != directoryName || name.isEmpty() || !json.has("createdAt")) return null
    val createdAt = json.optLong("createdAt")
    return WorkListEntry(
        id = id,
        name = name,
        description = if (json.has("description") && !json.isNull("description")) json.optString("description") else "",
        projectRoot = nullableString(json, "projectRoot"),
        createdAt = createdAt,
        kind = nullableString(json, "kind"),
        avatar = nullableString(json, "avatar"),
        workspaceId = nullableString(json, "workspaceId"),
        lastActivityAt = createdAt,
        preview = null
    )
}
