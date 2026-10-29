package com.nuum.storage

import androidx.datastore.core.DataStore
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NuumException
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/**
 * Settled sidebar width. Drag thresholds stay in the UI; only the values Mac stores
 * under `nuum.ui.sidebar.v2` are written here.
 */
data class SidebarLayout(
    val expandedWidth: Int,
    val isCollapsed: Boolean
)

object SidebarLayoutLimits {
    const val DEFAULT_EXPANDED_WIDTH = 236
    const val MIN_EXPANDED_WIDTH = 220
    const val MAX_EXPANDED_WIDTH = 400
}

/** Mac `localStorage` key `nuum-identity-edited`: a set of agent ids whose identity was saved. */
object UiPreferenceKeys {
    const val IDENTITY_EDITED = "nuum-identity-edited"
    const val EXPANDED_WIDTH = "expandedWidth"
    const val IS_COLLAPSED = "isCollapsed"
}

internal class UiPreferences(
    private val dataStore: DataStore<Preferences>
) {
    val sidebarLayout: Flow<SidebarLayout> = dataStore.data.map { prefs -> readLayout(prefs) }

    val identityEdited: Flow<Set<String>> = dataStore.data.map { prefs ->
        prefs[IDENTITY] ?: emptySet()
    }

    suspend fun readSidebarLayout(): SidebarLayout = readLayout(dataStore.data.first())

    suspend fun writeSidebarLayout(layout: SidebarLayout) {
        val width = normalizeSidebarWidth(layout.expandedWidth)
        dataStore.edit { prefs ->
            prefs[EXPANDED_WIDTH] = width
            prefs[IS_COLLAPSED] = layout.isCollapsed
        }
    }

    suspend fun hasEditedIdentity(agentId: String): Boolean {
        requireAgentId(agentId)
        return agentId in (dataStore.data.first()[IDENTITY] ?: emptySet())
    }

    suspend fun markIdentityEdited(agentId: String) {
        requireAgentId(agentId)
        dataStore.edit { prefs ->
            prefs[IDENTITY] = (prefs[IDENTITY] ?: emptySet()) + agentId
        }
    }

    private fun readLayout(prefs: Preferences): SidebarLayout = SidebarLayout(
        expandedWidth = normalizeSidebarWidth(prefs[EXPANDED_WIDTH]),
        isCollapsed = prefs[IS_COLLAPSED] == true
    )

    private fun requireAgentId(agentId: String) {
        if (agentId.isEmpty()) {
            throw NuumException(KernelErrorCode.INVALID, "Agent id is empty")
        }
    }

    companion object {
        private val EXPANDED_WIDTH = intPreferencesKey(UiPreferenceKeys.EXPANDED_WIDTH)
        private val IS_COLLAPSED = booleanPreferencesKey(UiPreferenceKeys.IS_COLLAPSED)
        private val IDENTITY = stringSetPreferencesKey(UiPreferenceKeys.IDENTITY_EDITED)

        fun create(file: File, scope: CoroutineScope): UiPreferences {
            file.parentFile?.mkdirs()
            val store = PreferenceDataStoreFactory.create(
                corruptionHandler = ReplaceFileCorruptionHandler { emptyPreferences() },
                scope = scope,
                produceFile = { file }
            )
            return UiPreferences(store)
        }
    }
}

internal fun normalizeSidebarWidth(raw: Int?): Int {
    val value = if (raw == null || raw <= 0) {
        SidebarLayoutLimits.DEFAULT_EXPANDED_WIDTH
    } else {
        raw
    }
    return value.coerceIn(
        SidebarLayoutLimits.MIN_EXPANDED_WIDTH,
        SidebarLayoutLimits.MAX_EXPANDED_WIDTH
    )
}

/** Production file: `filesDir/datastore/nuum-ui.preferences_pb`, outside `filesDir/nuum`. */
internal fun uiPreferencesFile(filesDir: File): File =
    File(filesDir, "datastore/${StoragePaths.UI_PREFERENCES_NAME}.preferences_pb")
