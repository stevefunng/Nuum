package com.nuum.feature.settings

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal enum class SettingsSection { General, Models }

@Composable
internal fun SettingsIcon(name: String, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(14.dp)) {
        val stroke = 1.4.dp.toPx()
        when (name) {
            "settings-gear" -> {
                val center = Offset(size.width / 2f, size.height / 2f)
                drawCircle(tint, radius = size.minDimension * 0.18f, center = center, style = Stroke(stroke))
                val inner = size.minDimension * 0.28f
                val outer = size.minDimension * 0.46f
                for (index in 0 until 8) {
                    val angle = index * PI / 4.0
                    drawLine(
                        color = tint,
                        start = Offset(
                            (center.x + cos(angle) * inner).toFloat(),
                            (center.y + sin(angle) * inner).toFloat()
                        ),
                        end = Offset(
                            (center.x + cos(angle) * outer).toFloat(),
                            (center.y + sin(angle) * outer).toFloat()
                        ),
                        strokeWidth = stroke,
                        cap = StrokeCap.Round
                    )
                }
            }
            "sliders" -> {
                val ys = listOf(size.height * 0.22f, size.height * 0.5f, size.height * 0.78f)
                val knobs = listOf(0.32f, 0.68f, 0.45f)
                ys.forEachIndexed { index, y ->
                    drawLine(tint, Offset(0f, y), Offset(size.width, y), stroke, StrokeCap.Round)
                    drawCircle(tint, radius = 2.2.dp.toPx(), center = Offset(size.width * knobs[index], y))
                }
            }
            "close" -> {
                val inset = size.minDimension * 0.22f
                drawLine(tint, Offset(inset, inset), Offset(size.width - inset, size.height - inset), stroke, StrokeCap.Round)
                drawLine(tint, Offset(size.width - inset, inset), Offset(inset, size.height - inset), stroke, StrokeCap.Round)
            }
            "chevron-right" -> {
                val midY = size.height / 2f
                drawLine(tint, Offset(size.width * 0.35f, size.height * 0.22f), Offset(size.width * 0.68f, midY), stroke, StrokeCap.Round)
                drawLine(tint, Offset(size.width * 0.68f, midY), Offset(size.width * 0.35f, size.height * 0.78f), stroke, StrokeCap.Round)
            }
        }
    }
}

@Composable
internal fun SettingsNavButton(
    label: String,
    icon: String,
    selected: Boolean,
    wide: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val palette = LocalNuumPalette.current
    Row(
        modifier
            .heightIn(min = if (wide) 32.dp else 48.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (selected) palette.fillGhostSelected else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 7.dp)
            .semantics {
                this.selected = selected
                role = Role.Tab
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(9.dp)
    ) {
        SettingsIcon(icon, if (selected) palette.textPrimary else palette.textSecondary)
        Text(
            text = label,
            color = if (selected) palette.textPrimary else palette.textSecondary,
            fontSize = 13.sp,
            fontFamily = FontFamily.SansSerif
        )
    }
}

@Composable
internal fun SettingsGroup(title: String, content: @Composable () -> Unit) {
    val palette = LocalNuumPalette.current
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(0.dp)) {
        Text(
            text = title,
            color = palette.textSecondary,
            fontSize = 12.sp,
            lineHeight = 17.sp,
            fontWeight = FontWeight.Medium,
            fontFamily = FontFamily.SansSerif,
            modifier = Modifier.padding(bottom = 8.dp)
        )
        content()
    }
}

@Composable
internal fun SettingsRow(
    title: String,
    description: String,
    alert: String?,
    compact: Boolean,
    control: @Composable () -> Unit
) {
    val palette = LocalNuumPalette.current
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = title,
                    color = palette.textPrimary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    fontFamily = FontFamily.SansSerif
                )
                Text(
                    text = description,
                    color = palette.textSecondary,
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    fontFamily = FontFamily.SansSerif
                )
            }
            Box(Modifier.then(if (compact) Modifier.widthIn(min = 160.dp) else Modifier)) {
                control()
            }
        }
        if (alert != null) {
            Text(
                text = alert,
                color = palette.textDanger,
                fontSize = 12.sp,
                lineHeight = 16.sp,
                fontFamily = FontFamily.SansSerif,
                modifier = Modifier
                    .padding(bottom = 8.dp)
                    .semantics {
                        liveRegion = LiveRegionMode.Assertive
                        contentDescription = alert
                    }
            )
        }
    }
}

