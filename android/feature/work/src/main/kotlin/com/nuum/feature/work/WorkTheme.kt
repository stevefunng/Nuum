package com.nuum.feature.work

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Text

/**
 * Dark sand tokens. This module does not read settings; the shell supplies the
 * resolved theme later. Until then the Mac default is dark.
 */
internal object WorkColors {
    val bgEditor = Color(0xFF070707)
    val bgElevated = Color(0xFF181818)
    val bgInput = Color(0xFF2F2F2F)
    val textPrimary = Color(0xFFFCFCFC)
    val textSecondary = Color(0x99FCFCFC)
    val textTertiary = Color(0x66FCFCFC)
    val textOnColor = Color(0xFFFCFCFC)
    val textOnPrimary = Color(0xFF141414)
    val textWarning = Color(0xFFFFAF38)
    val textDanger = Color(0xFFFF5667)
    val fillPrimary = Color(0xFFFAFAFA)
    val fillSecondary = Color(0x2C777777)
    val fillDangerSubtle = Color(0x2CFF263C)
    val fillBubbleUser = Color(0xFF5A5A5A)
    val borderSubtle = Color(0x0DFCFCFC)
    val edge = Color(0x17FCFCFC)
    val blue = Color(0xFF459FFE)
    val orange = Color(0xFFFF8838)
    val green = Color(0xFF38D591)
    val magenta = Color(0xFFFF5EB1)
    val scrim = Color(0xB2141414)
    val warningFill = Color(0xFFFF9800)
    val accentFill = Color(0xFF1084FE)
    val dangerFill = Color(0xFFFF263C)
}

internal fun avatarColor(id: String?): Color = when (id) {
    "cream" -> Color(0xFFF3E8D4)
    "green" -> Color(0xFFBAC8A8)
    "orange" -> Color(0xFFF4C2A1)
    "violet" -> Color(0xFFD5C6EB)
    "blue" -> Color(0xFFBEDCE7)
    "magenta" -> Color(0xFFEEC3CC)
    "honey" -> Color(0xFFEFDB9B)
    "black" -> Color(0xFFA7AAA8)
    else -> Color(0xFFBEDCE7)
}

internal val WorkRadiusLg = RoundedCornerShape(10.dp)
internal val WorkRadius2xl = RoundedCornerShape(16.dp)
internal val WorkRadiusFull = RoundedCornerShape(9999.dp)

@Composable
internal fun WorkTextButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    primary: Boolean = false,
    selected: Boolean = false,
    contentDescription: String? = null,
) {
    val background = if (primary) WorkColors.fillPrimary else WorkColors.fillSecondary
    val foreground = if (primary) WorkColors.textOnPrimary else WorkColors.textPrimary
    Text(
        text = text,
        color = foreground,
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = modifier
            .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
            .alpha(if (enabled) 1f else 0.45f)
            .background(background, WorkRadiusFull)
            .semantics {
                role = Role.Button
                this.selected = selected
                if (contentDescription != null) this.contentDescription = contentDescription
            }
            .clickable(enabled = enabled, onClick = onClick, role = Role.Button)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    )
}

@Composable
internal fun WorkIconButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier
            .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
            .semantics {
                role = Role.Button
                contentDescription = label
            }
            .clickable(enabled = enabled, onClick = onClick, role = Role.Button),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .heightIn(min = 24.dp)
                .padding(4.dp),
            contentAlignment = Alignment.Center,
        ) {
            content()
        }
    }
}

@Composable
internal fun WorkAlert(message: String, modifier: Modifier = Modifier) {
    Text(
        text = message,
        color = WorkColors.textDanger,
        fontSize = 12.sp,
        modifier = modifier.semantics {
            error(message)
            liveRegion = LiveRegionMode.Assertive
        },
    )
}
