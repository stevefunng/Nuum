package com.nuum.feature.settings

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import com.nuum.contracts.Language
import com.nuum.contracts.ThemePreference

internal val LocalNuumPalette = staticCompositionLocalOf { NuumPalette.Dark }
internal val LocalSettingsLanguage = staticCompositionLocalOf { Language.EN }

internal data class NuumPalette(
    val dark: Boolean,
    val modeName: String,
    val bgEditor: Color,
    val bgElevated: Color,
    val bgInput: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val textOnPrimary: Color,
    val textDanger: Color,
    val borderSubtle: Color,
    val borderDefault: Color,
    val strokeTertiary: Color,
    val fillGhostSelected: Color,
    val fillGhostHover: Color,
    val fillControlTrack: Color,
    val scrim: Color
) {
    companion object {
        val Light = NuumPalette(
            dark = false,
            modeName = "nuum-light",
            bgEditor = css("#fcfcfc"),
            bgElevated = css("#fcfcfc"),
            bgInput = css("#fcfcfc"),
            textPrimary = css("#141414"),
            textSecondary = css("#14141499"),
            textTertiary = css("#14141466"),
            textOnPrimary = css("#fcfcfc"),
            textDanger = css("#c21d2e"),
            borderSubtle = css("#1414140d"),
            borderDefault = css("#14141426"),
            strokeTertiary = css("#1414141a"),
            fillGhostSelected = css("#7777772b"),
            fillGhostHover = css("#77777717"),
            fillControlTrack = css("#1414141a"),
            scrim = css("#14141480")
        )
        val Dark = NuumPalette(
            dark = true,
            modeName = "nuum-dark",
            bgEditor = css("#070707"),
            bgElevated = css("#181818"),
            bgInput = css("#2f2f2f"),
            textPrimary = css("#fcfcfc"),
            textSecondary = css("#fcfcfc99"),
            textTertiary = css("#fcfcfc66"),
            textOnPrimary = css("#141414"),
            textDanger = css("#ff5667"),
            borderSubtle = css("#fcfcfc0d"),
            borderDefault = css("#fcfcfc26"),
            strokeTertiary = css("#fcfcfc1a"),
            fillGhostSelected = css("#77777752"),
            fillGhostHover = css("#7777772c"),
            fillControlTrack = css("#fcfcfc1a"),
            scrim = css("#141414b2")
        )
    }
}

/** CSS `#RRGGBB` or `#RRGGBBAA` → Compose color. Alpha stays the last byte. */
internal fun css(hex: String): Color {
    val raw = hex.removePrefix("#")
    val argb = when (raw.length) {
        6 -> 0xFF000000L or raw.toLong(16)
        8 -> {
            val rgb = raw.substring(0, 6).toLong(16)
            val alpha = raw.substring(6, 8).toLong(16)
            (alpha shl 24) or rgb
        }
        else -> throw IllegalArgumentException("Unsupported color $hex")
    }
    return Color(argb.toInt())
}

internal fun resolveDark(preference: ThemePreference?, systemDark: Boolean): Boolean = when (preference) {
    null, ThemePreference.DARK -> true
    ThemePreference.LIGHT -> false
    ThemePreference.SYSTEM -> systemDark
}

/**
 * Applies `nuum-light` / `nuum-dark`. A null preference is dark, matching the
 * shell before settings have loaded. `system` follows [systemDark].
 */
@Composable
fun NuumTheme(
    preference: ThemePreference?,
    systemDark: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val palette = if (resolveDark(preference, systemDark)) NuumPalette.Dark else NuumPalette.Light
    val scheme = if (palette.dark) {
        darkColorScheme(
            primary = palette.textPrimary,
            onPrimary = palette.textOnPrimary,
            background = palette.bgEditor,
            onBackground = palette.textPrimary,
            surface = palette.bgElevated,
            onSurface = palette.textPrimary
        )
    } else {
        lightColorScheme(
            primary = palette.textPrimary,
            onPrimary = palette.textOnPrimary,
            background = palette.bgEditor,
            onBackground = palette.textPrimary,
            surface = palette.bgElevated,
            onSurface = palette.textPrimary
        )
    }
    CompositionLocalProvider(LocalNuumPalette provides palette) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

/** In-app language. Null follows the system locale until settings load. */
@Composable
fun NuumLanguage(
    language: Language?,
    content: @Composable () -> Unit
) {
    CompositionLocalProvider(LocalSettingsLanguage provides displayLanguage(language), content = content)
}

@Composable
internal fun t(key: String): String = SettingsCopy.text(LocalSettingsLanguage.current, key)

@Composable
internal fun t(key: String, vars: Map<String, String>): String =
    SettingsCopy.format(LocalSettingsLanguage.current, key, vars)
