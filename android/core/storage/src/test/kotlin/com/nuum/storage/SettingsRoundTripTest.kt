package com.nuum.storage

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.nuum.contracts.DEFAULT_SETTINGS
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.Language
import com.nuum.contracts.ModelRef
import com.nuum.contracts.NuumException
import com.nuum.contracts.NuumPaths
import com.nuum.contracts.ProviderId
import com.nuum.contracts.Settings
import com.nuum.contracts.SidebarOrganization
import com.nuum.contracts.SidebarSection
import com.nuum.contracts.ThemePreference
import com.nuum.contracts.ToolPermission
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsRoundTripTest : StorageRobolectricTest() {
    @Test
    fun settingsRoundTripHasNoKeyFields() = withStore { store ->
        assertEquals(DEFAULT_SETTINGS, store.readSettings())
        assertFalse(store.exists(NuumPaths.settingsPath()))

        val settings = Settings(
            defaultToolPermission = ToolPermission.ALWAYS,
            defaultModel = ModelRef(ProviderId.OPENAI, "gpt-4o"),
            theme = ThemePreference.LIGHT,
            language = Language.EN,
            sidebar = SidebarOrganization(
                pinnedAgentIds = listOf("a1"),
                sections = listOf(
                    SidebarSection(
                        id = "g1",
                        name = "Research",
                        agentIds = listOf("a1", "a2"),
                        isCollapsed = true
                    )
                )
            )
        )
        store.writeSettings(settings)
        val raw = store.readText(NuumPaths.settingsPath())!!
        assertNoKeyFields(raw)
        assertFalse(raw.contains("openaiApiKey"))
        assertFalse(raw.contains("anthropicApiKey"))
        assertFalse(raw.contains("deepseekApiKey"))
        assertFalse(raw.contains("hasOpenaiKey"))
        assertFalse(raw.contains("sk-"))
        assertEquals(settings, store.readSettings())
        store.writeSettings(store.readSettings())
        assertEquals(settings, store.readSettings())
        assertEquals(listOf("a1"), store.sidebarPins())
        val section = store.sidebarSections().single()
        assertEquals("g1", section.id)
        assertEquals("Research", section.name)
        assertEquals(listOf("a1", "a2"), section.agentIds)
        assertTrue(section.isCollapsed)

        store.discardListProjection()
        store.rebuildListProjection()
        assertEquals(listOf("a1"), store.sidebarPins())
        assertEquals("Research", store.sidebarSections().single().name)
    }

    @Test
    fun aKeyFieldInTheDocumentIsStrippedOnWrite() = withStore { store ->
        store.writeTextAtomic(
            NuumPaths.settingsPath(),
            """{"theme":"light","openaiApiKey":"sk-test-secret","hasOpenaiKey":true,"defaultModel":{"provider":"openai","model":"gpt-4o","apiKey":"sk-nested"}}"""
        )
        val raw = store.readText(NuumPaths.settingsPath())!!
        assertNoKeyFields(raw)
        assertFalse(raw.contains("sk-test-secret"))
        assertFalse(raw.contains("sk-nested"))
        assertFalse(raw.contains("openaiApiKey"))
        assertFalse(raw.contains("hasOpenaiKey"))
        assertFalse(raw.contains("apiKey"))
        val read = store.readSettings()
        assertEquals(ThemePreference.LIGHT, read.theme)
        assertEquals(ProviderId.OPENAI, read.defaultModel.provider)
        assertEquals("gpt-4o", read.defaultModel.model)
        assertEquals(ToolPermission.ASK, read.defaultToolPermission)
        assertEquals(Language.ZH_CN, read.language)
        assertNull(read.sidebar)
        store.writeSettings(read)
        assertEquals(read, store.readSettings())
        assertNoKeyFields(store.readText(NuumPaths.settingsPath())!!)
    }

    @Test
    fun invalidSettingsJsonIsRejectedWithoutEchoingTheBody() = withStore { store ->
        try {
            store.writeTextAtomic(NuumPaths.settingsPath(), "not-json sk-secret-value")
            throw AssertionError("expected invalid settings to be rejected")
        } catch (error: NuumException) {
            assertEquals(KernelErrorCode.INVALID, error.code)
            assertFalse(error.message.contains("sk-secret-value"))
            assertFalse(error.message.contains("not-json"))
        }
        assertFalse(store.exists(NuumPaths.settingsPath()))
    }

    @Test
    fun agentSettingsDropNestedKeysAndKeepTheRest() = withStore { store ->
        store.writeTextAtomic(
            NuumPaths.profilePath("a1"),
            """{"id":"a1","name":"One","description":"","createdAt":5}"""
        )
        store.writeTextAtomic(
            NuumPaths.agentSettingsPath("a1"),
            """{"model":{"provider":"deepseek","model":"deepseek-chat","apiKey":"sk-agent"},"hiddenFromSidebar":true}"""
        )
        val raw = store.readText(NuumPaths.agentSettingsPath("a1"))!!
        assertFalse(raw.contains("sk-agent"))
        assertFalse(raw.contains("apiKey"))
        assertTrue(raw.contains("hiddenFromSidebar"))
        assertTrue(raw.contains("deepseek-chat"))
        assertTrue(store.agentList().single().hiddenFromSidebar)
    }

    @Test
    fun uiPreferencesStayOutOfSettingsAndTheNuumTree() = withStore { store ->
        store.writeSidebarLayout(SidebarLayout(320, true))
        store.markIdentityEdited("a1")
        store.writeSettings(DEFAULT_SETTINGS)
        val raw = store.readText(NuumPaths.settingsPath())!!
        assertFalse(raw.contains("expandedWidth"))
        assertFalse(raw.contains("nuum-identity-edited"))
        assertFalse(raw.contains("isCollapsed"))
        assertTrue(store.root.walkTopDown().none { it.name.contains("preferences") || it.name.contains("nuum-ui") })
    }

    @Test
    fun createStoresUiPreferencesOutsideTheNuumDirectory() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val store = FileAgentStore.create(context)
        try {
            kotlinx.coroutines.runBlocking {
                store.open()
                store.writeSidebarLayout(SidebarLayout(280, false))
                store.markIdentityEdited("nunu")
                val nuum = File(context.filesDir, "nuum")
                assertTrue(nuum.isDirectory)
                assertTrue(
                    nuum.walkTopDown().none { file ->
                        file.name.contains("preferences") || file.name.contains("nuum-ui")
                    }
                )
                val prefs = File(context.filesDir, "datastore/nuum-ui.preferences_pb")
                assertTrue(prefs.isFile)
                assertTrue(prefs.parentFile!!.absolutePath != nuum.absolutePath)
                assertEquals(280, store.readSidebarLayout().expandedWidth)
                assertTrue(store.hasEditedIdentity("nunu"))
                val marker = File(nuum, "migrations.json")
                assertTrue(marker.isFile)
                assertFalse(marker.readText().contains("key"))
            }
        } finally {
            store.close()
        }
    }
}

private fun assertNoKeyFields(text: String) {
    fun walk(value: Any?) {
        when (value) {
            is JSONObject -> {
                val keys = value.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    val lower = key.lowercase()
                    assertFalse("key field $key", lower.contains("key"))
                    assertFalse("secret field $key", lower.contains("secret"))
                    assertFalse(lower == "authorization")
                    walk(value.get(key))
                }
            }
            is JSONArray -> {
                for (index in 0 until value.length()) walk(value.get(index))
            }
        }
    }
    walk(JSONObject(text))
}
