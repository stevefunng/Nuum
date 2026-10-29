package com.nuum.feature.shell.chrome

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.material3.Text
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.stateDescription
import com.nuum.feature.shell.theme.LocalSand
import com.nuum.feature.shell.theme.SandPalette

internal enum class Glyph {
    Search, Plus, Sliders, Pin, Folder, Edit, Copy, ChevronRight, ChevronLeft,
    ArrowUp, ArrowDown, Ungroup, Close, People, Sidebar
}

@Composable
internal fun Int.nuum(): TextUnit {
    val scale = LocalDensity.current.fontScale.coerceAtLeast(0.1f)
    return (this / scale).sp
}

@Composable
internal fun GlyphIcon(glyph: Glyph, size: Dp, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val stroke = Stroke(width = 1.6.dp.toPx(), cap = StrokeCap.Round)
        val w = this.size.width
        val h = this.size.height
        fun line(x1: Float, y1: Float, x2: Float, y2: Float) {
            drawLine(tint, Offset(x1, y1), Offset(x2, y2), stroke.width, cap = StrokeCap.Round)
        }
        when (glyph) {
            Glyph.Search -> {
                drawCircle(tint, radius = w * 0.28f, center = Offset(w * 0.42f, h * 0.42f), style = stroke)
                line(w * 0.64f, h * 0.64f, w * 0.84f, h * 0.84f)
            }
            Glyph.Plus -> {
                line(w * 0.22f, h / 2f, w * 0.78f, h / 2f)
                line(w / 2f, h * 0.22f, w / 2f, h * 0.78f)
            }
            Glyph.Sliders -> {
                line(w * 0.18f, h * 0.3f, w * 0.82f, h * 0.3f)
                line(w * 0.18f, h * 0.5f, w * 0.82f, h * 0.5f)
                line(w * 0.18f, h * 0.7f, w * 0.82f, h * 0.7f)
                drawCircle(tint, radius = w * 0.07f, center = Offset(w * 0.35f, h * 0.3f))
                drawCircle(tint, radius = w * 0.07f, center = Offset(w * 0.62f, h * 0.5f))
                drawCircle(tint, radius = w * 0.07f, center = Offset(w * 0.42f, h * 0.7f))
            }
            Glyph.Pin -> {
                line(w * 0.32f, h * 0.22f, w * 0.68f, h * 0.22f)
                line(w * 0.32f, h * 0.22f, w * 0.38f, h * 0.48f)
                line(w * 0.68f, h * 0.22f, w * 0.62f, h * 0.48f)
                line(w * 0.38f, h * 0.48f, w * 0.62f, h * 0.48f)
                line(w / 2f, h * 0.48f, w / 2f, h * 0.82f)
            }
            Glyph.Folder -> {
                drawRoundRect(
                    color = Color.Transparent,
                    topLeft = Offset(w * 0.16f, h * 0.32f),
                    size = androidx.compose.ui.geometry.Size(w * 0.68f, h * 0.46f),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()),
                    style = stroke
                )
                line(w * 0.16f, h * 0.38f, w * 0.42f, h * 0.38f)
                line(w * 0.42f, h * 0.38f, w * 0.5f, h * 0.28f)
            }
            Glyph.Edit -> {
                line(w * 0.22f, h * 0.72f, w * 0.62f, h * 0.28f)
                line(w * 0.62f, h * 0.28f, w * 0.74f, h * 0.4f)
                line(w * 0.74f, h * 0.4f, w * 0.34f, h * 0.82f)
                line(w * 0.22f, h * 0.72f, w * 0.34f, h * 0.82f)
            }
            Glyph.Copy -> {
                drawRoundRect(
                    color = Color.Transparent,
                    topLeft = Offset(w * 0.28f, h * 0.22f),
                    size = androidx.compose.ui.geometry.Size(w * 0.42f, h * 0.5f),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()),
                    style = stroke
                )
                drawRoundRect(
                    color = Color.Transparent,
                    topLeft = Offset(w * 0.18f, h * 0.34f),
                    size = androidx.compose.ui.geometry.Size(w * 0.42f, h * 0.5f),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()),
                    style = stroke
                )
            }
            Glyph.ChevronRight -> {
                line(w * 0.34f, h * 0.22f, w * 0.66f, h * 0.5f)
                line(w * 0.66f, h * 0.5f, w * 0.34f, h * 0.78f)
            }
            Glyph.ChevronLeft -> {
                line(w * 0.66f, h * 0.22f, w * 0.34f, h * 0.5f)
                line(w * 0.34f, h * 0.5f, w * 0.66f, h * 0.78f)
            }
            Glyph.ArrowUp -> line(w / 2f, h * 0.78f, w / 2f, h * 0.22f).also {
                line(w * 0.28f, h * 0.42f, w / 2f, h * 0.22f)
                line(w * 0.72f, h * 0.42f, w / 2f, h * 0.22f)
            }
            Glyph.ArrowDown -> {
                line(w / 2f, h * 0.22f, w / 2f, h * 0.78f)
                line(w * 0.28f, h * 0.58f, w / 2f, h * 0.78f)
                line(w * 0.72f, h * 0.58f, w / 2f, h * 0.78f)
            }
            Glyph.Ungroup -> {
                line(w * 0.2f, h * 0.35f, w * 0.45f, h * 0.35f)
                line(w * 0.55f, h * 0.65f, w * 0.8f, h * 0.65f)
                line(w * 0.3f, h * 0.55f, w * 0.7f, h * 0.45f)
            }
            Glyph.Close -> {
                line(w * 0.28f, h * 0.28f, w * 0.72f, h * 0.72f)
                line(w * 0.72f, h * 0.28f, w * 0.28f, h * 0.72f)
            }
            Glyph.People -> {
                drawCircle(tint, radius = w * 0.12f, center = Offset(w * 0.38f, h * 0.32f), style = stroke)
                drawCircle(tint, radius = w * 0.1f, center = Offset(w * 0.64f, h * 0.36f), style = stroke)
                line(w * 0.18f, h * 0.78f, w * 0.58f, h * 0.78f)
                line(w * 0.48f, h * 0.78f, w * 0.84f, h * 0.78f)
            }
            Glyph.Sidebar -> {
                drawRoundRect(
                    color = Color.Transparent,
                    topLeft = Offset(w * 0.18f, h * 0.2f),
                    size = androidx.compose.ui.geometry.Size(w * 0.64f, h * 0.6f),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()),
                    style = stroke
                )
                line(w * 0.42f, h * 0.2f, w * 0.42f, h * 0.8f)
            }
        }
    }
}