@Composable
internal fun SettingsSelect(
    label: String,
    valueLabel: String,
    enabled: Boolean,
    options: List<Pair<String, String>>,
    selectedValue: String?,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    testTag: String
) {
    val palette = LocalNuumPalette.current
    var open by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(10.dp)
    Box(modifier) {
        Row(
            Modifier
                .testTag(testTag)
                .heightIn(min = 48.dp)
                .widthIn(min = 120.dp, max = 190.dp)
                .clip(shape)
                .border(1.dp, palette.borderDefault, shape)
                .background(palette.textPrimary.copy(alpha = 0.04f))
                .clickable(enabled = enabled, onClick = { open = true })
                .padding(horizontal = 9.dp, vertical = 5.dp)
                .semantics { contentDescription = label },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = valueLabel,
                color = if (enabled) palette.textPrimary else palette.textTertiary,
                fontSize = 13.sp,
                fontFamily = FontFamily.SansSerif
            )
            SettingsIcon("chevron-right", palette.textSecondary, Modifier.size(12.dp))
        }
        DropdownMenu(
            expanded = open,
            onDismissRequest = { open = false },
            containerColor = palette.bgElevated,
            shape = RoundedCornerShape(10.dp)
        ) {
            options.forEach { (value, optionLabel) ->
                DropdownMenuItem(
                    text = {
                        Text(optionLabel, color = palette.textPrimary, fontSize = 13.sp)
                    },
                    onClick = {
                        open = false
                        onSelect(value)
                    },
                    modifier = Modifier.testTag("option-$value"),
                    trailingIcon = {
                        if (value == selectedValue) {
                            Text("✓", color = palette.textPrimary, fontSize = 16.sp)
                        }
                    }
                )
            }
        }
    }
}

@Composable
internal fun ApiKeyField(
    label: String,
    error: String?,
    compact: Boolean,
    testTag: String,
    onBlur: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val palette = LocalNuumPalette.current
    val focusManager = LocalFocusManager.current
    var text by remember { mutableStateOf("") }
    var focused by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(10.dp)
    val width = if (compact) Modifier.fillMaxWidth().widthIn(min = 160.dp) else Modifier.width(175.dp)
    BasicTextField(
        value = text,
        onValueChange = { text = it },
        modifier = modifier
            .testTag(testTag)
            .then(width)
            .heightIn(min = 48.dp)
            .onFocusChanged { state ->
                val wasFocused = focused
                focused = state.isFocused
                if (wasFocused && !state.isFocused) onBlur(text)
            }
            .semantics { contentDescription = label },
        enabled = true,
        textStyle = TextStyle(
            color = palette.textPrimary,
            fontSize = 12.sp,
            fontFamily = FontFamily.SansSerif
        ),
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Password,
            imeAction = ImeAction.Done,
            autoCorrectEnabled = false
        ),
        keyboardActions = KeyboardActions(
            onDone = {
                onBlur(text)
                focusManager.clearFocus()
            }
        ),
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        cursorBrush = SolidColor(palette.textPrimary),
        decorationBox = { inner ->
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 36.dp)
                    .clip(shape)
                    .background(palette.bgInput)
                    .border(1.dp, if (error != null) palette.textDanger else palette.borderDefault, shape)
                    .padding(horizontal = 9.dp, vertical = 8.dp),
                contentAlignment = Alignment.CenterStart
            ) {
                inner()
            }
        }
    )
}

@Composable
internal fun SandSwitch(
    checked: Boolean,
    enabled: Boolean,
    label: String,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier
) {
    val palette = LocalNuumPalette.current
    val track = if (checked) palette.textPrimary else palette.fillControlTrack
    val knob = if (checked) palette.textOnPrimary else palette.textPrimary
    Box(
        modifier
            .size(width = 48.dp, height = 48.dp)
            .clickable(enabled = enabled, role = Role.Switch, onClick = onToggle)
            .semantics {
                contentDescription = label
                selected = checked
            },
        contentAlignment = Alignment.CenterEnd
    ) {
        Box(
            Modifier
                .size(width = 40.dp, height = 24.dp)
                .clip(RoundedCornerShape(999.dp))
                .background(track)
        ) {
            Box(
                Modifier
                    .padding(2.dp)
                    .size(20.dp)
                    .align(if (checked) Alignment.CenterEnd else Alignment.CenterStart)
                    .clip(RoundedCornerShape(999.dp))
                    .background(knob)
            )
        }
    }
}

@Composable
internal fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    val palette = LocalNuumPalette.current
    Text(
        text = text,
        color = palette.textPrimary,
        fontSize = 15.sp,
        lineHeight = 20.sp,
        fontWeight = FontWeight.Medium,
        letterSpacing = (-0.3).sp,
        fontFamily = FontFamily.SansSerif,
        modifier = modifier
            .heightIn(min = 54.dp)
            .padding(horizontal = 24.dp, vertical = 17.dp)
            .semantics { heading() }
    )
}
