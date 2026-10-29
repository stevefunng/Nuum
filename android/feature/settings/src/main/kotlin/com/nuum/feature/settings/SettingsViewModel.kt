package com.nuum.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.nuum.contracts.DEFAULT_MODEL_ID
import com.nuum.contracts.HostEvent
import com.nuum.contracts.Language
import com.nuum.contracts.ModelRef
import com.nuum.contracts.ProviderId
import com.nuum.contracts.PublicSettings
import com.nuum.contracts.SecretWriter
import com.nuum.contracts.SettingsPatch
import com.nuum.contracts.SettingsPort
import com.nuum.contracts.ThemePreference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

internal const val DEEPSEEK_CHAT = "deepseek-chat"
internal const val DEEPSEEK_REASONER = "deepseek-reasoner"
internal val DEEPSEEK_MODEL_IDS = listOf(DEEPSEEK_CHAT, DEEPSEEK_REASONER)

internal data class SettingsUiState(
    val loaded: Boolean = false,
    val loadError: String? = null,
    val language: Language? = null,
    val theme: ThemePreference? = null,
    val provider: ProviderId? = null,
    val modelId: String? = null,
    val languageBusy: Boolean = false,
    val languageFailed: Boolean = false,
    val themeError: String? = null,
    val providerError: String? = null,
    val deepSeekModelError: String? = null,
    val keyErrors: Map<ProviderId, String> = emptyMap()
)

/**
 * Settings edits against [SettingsPort] and [SecretWriter]. Key characters stay
 * in the composable that the user is typing into. This state never holds them
 * and never reads a stored key back.
 */
internal class SettingsViewModel(
    private val settings: SettingsPort,
    private val secrets: SecretWriter,
    scope: CoroutineScope? = null
) : ViewModel() {
    private val work = scope ?: viewModelScope
    private val _state = MutableStateFlow(SettingsUiState())
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    init {
        work.launch {
            settings.events.collect { event ->
                if (event is HostEvent.SettingsUpdated) apply(event.settings)
            }
        }
        refresh()
    }

    fun refresh() {
        work.launch {
            try {
                apply(settings.get())
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.update { it.copy(loaded = false, loadError = error.message.orEmpty()) }
            }
        }
    }

    fun onLanguageSelected(language: Language) {
        val current = _state.value
        if (!current.loaded || current.languageBusy || current.language == language) return
        work.launch {
            _state.update { it.copy(languageBusy = true, languageFailed = false) }
            try {
                apply(settings.set(SettingsPatch(language = language)))
                _state.update { it.copy(languageBusy = false, languageFailed = false) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                _state.update { it.copy(languageBusy = false, languageFailed = true) }
            }
        }
    }

    fun onThemeSelected(theme: ThemePreference) {
        val current = _state.value
        if (!current.loaded || current.theme == theme) return
        work.launch {
            try {
                apply(settings.set(SettingsPatch(theme = theme)))
                _state.update { it.copy(themeError = null) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.update { it.copy(themeError = error.message.orEmpty()) }
            }
        }
    }

    fun onProviderSelected(provider: ProviderId) {
        val current = _state.value
        if (!current.loaded || current.provider == provider) return
        saveModel(ModelRef(provider, DEFAULT_MODEL_ID.getValue(provider)), deepSeekRow = false)
    }

    fun onDeepSeekModelSelected(modelId: String) {
        val current = _state.value
        if (!current.loaded || current.provider != ProviderId.DEEPSEEK || current.modelId == modelId) return
        saveModel(ModelRef(ProviderId.DEEPSEEK, modelId), deepSeekRow = true)
    }

    /**
     * Blur of a key field. An empty string deletes that provider's key.
     * The field is not filled from storage, so a blur only happens after focus.
     */
    fun onApiKeyBlur(provider: ProviderId, value: String) {
        work.launch {
            try {
                secrets.write(provider, if (value.isEmpty()) "" else value)
                _state.update { it.copy(keyErrors = it.keyErrors - provider) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                val message = redactSecret(error.message.orEmpty(), value)
                _state.update { it.copy(keyErrors = it.keyErrors + (provider to message)) }
            }
        }
    }

    private fun saveModel(model: ModelRef, deepSeekRow: Boolean) {
        work.launch {
            try {
                apply(settings.set(SettingsPatch(defaultModel = model)))
                _state.update {
                    if (deepSeekRow) it.copy(deepSeekModelError = null) else it.copy(providerError = null)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                val message = error.message.orEmpty()
                _state.update {
                    if (deepSeekRow) it.copy(deepSeekModelError = message) else it.copy(providerError = message)
                }
            }
        }
    }

    private fun apply(settings: PublicSettings) {
        _state.update {
            it.copy(
                loaded = true,
                loadError = null,
                language = settings.language,
                theme = settings.theme,
                provider = settings.defaultModel.provider,
                modelId = settings.defaultModel.model
            )
        }
    }

    companion object {
        fun factory(settings: SettingsPort, secrets: SecretWriter): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T =
                    SettingsViewModel(settings, secrets) as T
            }
    }
}
