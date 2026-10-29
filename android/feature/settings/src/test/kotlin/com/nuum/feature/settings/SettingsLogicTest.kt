package com.nuum.feature.settings

import com.nuum.contracts.DEFAULT_MODEL_ID
import com.nuum.contracts.DesktopErrorCode
import com.nuum.contracts.Language
import com.nuum.contracts.NuumException
import com.nuum.contracts.ProviderId
import com.nuum.contracts.Secrets
import com.nuum.contracts.ThemePreference
import com.nuum.contracts.ToolPermission
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsLogicTest {
    private val scopes = mutableListOf<CoroutineScope>()

    @After
    fun cancelScopes() {
        scopes.forEach { it.cancel() }
    }

    @Test
    fun saveAndLoadApiKeyThroughSecretStore() {
        val store = MemorySecretStore()
        val writer = MemorySecretWriter(store)
        val viewModel = settingsViewModel(secrets = writer, store = store)
        viewModel.onApiKeyBlur(ProviderId.DEEPSEEK, "sk-test-deepseek")
        assertEquals(0, store.readCount)
        val loaded = store.load()
        assertEquals("sk-test-deepseek", loaded.deepseekApiKey)
        assertNull(loaded.openaiApiKey)
        assertEquals(ProviderId.DEEPSEEK to "sk-test-deepseek", writer.writes.single())
        assertFalse(viewModel.state.value.toString().contains("sk-test-deepseek"))
    }

    @Test
    fun clearApiKeyRemovesItFromSecretStore() {
        val store = MemorySecretStore()
        val writer = MemorySecretWriter(store)
        val viewModel = settingsViewModel(secrets = writer, store = store)
        viewModel.onApiKeyBlur(ProviderId.OPENAI, "sk-test-openai")
        viewModel.onApiKeyBlur(ProviderId.OPENAI, "")
        assertNull(store.load().openaiApiKey)
        assertEquals("", writer.writes.last().second)
        assertEquals(ProviderId.OPENAI, writer.writes.last().first)
    }

    @Test
    fun switchingProviderUsesDefaultModelId() {
        val settings = FakeSettingsPort()
        val viewModel = settingsViewModel(settings)
        viewModel.onProviderSelected(ProviderId.OPENAI)
        assertEquals(DEFAULT_MODEL_ID.getValue(ProviderId.OPENAI), settings.current.defaultModel.model)
        assertEquals(ProviderId.OPENAI, settings.current.defaultModel.provider)
        viewModel.onProviderSelected(ProviderId.ANTHROPIC)
        assertEquals(DEFAULT_MODEL_ID.getValue(ProviderId.ANTHROPIC), settings.current.defaultModel.model)
        viewModel.onProviderSelected(ProviderId.DEEPSEEK)
        assertEquals(DEFAULT_MODEL_ID.getValue(ProviderId.DEEPSEEK), settings.current.defaultModel.model)
        assertEquals(DEEPSEEK_CHAT, viewModel.state.value.modelId)
    }

    @Test
    fun deepSeekModelChoiceDoesNotResetToTheDefault() {
        val settings = FakeSettingsPort(sampleSettings(model = com.nuum.contracts.ModelRef(ProviderId.DEEPSEEK, DEEPSEEK_CHAT)))
        val viewModel = settingsViewModel(settings)
        viewModel.onDeepSeekModelSelected(DEEPSEEK_REASONER)
        assertEquals(DEEPSEEK_REASONER, settings.current.defaultModel.model)
        assertEquals(ProviderId.DEEPSEEK, settings.current.defaultModel.provider)
    }

    @Test
    fun standingToolPermissionPersistsAcrossSettingsEdits() {
        val settings = FakeSettingsPort(sampleSettings(permission = ToolPermission.ALWAYS))
        val viewModel = settingsViewModel(settings)
        viewModel.onThemeSelected(ThemePreference.LIGHT)
        viewModel.onLanguageSelected(Language.ZH_CN)
        viewModel.onProviderSelected(ProviderId.OPENAI)
        assertEquals(ToolPermission.ALWAYS, settings.current.defaultToolPermission)
        assertTrue(settings.patches.all { it.defaultToolPermission == null })
        assertEquals(ThemePreference.LIGHT, viewModel.state.value.theme)
        assertEquals(Language.ZH_CN, viewModel.state.value.language)
    }

    @Test
    fun languageFailureUsesTheFixedMessageFlagAndThemeFailureKeepsTheMessage() {
        val settings = FakeSettingsPort()
        settings.failLanguage = true
        settings.themeFailure = "theme disk full"
        val viewModel = settingsViewModel(settings)
        viewModel.onLanguageSelected(Language.ZH_CN)
        assertTrue(viewModel.state.value.languageFailed)
        assertEquals(Language.EN, viewModel.state.value.language)
        viewModel.onThemeSelected(ThemePreference.LIGHT)
        assertEquals("theme disk full", viewModel.state.value.themeError)
        assertEquals(ThemePreference.DARK, settings.current.theme)
    }

    @Test
    fun languageControlStaysBusyWhileTheSaveIsHeld() {
        val settings = FakeSettingsPort()
        settings.holdLanguage = true
        val viewModel = settingsViewModel(settings)
        viewModel.onLanguageSelected(Language.ZH_CN)
        assertTrue(viewModel.state.value.languageBusy)
        assertEquals(Language.EN, viewModel.state.value.language)
    }

    @Test
    fun keyStoreFailureKeepsTheMessageWithoutTheKey() {
        val store = MemorySecretStore()
        val writer = MemorySecretWriter(store)
        writer.failure = NuumException(DesktopErrorCode.SECRET_STORE, "keystore rejected sk-test-deepseek")
        val viewModel = settingsViewModel(secrets = writer, store = store)
        viewModel.onApiKeyBlur(ProviderId.DEEPSEEK, "sk-test-deepseek")
        val message = viewModel.state.value.keyErrors.getValue(ProviderId.DEEPSEEK)
        assertFalse(message.contains("sk-test-deepseek"))
        assertTrue(message.contains("keystore rejected"))
        assertNull(store.peek().deepseekApiKey)
    }

    @Test
    fun openingDoesNotWriteOrReadAKey() {
        val store = MemorySecretStore()
        kotlinx.coroutines.runBlocking {
            store.write(Secrets(deepseekApiKey = "sk-stored-not-in-ui"))
        }
        val writer = MemorySecretWriter(store)
        settingsViewModel(secrets = writer, store = store)
        assertTrue(writer.writes.isEmpty())
        assertEquals(0, store.readCount)
        assertEquals("sk-stored-not-in-ui", store.peek().deepseekApiKey)
    }

    @Test
    fun proactiveTogglePauseAndCheckSendSnapshotFields() {
        val clock = FakeClock(now = 5_000L)
        val proactive = FakeProactivePort(
            proactiveSnapshot(agent = proactiveAgent(enabled = true, state = "waiting-context", revision = 7))
        )
        val viewModel = proactiveViewModel(proactive, clock)
        viewModel.onPause(PAUSE_30_MINUTES_MS)
        val paused = proactive.configures.single()
        assertEquals("agent-1", paused.agentId)
        assertEquals(7, paused.expectedRevision)
        assertEquals(5_000L + PAUSE_30_MINUTES_MS, paused.pausedUntil)
        assertEquals("paused", viewModel.state.value.snapshot?.agents?.single()?.state)

        viewModel.onResume()
        val resumed = proactive.configures.last()
        assertEquals(true, resumed.resume)
        assertNull(resumed.pausedUntil)
        assertEquals("agent-1", resumed.agentId)

        viewModel.onCheck()
        assertEquals(listOf("agent-1"), proactive.checks)
    }

    @Test
    fun failedConfigureDoesNotMoveTheSwitchAndRetryRepeatsTheCall() {
        val proactive = FakeProactivePort(
            proactiveSnapshot(agent = proactiveAgent(enabled = false, state = "disabled", revision = 2))
        )
        proactive.failConfigure = true
        val viewModel = proactiveViewModel(proactive)
        viewModel.onToggle()
        assertEquals(false, viewModel.state.value.snapshot?.agents?.single()?.policy?.enabled)
        assertTrue(viewModel.state.value.failed)
        val first = proactive.configures.single()
        assertEquals(true, first.enabled)
        assertEquals(true, first.resume)
        assertEquals(2, first.expectedRevision)
        proactive.failConfigure = false
        viewModel.onRetry()
        assertEquals(2, proactive.configures.size)
        assertEquals(first, proactive.configures.last())
        assertEquals(true, viewModel.state.value.snapshot?.agents?.single()?.policy?.enabled)
        assertFalse(viewModel.state.value.failed)
    }

    @Test
    fun agentActionsLabelComesFromTheSnapshotFlag() {
        assertEquals(ConnectionLabel.NotConnected, agentActionsLabel(false))
        assertEquals(ConnectionLabel.Available, agentActionsLabel(true))
        assertEquals(ConnectionLabel.NotConnected, contextSourcesLabel(emptyList()))
        assertEquals(ConnectionLabel.Available, contextSourcesLabel(listOf("calendar")))
    }

    private fun settingsViewModel(
        settings: FakeSettingsPort = FakeSettingsPort(),
        secrets: MemorySecretWriter? = null,
        store: MemorySecretStore = MemorySecretStore()
    ): SettingsViewModel {
        val writer = secrets ?: MemorySecretWriter(store)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        scopes += scope
        return SettingsViewModel(settings, writer, scope)
    }

    private fun proactiveViewModel(
        proactive: FakeProactivePort,
        clock: FakeClock = FakeClock()
    ): ProactiveViewModel {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        scopes += scope
        return ProactiveViewModel(FakeSettingsPort(), proactive, clock, scope)
    }
}
