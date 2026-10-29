package com.nuum.feature.shell.theme

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.nuum.contracts.Language
import com.nuum.contracts.ThemePreference
import com.nuum.feature.shell.i18n.Copy

internal data class SandPalette(
    val dark: Boolean,
    val bgChrome: Color,
    val bgEditor: Color,
    val bgElevated: Color,
    val bgInput: Color,
    val bgSecondary: Color,
    val fillSecondary: Color,
    val fillSelected: Color,
    val fillPrimary: Color,
    val textOnPrimary: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val textDanger: Color,
    val textOnColor: Color,
    val borderSubtle: Color,
    val borderDefault: Color,
    val borderFocus: Color,
    val fillAccent: Color,
    val scrim: Color,
    val supplementary4: Color,
    val badgeInk: Color = Color(0xFF171F24),
    val badgePaperTop: Color = Color(0xFFFAFBF9),
    val badgePaperBottom: Color = Color(0xFFE9ECE9)
)

internal val LocalSand = staticCompositionLocalOf { darkPalette() }
internal val LocalCopy = staticCompositionLocalOf { Copy(Language.ZH_CN) }

internal fun darkPalette() = SandPalette(
    dark = true,
    bgChrome = css("#111111"),
    bgEditor = css("#070707"),
    bgElevated = css("#181818"),
    bgInput = css("#2f2f2f"),
    bgSecondary = css("#77777752"),
    fillSecondary = css("#7777772c"),
    fillSelected = css("#77777752"),
    fillPrimary = css("#fafafa"),
    textOnPrimary = css("#141414"),
    textPrimary = css("#fcfcfc"),
    textSecondary = css("#fcfcfc99"),
    textTertiary = css("#fcfcfc66"),
    textDanger = css("#ff5667"),
    textOnColor = css("#fcfcfc"),
    borderSubtle = css("#fcfcfc0d"),
    borderDefault = css("#fcfcfc26"),
    borderFocus = css("#fcfcfc66"),
    fillAccent = css("#1084fe"),
    scrim = css("#141414b2"),
    supplementary4 = css("#9159fe")
)

internal fun lightPalette() = SandPalette(
    dark = false,
    bgChrome = css("#f7f7f7"),
    bgEditor = css("#fcfcfc"),
    bgElevated = css("#fcfcfc"),
    bgInput = css("#fcfcfc"),
    bgSecondary = css("#7777772b"),
    fillSecondary = css("#77777717"),
    fillSelected = css("#7777772b"),
    fillPrimary = css("#070707"),
    textOnPrimary = css("#fcfcfc"),
    textPrimary = css("#141414"),
    textSecondary = css("#14141499"),
    textTertiary = css("#14141466"),
    textDanger = css("#c21d2e"),
    textOnColor = css("#fcfcfc"),
    borderSubtle = css("#1414140d"),
    borderDefault = css("#14141426"),
    borderFocus = css("#14141466"),
    fillAccent = css("#1084fe"),
    scrim = css("#14141480"),
    supplementary4 = css("#9159fe")
)

/** CSS `#RRGGBB` / `#RRGGBBAA` → Compose `#AARRGGBB`. Values are unchanged. */
internal fun css(hex: String): Color {
    val raw = hex.removePrefix("#")
    val argb = when (raw.length) {
        6 -> raw.toLong(16) or 0xFF000000L
        8 -> {
            val rgb = raw.substring(0, 6).toLong(16)
            val alpha = raw.substring(6, 8).toLong(16)
            (alpha shl 24) or rgb
        }
        else -> error("Bad color $hex")
    }
    return Color(argb)
}

@Composable
internal fun resolvedDark(theme: ThemePreference?): Boolean = when (theme) {
    ThemePreference.LIGHT -> false
    ThemePreference.SYSTEM -> isSystemInDarkTheme()
    ThemePreference.DARK, null -> true
}

@Composable
internal fun SandTheme(
    theme: ThemePreference?,
    language: Language,
    content: @Composable () -> Unit
) {
    val dark = resolvedDark(theme)
    val palette = if (dark) darkPalette() else lightPalette()
    val scheme = if (dark) {
        darkColorScheme(
            primary = palette.fillPrimary,
            onPrimary = palette.textOnPrimary,
            background = palette.bgEditor,
            surface = palette.bgElevated,
            onBackground = palette.textPrimary,
            onSurface = palette.textPrimary
        )
    } else {
        lightColorScheme(
            primary = palette.fillPrimary,
            onPrimary = palette.textOnPrimary,
            background = palette.bgEditor,
            surface = palette.bgElevated,
            onBackground = palette.textPrimary,
            onSurface = palette.textPrimary
        )
    }
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = view.context.findActivity()?.window ?: return@SideEffect
            val argb = palette.bgChrome.toArgb()
            window.statusBarColor = argb
            window.navigationBarColor = argb
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
        }
    }
    CompositionLocalProvider(LocalSand provides palette, LocalCopy provides Copy(language)) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

private fun Context.findActivity(): Activity? {
    var current: Context? = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return null
}
