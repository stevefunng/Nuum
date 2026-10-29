package com.nuum.feature.settings

import android.content.res.Configuration
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasStateDescription
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ApplicationProvider
import com.nuum.contracts.DEFAULT_MODEL_ID
import com.nuum.contracts.Language
import com.nuum.contracts.ProactiveActivity
import com.nuum.contracts.ProviderId
import com.nuum.contracts.Secrets
import com.nuum.contracts.ThemePreference
import java.util.Locale
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SettingsScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    @After
    fun clearViewModels() {
        compose.activity.viewModelStore.clear()
    }

    @Test
    fun screensRenderWithoutNetwork() {
        val harness = Harness()
        compose.setContent {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) {
                    SettingsScreen(
                        dependencies = harness.dependencies,
                        onClose = {},
                        onOpenProactive = {}
                    )
                }
                Box(Modifier.weight(1f)) {
                    ProactiveScreen(
                        dependencies = harness.dependencies,
                        onBack = {},
                        onOpenAgent = {},
                        onOpenShell = {}
                    )
                }
            }
        }
        compose.waitUntil(5_000) {
            compose.onAllNodes(hasStateDescription("loaded")).fetchSemanticsNodes().size >= 2
        }
        assertText("General")
        assertText("Models")
        compose.onNodeWithTag("section-models").performClick()
        assertText("Encrypted on this device using OS protection and provided to the service at runtime.")
        assertEquals(0, harness.store.readCount)
        assertTrue(harness.writer.writes.isEmpty())
        assertText("Check setup")
        compose.onNodeWithText("Quit").assertDoesNotExist()
        compose.onNodeWithTag("agent-actions-status").assertExists()
    }

    @Test
    @Config(sdk = [34], qualifiers = "w1000dp-h900dp")
    fun wideSettingsUsesTheSideNav() {
        val harness = Harness()
        compose.setContent {
            SettingsScreen(harness.dependencies, onClose = {}, onOpenProactive = {})
        }
        waitUntilLoaded()
        compose.onNodeWithTag("settings-sections").assertExists()
        compose.onNodeWithTag("section-general").assertExists()
        compose.onNodeWithTag("section-models").performClick()
        assertText("API keys")
    }

    @Test
    fun selectorsStayDisabledUntilSettingsLoad() {
        val harness = Harness()
        harness.settings.getGate = kotlinx.coroutines.CompletableDeferred()
        compose.setContent {
            SettingsScreen(harness.dependencies, onClose = {}, onOpenProactive = {})
        }
        compose.waitForIdle()
        compose.onNodeWithTag("language-select").assertIsNotEnabled()
        compose.onNodeWithTag("section-models").performClick()
        compose.onNodeWithTag("provider-select").assertIsNotEnabled()
        compose.onNodeWithText("DeepSeek").assertDoesNotExist()
        harness.settings.getGate?.complete(Unit)
        waitUntilLoaded()
        compose.onNodeWithTag("provider-select").assertExists()
    }

    @Test
    fun switchingProviderOnScreenUsesDefaultModelId() {
        val harness = Harness()
        compose.setContent {
            SettingsScreen(harness.dependencies, onClose = {}, onOpenProactive = {})
        }
        waitUntilLoaded()
        compose.onNodeWithTag("section-models").performClick()
        compose.onNodeWithTag("provider-select").performClick()
        compose.onNodeWithTag("option-openai").performClick()
        compose.waitUntil { harness.settings.current.defaultModel.provider == ProviderId.OPENAI }
        assertEquals(DEFAULT_MODEL_ID.getValue(ProviderId.OPENAI), harness.settings.current.defaultModel.model)
        compose.onNodeWithTag("provider-select").performClick()
        compose.onNodeWithTag("option-deepseek").performClick()
        compose.waitUntil { harness.settings.current.defaultModel.provider == ProviderId.DEEPSEEK }
        assertEquals(DEEPSEEK_CHAT, harness.settings.current.defaultModel.model)
    }

    @Test
    fun blurEmptyStringDeletesTheKeyAndATypedKeyRoundTripsThroughSecretStore() {
        val harness = Harness()
        compose.setContent {
            SettingsScreen(harness.dependencies, onClose = {}, onOpenProactive = {})
        }
        waitUntilLoaded()
        compose.onNodeWithTag("section-models").performClick()
        compose.onNodeWithTag("api-key-deepseek").performClick()
        compose.onNodeWithTag("api-key-deepseek").performTextInput("sk-test-deepseek")
        compose.onNodeWithTag("api-key-deepseek").performImeAction()
        compose.waitUntil(5_000) { harness.writer.writes.isNotEmpty() }
        assertEquals(0, harness.store.readCount)
        assertEquals("sk-test-deepseek", harness.store.load().deepseekApiKey)

        compose.onNodeWithTag("api-key-deepseek").performTextClearance()
        compose.onNodeWithTag("api-key-deepseek").performImeAction()
        compose.waitUntil(5_000) { harness.writer.writes.last().second?.isEmpty() == true }
        assertNull(harness.store.load().deepseekApiKey)
    }

    @Test
    fun storedKeyIsNotShownWhenTheScreenOpens() {
        val harness = Harness()
        val stored = "sk-stored-not-in-ui"
        runBlocking { harness.store.write(Secrets(deepseekApiKey = stored)) }
        compose.setContent {
            SettingsScreen(harness.dependencies, onClose = {}, onOpenProactive = {})
        }
        waitUntilLoaded()
        compose.onNodeWithTag("section-models").performClick()
        assertEquals(0, compose.onAllNodesWithText(stored, substring = true).fetchSemanticsNodes().size)
        assertEquals(0, harness.store.readCount)
        assertTrue(harness.writer.writes.isEmpty())
    }

    @Test
    fun languageAndThemeApplyImmediately() {
        val harness = Harness()
        compose.setContent {
            SettingsScreen(
                dependencies = harness.dependencies,
                onClose = {},
                onOpenProactive = {}
            )
        }
        waitUntilLoaded()
        compose.onNodeWithTag("nuum-dark").assertExists()
        compose.onNodeWithTag("language-select").performClick()
        compose.onNodeWithTag("option-zh-CN").performClick()
        compose.waitUntil { harness.settings.current.language == Language.ZH_CN }
        assertText("通用")
        assertText("外观")
        compose.onNodeWithTag("theme-select").performClick()
        compose.onNodeWithTag("option-light").performClick()
        compose.waitUntil { harness.settings.current.theme == ThemePreference.LIGHT }
        compose.onNodeWithTag("nuum-light").assertExists()
    }

    @Test
    fun followSystemTracksThePlatformSetting() {
        val harness = Harness(
            settings = FakeSettingsPort(sampleSettings(theme = ThemePreference.SYSTEM))
        )
        val systemDark = androidx.compose.runtime.mutableStateOf(true)
        compose.setContent {
            SettingsScreen(
                dependencies = harness.dependencies,
                onClose = {},
                onOpenProactive = {},
                systemDark = systemDark.value
            )
        }
        waitUntilLoaded()
        compose.onNodeWithTag("nuum-dark").assertExists()
        systemDark.value = false
        compose.waitForIdle()
        compose.onNodeWithTag("nuum-light").assertExists()
    }

    @Test
    fun proactiveActionsFollowTheSnapshotAndThereIsNoActionsSwitch() {
        val off = Harness(
            proactive = FakeProactivePort(
                proactiveSnapshot(
                    agent = proactiveAgent(enabled = true, state = "ready", name = "Mika"),
                    actionsAvailable = false,
                    sources = listOf("notes")
                )
            )
        )
        compose.setContent {
            ProactiveScreen(off.dependencies, onBack = {}, onOpenAgent = {}, onOpenShell = {})
        }
        waitUntilLoaded()
        compose.onNodeWithTag("agent-actions-status").assertExists()
        compose.onNodeWithText("Not connected").assertExists()
        compose.onNodeWithTag("context-sources-status").assertExists()
        compose.onNodeWithText("Available").assertExists()
        compose.onNodeWithText("Mika").assertExists()
        assertEquals(1, compose.onAllNodes(androidx.compose.ui.test.hasTestTag("proactive-switch")).fetchSemanticsNodes().size)
        compose.onNodeWithText("Enable actions").assertDoesNotExist()

    }

    @Test
    fun agentActionsLabelFollowsAConnectedSnapshot() {
        val on = Harness(
            proactive = FakeProactivePort(
                proactiveSnapshot(
                    agent = proactiveAgent(enabled = true, state = "ready"),
                    actionsAvailable = true
                )
            )
        )
        compose.setContent {
            ProactiveScreen(on.dependencies, onBack = {}, onOpenAgent = {}, onOpenShell = {})
        }
        waitUntilLoaded()
        compose.onNodeWithTag("agent-actions-status").assertExists()
        assertText("Available")
        compose.onNodeWithText("Not connected").assertExists()
    }

    @Test
    fun pauseCheckAndRetryResendsTheLastCall() {
        var opened: String? = null
        val proactive = FakeProactivePort(
            proactiveSnapshot(
                agent = proactiveAgent(
                    enabled = true,
                    state = "waiting-context",
                    revision = 3,
                    activity = listOf(
                        ProactiveActivity("a", 1_700_000_000_000, "enabled"),
                        ProactiveActivity("b", 1_700_000_060_000, "no-change"),
                        ProactiveActivity("c", 1_700_000_120_000, "error"),
                        ProactiveActivity("d", 1_700_000_180_000, "paused")
                    )
                )
            )
        )
        val clock = FakeClock(now = 10_000L)
        val harness = Harness(proactive = proactive, clock = clock)
        compose.setContent {
            ProactiveScreen(
                dependencies = harness.dependencies,
                onBack = {},
                onOpenAgent = { opened = it },
                onOpenShell = {}
            )
        }
        waitUntilLoaded()
        compose.onNodeWithText("Proactive enabled").assertExists()
        compose.onNodeWithText("Paused").assertDoesNotExist()
        compose.onNodeWithTag("pause-select").performClick()
        compose.onNodeWithText("For 30 minutes").performClick()
        compose.waitUntil { proactive.configures.isNotEmpty() }
        assertEquals(10_000L + PAUSE_30_MINUTES_MS, proactive.configures.single().pausedUntil)
        compose.onNodeWithTag("resume-now").performClick()
        compose.waitUntil { proactive.configures.size == 2 }
        compose.onNodeWithTag("check-setup").performClick()
        compose.waitUntil { proactive.checks.single() == "agent-1" }
        proactive.failCheck = true
        compose.onNodeWithTag("check-setup").performClick()
        compose.waitUntil { compose.onAllNodesWithText("Could not update proactive mode.").fetchSemanticsNodes().isNotEmpty() }
        proactive.failCheck = false
        compose.onNodeWithTag("proactive-retry").performScrollTo().performClick()
        compose.waitUntil(5_000) { proactive.checks.size == 3 }
        compose.onNodeWithTag("open-nunu").performClick()
        assertEquals("agent-1", opened)
    }

    private fun assertText(text: String) {
        assertTrue(compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty())
    }

    private fun waitUntilLoaded() {
        compose.waitUntil(timeoutMillis = 5_000) {
            compose.onAllNodes(hasStateDescription("loaded")).fetchSemanticsNodes().isNotEmpty()
        }
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SettingsCopyResourceTest {
    @Test
    fun xmlMatchesMessages() {
        val base = ApplicationProvider.getApplicationContext<android.content.Context>()
        val english = localized(base, "en")
        val chinese = localized(base, "zh-CN")
        SettingsCopy.resourceIds.forEach { (key, id) ->
            assertEquals(SettingsCopy.text(Language.EN, key), english.getString(id))
            assertEquals(SettingsCopy.text(Language.ZH_CN, key), chinese.getString(id))
        }
    }

    private fun localized(base: android.content.Context, tag: String): android.content.Context {
        val configuration = Configuration(base.resources.configuration)
        configuration.setLocale(Locale.forLanguageTag(tag))
        return base.createConfigurationContext(configuration)
    }
}

class SettingsSourceTest {
    @Test
    fun uiDoesNotImportNetworkOrReadSecretsBack() {
        val sources = java.io.File("src/main").walkTopDown().filter { it.extension == "kt" }.toList()
        assertTrue(sources.isNotEmpty())
        val text = sources.joinToString("\n") { it.readText() }
        val imports = text.lineSequence().filter { it.trimStart().startsWith("import ") }.toList()
        assertTrue(imports.none { it.contains("SecretStore") || it.contains("okhttp3") || it.contains("java.net") })
        assertTrue(!text.contains("hasDeepseekKey"))
        assertTrue(!text.contains("hasOpenaiKey"))
        assertTrue(!text.contains("hasAnthropicKey"))
        assertTrue(!text.contains("HttpURLConnection"))
        assertTrue(!text.contains("Default local-tool permission"))
        assertTrue(!text.contains("actionsAvailable = false"))
        assertTrue(text.contains("actionsAvailable"))
    }
}

private class Harness(
    val settings: FakeSettingsPort = FakeSettingsPort(),
    val store: MemorySecretStore = MemorySecretStore(),
    val writer: MemorySecretWriter = MemorySecretWriter(store),
    val proactive: FakeProactivePort = FakeProactivePort(proactiveSnapshot()),
    val clock: FakeClock = FakeClock()
) {
    val dependencies = SettingsDependencies(settings, writer, proactive, clock)
}
