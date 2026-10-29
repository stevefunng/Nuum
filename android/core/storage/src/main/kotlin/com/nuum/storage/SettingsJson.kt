package com.nuum.storage

import com.nuum.contracts.DEFAULT_SETTINGS
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.Language
import com.nuum.contracts.ModelRef
import com.nuum.contracts.NuumException
import com.nuum.contracts.ProviderId
import com.nuum.contracts.Settings
import com.nuum.contracts.SidebarOrganization
import com.nuum.contracts.SidebarSection
import com.nuum.contracts.ThemePreference
import com.nuum.contracts.ToolPermission
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * Global `settings.json` is the non-secret Mac document. Encoding writes only
 * [Settings] fields, so key material cannot round-trip through this file.
 */
internal object SettingsJson {
    fun encode(settings: Settings): String {
        val json = JSONObject()
        json.put("defaultToolPermission", settings.defaultToolPermission.wire)
        json.put(
            "defaultModel",
            JSONObject()
                .put("provider", settings.defaultModel.provider.wire)
                .put("model", settings.defaultModel.model)
        )
        json.put("theme", settings.theme.wire)
        json.put("language", settings.language.wire)
        settings.sidebar?.let { json.put("sidebar", encodeSidebar(it)) }
        return json.toString(2) + "\n"
    }

    fun decode(text: String): Settings {
        val json = try {
            JSONObject(text)
        } catch (_: JSONException) {
            return DEFAULT_SETTINGS
        }
        return fromObject(json)
    }

    /** Rewrites a global settings document to the schema. Invalid JSON is rejected without echoing it. */
    fun canonical(text: String): String {
        val json = try {
            JSONObject(text)
        } catch (_: JSONException) {
            throw NuumException(KernelErrorCode.INVALID, "settings.json must be a JSON object")
        }
        return encode(fromObject(json))
    }

    /**
     * Agent `settings.json` keeps its own shape. Secret-like keys are removed;
     * a document that already has none is returned unchanged.
     */
    fun stripSecretFields(text: String): String {
        val json = try {
            JSONObject(text)
        } catch (_: JSONException) {
            throw NuumException(KernelErrorCode.INVALID, "settings.json must be a JSON object")
        }
        if (!removeForbidden(json)) return text
        return json.toString(2) + "\n"
    }

    private fun fromObject(json: JSONObject): Settings {
        val permission = enumByWire<ToolPermission>(json.optString("defaultToolPermission"))
            ?: DEFAULT_SETTINGS.defaultToolPermission
        val model = parseModel(json.optJSONObject("defaultModel")) ?: DEFAULT_SETTINGS.defaultModel
        val theme = enumByWire<ThemePreference>(json.optString("theme")) ?: DEFAULT_SETTINGS.theme
        val language = enumByWire<Language>(json.optString("language")) ?: DEFAULT_SETTINGS.language
        val sidebar = if (json.has("sidebar") && !json.isNull("sidebar")) {
            parseSidebar(json.optJSONObject("sidebar"))
        } else {
            null
        }
        return Settings(
            defaultToolPermission = permission,
            defaultModel = model,
            theme = theme,
            language = language,
            sidebar = sidebar
        )
    }

    private fun parseModel(json: JSONObject?): ModelRef? {
        if (json == null) return null
        val provider = enumByWire<ProviderId>(json.optString("provider")) ?: return null
        val model = json.optString("model")
        if (model.isEmpty()) return null
        return ModelRef(provider, model)
    }

    private fun parseSidebar(json: JSONObject?): SidebarOrganization? {
        if (json == null) return null
        val sectionsJson = json.optJSONArray("sections") ?: JSONArray()
        val sections = buildList {
            for (index in 0 until sectionsJson.length()) {
                val section = sectionsJson.optJSONObject(index) ?: return null
                val id = section.optString("id")
                val name = section.optString("name").trim()
                if (id.isEmpty() || name.isEmpty()) return null
                add(
                    SidebarSection(
                        id = id,
                        name = name,
                        agentIds = stringList(section.optJSONArray("agentIds")),
                        isCollapsed = section.optBoolean("isCollapsed", false)
                    )
                )
            }
        }
        return SidebarOrganization(
            pinnedAgentIds = stringList(json.optJSONArray("pinnedAgentIds")),
            sections = sections
        )
    }

    private fun encodeSidebar(sidebar: SidebarOrganization): JSONObject {
        val pins = JSONArray()
        sidebar.pinnedAgentIds.forEach { pins.put(it) }
        val sections = JSONArray()
        sidebar.sections.forEach { section ->
            val agentIds = JSONArray()
            section.agentIds.forEach { agentIds.put(it) }
            sections.put(
                JSONObject()
                    .put("id", section.id)
                    .put("name", section.name)
                    .put("agentIds", agentIds)
                    .put("isCollapsed", section.isCollapsed)
            )
        }
        return JSONObject()
            .put("pinnedAgentIds", pins)
            .put("sections", sections)
    }

    private inline fun <reified T> enumByWire(wire: String): T? where T : Enum<T> {
        if (wire.isEmpty()) return null
        return enumValues<T>().firstOrNull { value ->
            when (value) {
                is ToolPermission -> value.wire == wire
                is ThemePreference -> value.wire == wire
                is Language -> value.wire == wire
                is ProviderId -> value.wire == wire
                else -> false
            }
        }
    }

    private fun removeForbidden(value: Any?): Boolean {
        var removed = false
        when (value) {
            is JSONObject -> {
                val keys = jsonKeys(value)
                for (key in keys) {
                    if (isForbiddenKey(key)) {
                        value.remove(key)
                        removed = true
                    } else if (removeForbidden(value.opt(key))) {
                        removed = true
                    }
                }
            }
            is JSONArray -> {
                for (index in 0 until value.length()) {
                    if (removeForbidden(value.opt(index))) removed = true
                }
            }
        }
        return removed
    }

    private fun isForbiddenKey(key: String): Boolean {
        val normalized = key.lowercase()
        return normalized.contains("key") ||
            normalized.contains("secret") ||
            normalized == "authorization"
    }
}

internal fun stringList(array: JSONArray?): List<String> {
    if (array == null) return emptyList()
    val values = LinkedHashSet<String>()
    for (index in 0 until array.length()) {
        if (array.isNull(index)) continue
        val text = array.optString(index).trim()
        if (text.isNotEmpty()) values += text
    }
    return values.toList()
}

internal fun jsonKeys(json: JSONObject): List<String> {
    val keys = mutableListOf<String>()
    val iterator = json.keys()
    while (iterator.hasNext()) keys += iterator.next()
    return keys
}

internal fun nullableString(json: JSONObject, key: String): String? {
    if (!json.has(key) || json.isNull(key)) return null
    return json.optString(key)
}
