package com.nuum.feature.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.activity.compose.LocalOnBackPressedDispatcherOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nuum.contracts.Language
import com.nuum.contracts.ProviderId
import com.nuum.contracts.ThemePreference

/**
 * General and Models. API key fields start empty and are written through
 * [com.nuum.contracts.SecretWriter] on blur. They are never filled from storage.
 * Global tool permission and the profile execution form are not on this screen.
 */
@Composable
fun SettingsScreen(
    dependencies: SettingsDependencies,
    onClose: () -> Unit,
    onOpenProactive: () -> Unit,
    modifier: Modifier = Modifier,
    systemDark: Boolean = androidx.compose.foundation.isSystemInDarkTheme()
) {
    val viewModel: SettingsViewModel = viewModel(
        factory = SettingsViewModel.factory(dependencies.settings, dependencies.secrets)
    )
    val state by viewModel.state.collectAsState()
    if (LocalOnBackPressedDispatcherOwner.current != null) {
        BackHandler(onBack = onClose)
    }
    NuumTheme(preference = state.theme, systemDark = systemDark) {
        NuumLanguage(language = state.language) {
            SettingsScaffold(
                state = state,
                onClose = onClose,
                onOpenProactive = onOpenProactive,
                onLanguage = viewModel::onLanguageSelected,
                onTheme = viewModel::onThemeSelected,
                onProvider = viewModel::onProviderSelected,
                onDeepSeekModel = viewModel::onDeepSeekModelSelected,
                onApiKeyBlur = viewModel::onApiKeyBlur,
                modifier = modifier
            )
        }
    }
}

