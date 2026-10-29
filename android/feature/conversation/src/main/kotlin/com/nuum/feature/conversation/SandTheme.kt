package com.nuum.feature.conversation

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

@Immutable
internal data class SandPalette(
    val bgEditor: Color,
    val bgElevated: Color,
    val bgInput: Color,
    val bgTertiary: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val textOnColor: Color,
    val textOnPrimary: Color,
    val textDanger: Color,
    val textLink: Color,
    val borderSubtle: Color,
    val borderDefault: Color,
    val borderStrong: Color,
    val borderFocus: Color,
    val borderDanger: Color,
    val fillPrimary: Color,
    val fillPrimaryHover: Color,
    val fillSecondary: Color,
    val fillGhostHover: Color,
    val fillGhostSelected: Color,
    val fillBubbleAgent: Color,
    val fillDangerSubtle: Color,
    val fillWarning: Color,
    val fillDanger: Color,
    val fillAccent: Color,
    val scrim: Color,
    val supplementary4: Color
)

private val SandDark = SandPalette(
    bgEditor = Color(0xFF070707),
    bgElevated = Color(0xFF181818),
    bgInput = Color(0xFF2F2F2F),
    bgTertiary = Color(0x2C777777),
    textPrimary = Color(0xFFFCFCFC),
    textSecondary = Color(0x99FCFCFC),
    textTertiary = Color(0x66FCFCFC),
    textOnColor = Color(0xFFFCFCFC),
    textOnPrimary = Color(0xFF141414),
    textDanger = Color(0xFFFF5667),
    textLink = Color(0xFF459FFE),
    borderSubtle = Color(0x0DFCFCFC),
    borderDefault = Color(0x26FCFCFC),
    borderStrong = Color(0x4DFCFCFC),
    borderFocus = Color(0x66FCFCFC),
    borderDanger = Color(0xFFC21D2E),
    fillPrimary = Color(0xFFFAFAFA),
    fillPrimaryHover = Color(0xFFD5D5D5),
    fillSecondary = Color(0x2C777777),
    fillGhostHover = Color(0x2C777777),
    fillGhostSelected = Color(0x52777777),
    fillBubbleAgent = Color(0xFF262626),
    fillDangerSubtle = Color(0x2CFF263C),
    fillWarning = Color(0xFFFF9800),
    fillDanger = Color(0xFFFF263C),
    fillAccent = Color(0xFF1084FE),
    scrim = Color(0xB2141414),
    supplementary4 = Color(0xFF9159FE)
)

private val SandLight = SandPalette(
    bgEditor = Color(0xFFFCFCFC),
    bgElevated = Color(0xFFFCFCFC),
    bgInput = Color(0xFFFCFCFC),
    bgTertiary = Color(0x17777777),
    textPrimary = Color(0xFF141414),
    textSecondary = Color(0x99141414),
    textTertiary = Color(0x66141414),
    textOnColor = Color(0xFFFCFCFC),
    textOnPrimary = Color(0xFFFCFCFC),
    textDanger = Color(0xFFC21D2E),
    textLink = Color(0xFF0C64C1),
    borderSubtle = Color(0x0D141414),
    borderDefault = Color(0x26141414),
    borderStrong = Color(0x4D141414),
    borderFocus = Color(0x66141414),
    borderDanger = Color(0xFFFF5667),
    fillPrimary = Color(0xFF070707),
    fillPrimaryHover = Color(0xFF2F2F2F),
    fillSecondary = Color(0x17777777),
    fillGhostHover = Color(0x17777777),
    fillGhostSelected = Color(0x2B777777),
    fillBubbleAgent = Color(0xFFEEEEEE),
    fillDangerSubtle = Color(0x17FF263C),
    fillWarning = Color(0xFFFF9800),
    fillDanger = Color(0xFFFF263C),
    fillAccent = Color(0xFF1084FE),
    scrim = Color(0x80141414),
    supplementary4 = Color(0xFF9159FE)
)

private val LocalSand = staticCompositionLocalOf { SandDark }

internal object Sand {
    val bgEditor: Color @Composable get() = LocalSand.current.bgEditor
    val bgElevated: Color @Composable get() = LocalSand.current.bgElevated
    val bgInput: Color @Composable get() = LocalSand.current.bgInput
    val bgTertiary: Color @Composable get() = LocalSand.current.bgTertiary
    val textPrimary: Color @Composable get() = LocalSand.current.textPrimary
    val textSecondary: Color @Composable get() = LocalSand.current.textSecondary
    val textTertiary: Color @Composable get() = LocalSand.current.textTertiary
    val textOnColor: Color @Composable get() = LocalSand.current.textOnColor
    val textOnPrimary: Color @Composable get() = LocalSand.current.textOnPrimary
    val textDanger: Color @Composable get() = LocalSand.current.textDanger
    val textLink: Color @Composable get() = LocalSand.current.textLink
    val borderSubtle: Color @Composable get() = LocalSand.current.borderSubtle
    val borderDefault: Color @Composable get() = LocalSand.current.borderDefault
    val borderStrong: Color @Composable get() = LocalSand.current.borderStrong
    val borderFocus: Color @Composable get() = LocalSand.current.borderFocus
    val borderDanger: Color @Composable get() = LocalSand.current.borderDanger
    val fillPrimary: Color @Composable get() = LocalSand.current.fillPrimary
    val fillPrimaryHover: Color @Composable get() = LocalSand.current.fillPrimaryHover
    val fillSecondary: Color @Composable get() = LocalSand.current.fillSecondary
    val fillGhostHover: Color @Composable get() = LocalSand.current.fillGhostHover
    val fillGhostSelected: Color @Composable get() = LocalSand.current.fillGhostSelected
    val fillBubbleAgent: Color @Composable get() = LocalSand.current.fillBubbleAgent
    val fillDangerSubtle: Color @Composable get() = LocalSand.current.fillDangerSubtle
    val fillWarning: Color @Composable get() = LocalSand.current.fillWarning
    val fillDanger: Color @Composable get() = LocalSand.current.fillDanger
    val fillAccent: Color @Composable get() = LocalSand.current.fillAccent
    val scrim: Color @Composable get() = LocalSand.current.scrim
    val supplementary4: Color @Composable get() = LocalSand.current.supplementary4
}

@Composable
internal fun ConversationTheme(dark: Boolean = true, content: @Composable () -> Unit) {
    val sand = if (dark) SandDark else SandLight
    CompositionLocalProvider(LocalSand provides sand) {
        MaterialTheme(
            colorScheme = if (dark) {
                darkColorScheme(
                    background = sand.bgEditor,
                    surface = sand.bgElevated,
                    primary = sand.fillPrimary,
                    onPrimary = sand.textOnPrimary,
                    error = sand.textDanger
                )
            } else {
                lightColorScheme(
                    background = sand.bgEditor,
                    surface = sand.bgElevated,
                    primary = sand.fillPrimary,
                    onPrimary = sand.textOnPrimary,
                    error = sand.textDanger
                )
            },
            content = content
        )
    }
}