@Composable
internal fun IconHit(
    label: String,
    glyph: Glyph,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    expanded: Boolean? = null,
    title: String? = null
) {
    val sand = LocalSand.current
    Box(
        modifier
            .size(48.dp)
            .semantics {
                role = Role.Button
                contentDescription = label
                val state = listOfNotNull(
                    title,
                    expanded?.let { if (it) "expanded" else "collapsed" }
                ).joinToString(", ")
                if (state.isNotEmpty()) stateDescription = state
            }
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Box(
            Modifier
                .size(24.dp)
                .clip(CircleShape)
                .background(if (enabled) Color.Transparent else sand.fillSecondary),
            contentAlignment = Alignment.Center
        ) {
            GlyphIcon(glyph, 16.dp, if (enabled) sand.textPrimary else sand.textTertiary)
        }
    }
}

@Composable
internal fun SandText(
    text: String,
    color: Color,
    size: Int,
    modifier: Modifier = Modifier,
    weight: FontWeight = FontWeight.Normal,
    maxLines: Int = Int.MAX_VALUE,
    family: FontFamily = FontFamily.SansSerif,
    textAlign: TextAlign? = null
) {
    Text(
        text = text,
        color = color,
        fontSize = size.nuum(),
        fontWeight = weight,
        maxLines = maxLines,
        overflow = TextOverflow.Ellipsis,
        textAlign = textAlign ?: TextAlign.Unspecified,
        fontFamily = family,
        letterSpacing = if (size == 13) (-0.08f).sp else TextUnit.Unspecified,
        lineHeight = when (size) {
            11 -> 14.nuum()
            12 -> 16.nuum()
            13 -> 18.nuum()
            14 -> 22.nuum()
            else -> TextUnit.Unspecified
        },
        modifier = modifier
    )
}

@Composable
internal fun AlertLine(text: String, modifier: Modifier = Modifier) {
    val sand = LocalSand.current
    SandText(
        text = text,
        color = sand.textDanger,
        size = 12,
        modifier = modifier.semantics { liveRegion = LiveRegionMode.Assertive }
    )
}

@Composable
internal fun PillButton(
    label: String,
    primary: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val sand = LocalSand.current
    val background = if (primary) sand.fillPrimary else sand.bgSecondary
    val foreground = if (primary) sand.textOnPrimary else sand.textPrimary
    Box(
        modifier
            .heightIn(min = 48.dp)
            .semantics {
                role = Role.Button
                contentDescription = label
            }
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Box(
            Modifier
                .height(32.dp)
                .clip(RoundedCornerShape(999.dp))
                .background(background.copy(alpha = if (enabled) background.alpha else background.alpha))
                .padding(horizontal = 14.dp),
            contentAlignment = Alignment.Center
        ) {
            SandText(
                label,
                foreground.copy(alpha = if (enabled) 1f else 0.45f),
                13,
                weight = FontWeight.SemiBold
            )
        }
    }
}

internal data class MenuEntry(
    val label: String,
    val glyph: Glyph,
    val enabled: Boolean = true,
    val separator: Boolean = false,
    val onSelect: () -> Unit
)

@Composable
internal fun ActionMenu(
    entries: List<MenuEntry>,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    label: String
) {
    val sand = LocalSand.current
    Box(
        Modifier
            .fillMaxSize()
            .clickable(onClick = onDismiss)
            .padding(12.dp)
    ) {
        Column(
            modifier
                .widthIn(min = 208.dp, max = 300.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(sand.bgElevated)
                .semantics { contentDescription = label }
                .clickable(enabled = false, onClick = {})
                .padding(vertical = 6.dp)
        ) {
            entries.forEach { entry ->
                if (entry.separator) {
                    Box(
                        Modifier
                            .padding(vertical = 4.dp)
                            .fillMaxWidth()
                            .height(1.dp)
                            .background(sand.borderSubtle)
                    )
                }
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 40.dp)
                        .clickable(enabled = entry.enabled, onClick = entry.onSelect)
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    GlyphIcon(
                        entry.glyph,
                        16.dp,
                        if (entry.enabled) sand.textPrimary else sand.textTertiary
                    )
                    SandText(
                        entry.label,
                        if (entry.enabled) sand.textPrimary else sand.textTertiary,
                        13
                    )
                }
            }
        }
    }
}

@Composable
internal fun SandPalette.panel(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(
        modifier
            .clip(RoundedCornerShape(18.dp))
            .background(bgElevated)
            .padding(PaddingValues(0.dp))
    ) { content() }
}