@Composable
private fun SettingsScaffold(
    state: SettingsUiState,
    onClose: () -> Unit,
    onOpenProactive: () -> Unit,
    onLanguage: (Language) -> Unit,
    onTheme: (ThemePreference) -> Unit,
    onProvider: (ProviderId) -> Unit,
    onDeepSeekModel: (String) -> Unit,
    onApiKeyBlur: (ProviderId, String) -> Unit,
    modifier: Modifier = Modifier
) {
    val palette = LocalNuumPalette.current
    var section by remember { mutableStateOf(SettingsSection.General) }
    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .testTag(palette.modeName)
            .semantics { stateDescription = if (state.loaded) "loaded" else "loading" }
    ) {
        val windowWidth = maxWidth
        val windowHeight = maxHeight
        val fullscreen = windowWidth < 840.dp
        val sideNav = windowWidth >= 900.dp
        Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
            if (!fullscreen) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(palette.scrim)
                        .clickable(onClick = onClose)
                )
            }
            val panelModifier = when {
                fullscreen -> Modifier.fillMaxSize().background(palette.bgEditor)
                sideNav -> Modifier
                    .align(Alignment.Center)
                    .width(minOf(860.dp, windowWidth - 32.dp))
                    .heightIn(max = windowHeight * 0.9f)
                    .background(palette.bgElevated, RoundedCornerShape(14.dp))
                    .border(1.dp, palette.borderDefault, RoundedCornerShape(14.dp))
                else -> Modifier
                    .align(Alignment.Center)
                    .width(windowWidth - 32.dp)
                    .height(windowHeight - 32.dp)
                    .background(palette.bgElevated, RoundedCornerShape(14.dp))
                    .border(1.dp, palette.borderDefault, RoundedCornerShape(14.dp))
            }
            if (sideNav) {
                Row(panelModifier) {
                    SettingsSideNav(section = section, onSection = { section = it })
                    Column(Modifier.weight(1f).fillMaxHeight()) {
                        SettingsHeader(section = section, onClose = onClose)
                        SettingsBody(
                            state = state,
                            section = section,
                            compact = false,
                            onOpenProactive = onOpenProactive,
                            onLanguage = onLanguage,
                            onTheme = onTheme,
                            onProvider = onProvider,
                            onDeepSeekModel = onDeepSeekModel,
                            onApiKeyBlur = onApiKeyBlur,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            } else {
                Column(panelModifier) {
                    SettingsHeader(section = section, onClose = onClose)
                    SettingsTopNav(section = section, onSection = { section = it })
                    SettingsBody(
                        state = state,
                        section = section,
                        compact = fullscreen,
                        onOpenProactive = onOpenProactive,
                        onLanguage = onLanguage,
                        onTheme = onTheme,
                        onProvider = onProvider,
                        onDeepSeekModel = onDeepSeekModel,
                        onApiKeyBlur = onApiKeyBlur,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun SettingsHeader(section: SettingsSection, onClose: () -> Unit) {
    val palette = LocalNuumPalette.current
    val title = t(if (section == SettingsSection.General) "General" else "Models")
    val close = t("Close")
    Box(Modifier.fillMaxWidth()) {
        SectionTitle(title, Modifier.padding(end = 48.dp))
        Box(
            Modifier
                .align(Alignment.CenterEnd)
                .padding(end = 8.dp)
                .heightIn(min = 48.dp)
                .clickable(onClick = onClose)
                .padding(12.dp)
                .testTag("close-settings")
                .semantics { contentDescription = close }
        ) {
            SettingsIcon("close", palette.textSecondary)
        }
        Box(
            Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .height(1.dp)
                .background(palette.borderSubtle)
        )
    }
}

@Composable
private fun SettingsSideNav(section: SettingsSection, onSection: (SettingsSection) -> Unit) {
    val palette = LocalNuumPalette.current
    val sections = t("Settings sections")
    Column(
        Modifier
            .width(190.dp)
            .fillMaxHeight()
            .background(palette.textPrimary.copy(alpha = 0.02f))
            .padding(start = 10.dp, end = 10.dp, top = 54.dp, bottom = 12.dp)
            .semantics { contentDescription = sections }
            .testTag("settings-sections"),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        NavItems(section, wide = true, onSection = onSection)
    }
}

@Composable
private fun SettingsTopNav(section: SettingsSection, onSection: (SettingsSection) -> Unit) {
    val sections = t("Settings sections")
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .semantics { contentDescription = sections }
            .testTag("settings-sections"),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        NavItems(section, wide = false, onSection = onSection)
    }
}

@Composable
private fun NavItems(
    section: SettingsSection,
    wide: Boolean,
    onSection: (SettingsSection) -> Unit
) {
    SettingsNavButton(
        label = t("General"),
        icon = "settings-gear",
        selected = section == SettingsSection.General,
        wide = wide,
        onClick = { onSection(SettingsSection.General) },
        modifier = Modifier.testTag("section-general")
    )
    SettingsNavButton(
        label = t("Models"),
        icon = "sliders",
        selected = section == SettingsSection.Models,
        wide = wide,
        onClick = { onSection(SettingsSection.Models) },
        modifier = Modifier.testTag("section-models")
    )
}

@Composable
private fun SettingsBody(
    state: SettingsUiState,
    section: SettingsSection,
    compact: Boolean,
    onOpenProactive: () -> Unit,
    onLanguage: (Language) -> Unit,
    onTheme: (ThemePreference) -> Unit,
    onProvider: (ProviderId) -> Unit,
    onDeepSeekModel: (String) -> Unit,
    onApiKeyBlur: (ProviderId, String) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp)
    ) {
        state.loadError?.let { message ->
            Text(
                text = message,
                color = LocalNuumPalette.current.textDanger,
                fontSize = 12.sp,
                modifier = Modifier.semantics { contentDescription = message }
            )
        }
        if (section == SettingsSection.General) {
            GeneralSection(state, compact, onLanguage, onTheme, onOpenProactive)
        } else {
            ModelsSection(state, compact, onProvider, onDeepSeekModel, onApiKeyBlur)
        }
    }
}

@Composable
private fun GeneralSection(
    state: SettingsUiState,
    compact: Boolean,
    onLanguage: (Language) -> Unit,
    onTheme: (ThemePreference) -> Unit,
    onOpenProactive: () -> Unit
) {
    SettingsGroup(title = t("Appearance")) {
        SettingsRow(
            title = t("Language"),
            description = t("Choose the language used throughout Nuum."),
            alert = if (state.languageFailed) t("Could not change language. Please try again.") else null,
            compact = compact
        ) {
            SettingsSelect(
                label = t("Language"),
                valueLabel = state.language?.let(::languageLabel).orEmpty(),
                enabled = state.loaded && !state.languageBusy,
                options = listOf(Language.ZH_CN.wire to "中文", Language.EN.wire to "English"),
                selectedValue = state.language?.wire,
                onSelect = { wire ->
                    onLanguage(if (wire == Language.EN.wire) Language.EN else Language.ZH_CN)
                },
                testTag = "language-select"
            )
        }
        RowDivider()
        SettingsRow(
            title = t("Theme"),
            description = t("Keep the current dark shell, or switch to the light palette."),
            alert = state.themeError,
            compact = compact
        ) {
            SettingsSelect(
                label = t("Theme"),
                valueLabel = state.theme?.let { t(themeKey(it)) }.orEmpty(),
                enabled = state.loaded,
                options = listOf(
                    ThemePreference.SYSTEM.wire to t("Follow system"),
                    ThemePreference.LIGHT.wire to t("Light"),
                    ThemePreference.DARK.wire to t("Dark")
                ),
                selectedValue = state.theme?.wire,
                onSelect = { wire ->
                    val theme = ThemePreference.entries.first { it.wire == wire }
                    onTheme(theme)
                },
                testTag = "theme-select"
            )
        }
    }
    SettingsGroup(title = t("Proactive mode")) {
        SettingsRow(
            title = "Nunu",
            description = t("Manage your proactive companion from the menu bar."),
            alert = null,
            compact = compact
        ) {
            val label = t("Open menu bar panel")
            Text(
                text = label,
                color = LocalNuumPalette.current.textPrimary,
                fontSize = 13.sp,
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.Medium,
                modifier = Modifier
                    .testTag("open-proactive")
                    .heightIn(min = 48.dp)
                    .clickable(onClick = onOpenProactive)
                    .padding(horizontal = 9.dp, vertical = 8.dp)
                    .semantics { contentDescription = label }
            )
        }
    }
}

@Composable
private fun ModelsSection(
    state: SettingsUiState,
    compact: Boolean,
    onProvider: (ProviderId) -> Unit,
    onDeepSeekModel: (String) -> Unit,
    onApiKeyBlur: (ProviderId, String) -> Unit
) {
    SettingsGroup(title = t("Model preferences")) {
        SettingsRow(
            title = t("Default provider"),
            description = t("Used for new chats until you change the session model."),
            alert = state.providerError,
            compact = compact
        ) {
            SettingsSelect(
                label = t("Default provider"),
                valueLabel = state.provider?.let(::providerLabel).orEmpty(),
                enabled = state.loaded,
                options = listOf(ProviderId.DEEPSEEK, ProviderId.OPENAI, ProviderId.ANTHROPIC)
                    .map { it.wire to providerLabel(it) },
                selectedValue = state.provider?.wire,
                onSelect = { wire -> onProvider(ProviderId.entries.first { it.wire == wire }) },
                testTag = "provider-select"
            )
        }
        if (state.provider == ProviderId.DEEPSEEK) {
            RowDivider()
            SettingsRow(
                title = t("DeepSeek model"),
                description = t("deepseek-chat for everyday use. deepseek-reasoner for longer reasoning."),
                alert = state.deepSeekModelError,
                compact = compact
            ) {
                SettingsSelect(
                    label = t("DeepSeek model"),
                    valueLabel = state.modelId.orEmpty(),
                    enabled = state.loaded,
                    options = DEEPSEEK_MODEL_IDS.map { it to it },
                    selectedValue = state.modelId,
                    onSelect = onDeepSeekModel,
                    testTag = "deepseek-model-select"
                )
            }
        }
    }
    SettingsGroup(title = t("API keys")) {
        KeyRow(ProviderId.DEEPSEEK, "DeepSeek API key", "Stored in the OS keychain and injected into Host memory only.", state, compact, onApiKeyBlur)
        RowDivider()
        KeyRow(ProviderId.OPENAI, "OpenAI API key", "Optional. Used when the default provider is OpenAI.", state, compact, onApiKeyBlur)
        RowDivider()
        KeyRow(ProviderId.ANTHROPIC, "Anthropic API key", "Optional. Used when the default provider is Anthropic.", state, compact, onApiKeyBlur)
    }
}

@Composable
private fun KeyRow(
    provider: ProviderId,
    titleKey: String,
    descriptionKey: String,
    state: SettingsUiState,
    compact: Boolean,
    onApiKeyBlur: (ProviderId, String) -> Unit
) {
    SettingsRow(
        title = t(titleKey),
        description = t(descriptionKey),
        alert = state.keyErrors[provider],
        compact = compact
    ) {
        ApiKeyField(
            label = t(titleKey),
            error = state.keyErrors[provider],
            compact = compact,
            testTag = "api-key-${provider.wire}",
            onBlur = { onApiKeyBlur(provider, it) }
        )
    }
}

@Composable
private fun RowDivider() {
    Box(
        Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(LocalNuumPalette.current.borderSubtle)
    )
}

private fun languageLabel(language: Language): String = when (language) {
    Language.ZH_CN -> "中文"
    Language.EN -> "English"
}

private fun themeKey(theme: ThemePreference): String = when (theme) {
    ThemePreference.SYSTEM -> "Follow system"
    ThemePreference.LIGHT -> "Light"
    ThemePreference.DARK -> "Dark"
}

internal fun providerLabel(provider: ProviderId): String = when (provider) {
    ProviderId.DEEPSEEK -> "DeepSeek"
    ProviderId.OPENAI -> "OpenAI"
    ProviderId.ANTHROPIC -> "Anthropic"
}
