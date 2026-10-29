package com.nuum.feature.shell.create

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nuum.feature.shell.avatar.COLOR_LABEL_KEYS
import com.nuum.feature.shell.avatar.NunuAvatar
import com.nuum.feature.shell.chrome.AlertLine
import com.nuum.feature.shell.chrome.Glyph
import com.nuum.feature.shell.chrome.IconHit
import com.nuum.feature.shell.chrome.PillButton
import com.nuum.feature.shell.chrome.SandText
import com.nuum.feature.shell.chrome.nuum
import com.nuum.feature.shell.model.ShellModel
import com.nuum.feature.shell.motion.LocalAvatarRandom
import com.nuum.feature.shell.motion.LocalUnboxFrameClock
import com.nuum.feature.shell.motion.UNBOX_DURATION_MS
import com.nuum.feature.shell.motion.easeOutStrong
import com.nuum.feature.shell.motion.isReducedMotion
import com.nuum.feature.shell.theme.LocalCopy
import com.nuum.feature.shell.theme.LocalSand
import com.nuum.protocol.AGENT_AVATAR_COLORS
import com.nuum.protocol.rollAgentAvatar
import kotlin.random.Random

internal enum class UnboxPackage { SoftTray, PaperFold, RoundBox }

internal fun rollUnboxingPackage(random: Random): UnboxPackage {
    val index = random.nextInt(3).coerceAtMost(2)
    return UnboxPackage.entries[index]
}

@Composable
internal fun CreateNunuLayer(model: ShellModel, onDismiss: () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val compact = maxWidth < 840.dp
        val dialogWidth = (maxWidth - 32.dp).coerceAtMost(440.dp)
        if (compact) {
            CreateNunuPage(model, onDismiss, Modifier.fillMaxSize().background(LocalSand.current.bgEditor))
        } else {
            val sand = LocalSand.current
            Box(
                Modifier
                    .fillMaxSize()
                    .background(sand.scrim)
                    .clickable(enabled = !model.creating) { onDismiss() },
                contentAlignment = Alignment.Center
            ) {
                CreateNunuPage(
                    model,
                    onDismiss,
                    Modifier
                        .widthIn(max = 440.dp)
                        .width(dialogWidth)
                        .clip(RoundedCornerShape(18.dp))
                        .background(sand.bgElevated)
                        .clickable(onClick = {})
                )
            }
        }
    }
}

@Composable
private fun CreateNunuPage(model: ShellModel, onDismiss: () -> Unit, modifier: Modifier) {
    val copy = LocalCopy.current
    val sand = LocalSand.current
    val random = LocalAvatarRandom.current
    val roll = remember { rollAgentAvatar(random) }
    var color by remember { mutableStateOf(roll.color) }
    var name by remember { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    Column(modifier.semantics { contentDescription = copy.t("Create new Nunu"); heading() }) {
        Row(
            Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            SandText(
                copy.t("Create new Nunu"),
                sand.textPrimary,
                14,
                Modifier.weight(1f)
            )
            IconHit(
                label = copy.t("Close dialog"),
                glyph = Glyph.Close,
                onClick = onDismiss,
                enabled = !model.creating
            )
        }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val unboxHeight = if (maxHeight < 640.dp && maxHeight > 0.dp) 192.dp else 280.dp
            NunuUnbox(
                agentId = "create",
                color = color,
                shape = roll.shape,
                material = roll.material,
                modifier = Modifier.fillMaxWidth().height(unboxHeight)
            )
        }
        BasicTextField(
            value = name,
            onValueChange = { if (it.length <= 80) name = it },
            singleLine = true,
            enabled = !model.creating,
            textStyle = TextStyle(
                color = sand.textPrimary,
                fontSize = 14.nuum(),
                textAlign = TextAlign.Center
            ),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = {
                model.createAgent(name, color, roll.shape, roll.material)
            }),
            modifier = Modifier
                .padding(horizontal = 16.dp)
                .fillMaxWidth()
                .height(36.dp)
                .clip(RoundedCornerShape(9.dp))
                .border(1.dp, sand.borderDefault, RoundedCornerShape(9.dp))
                .padding(horizontal = 12.dp)
                .focusRequester(focus)
                .testTag("nunu-name")
                .semantics { contentDescription = copy.t("Nunu name") },
            decorationBox = { inner ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    if (name.isEmpty()) {
                        SandText(copy.t("Give your Nunu a name"), sand.textTertiary, 14)
                    }
                    inner()
                }
            }
        )
        Row(
            Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp)
                .horizontalScroll(rememberScrollState())
                .semantics { contentDescription = copy.t("Nunu color") },
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AGENT_AVATAR_COLORS.forEach { swatch ->
                val label = copy.t(COLOR_LABEL_KEYS.getValue(swatch.id))
                val selected = color == swatch.id
                Box(
                    Modifier
                        .size(48.dp)
                        .testTag("swatch-${swatch.id}")
                        .semantics {
                            contentDescription = label
                            this.selected = selected
                        }
                        .clickable(enabled = !model.creating) { color = swatch.id },
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        Modifier
                            .size(36.dp)
                            .border(
                                1.dp,
                                if (selected) sand.borderFocus else sand.borderSubtle,
                                CircleShape
                            )
                            .padding(1.dp)
                            .background(sand.bgElevated, CircleShape)
                            .padding(3.dp)
                            .background(com.nuum.feature.shell.theme.css(swatch.value), CircleShape)
                    )
                }
            }
        }
        model.createError?.let { message ->
            AlertLine(copy.t(message), Modifier.padding(horizontal = 16.dp))
        }
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically
        ) {
            PillButton(copy.t("Cancel"), primary = false, enabled = !model.creating, onClick = onDismiss)
            PillButton(
                label = if (model.creating) copy.t("Creating…") else copy.t("Create"),
                primary = true,
                enabled = !model.creating && name.isNotBlank(),
                onClick = { model.createAgent(name, color, roll.shape, roll.material) }
            )
        }
    }
}

/**
 * 2D unbox. Reduced motion paints the rest pose on the first frame and does not
 * call [LocalUnboxFrameClock]. Changing color does not replay the open.
 */
@Composable
internal fun NunuUnbox(
    agentId: String,
    color: String,
    shape: String,
    material: String,
    modifier: Modifier = Modifier
) {
    val reduced = isReducedMotion()
    val openedReduced = remember { reduced }
    var progress by remember { mutableFloatStateOf(if (openedReduced) 1f else 0f) }
    val packageKind = remember(openedReduced) {
        if (openedReduced) null else rollUnboxingPackage(Random.Default)
    }
    if (!openedReduced) {
        val clock = LocalUnboxFrameClock.current
        LaunchedEffect(clock) {
            var start = 0L
            var elapsed = 0L
            while (elapsed < UNBOX_DURATION_MS) {
                clock.awaitFrame { nanos ->
                    if (start == 0L) start = nanos
                    elapsed = ((nanos - start) / 1_000_000L).coerceAtLeast(0L)
                    progress = (elapsed.toFloat() / UNBOX_DURATION_MS.toFloat()).coerceIn(0f, 1f)
                }
            }
            progress = 1f
        }
    }
    val eased = if (openedReduced) 1f else easeOutStrong(progress)
    val scale = if (openedReduced) 1f else 0.92f + 0.08f * eased
    val showPackaging = !openedReduced && eased < 0.999f && packageKind != null
    val sand = LocalSand.current
    Box(
        modifier.semantics { },
        contentAlignment = Alignment.Center
    ) {
        if (progress >= 1f || openedReduced) {
            Box(Modifier.testTag("unbox-settled"))
        }
        if (showPackaging) {
            val pigment = com.nuum.feature.shell.theme.css(
                AGENT_AVATAR_COLORS.first { it.id == color }.value
            )
            val fill = Color(
                red = pigment.red * 0.4f + sand.bgElevated.red * 0.6f,
                green = pigment.green * 0.4f + sand.bgElevated.green * 0.6f,
                blue = pigment.blue * 0.4f + sand.bgElevated.blue * 0.6f,
                alpha = 1f - eased
            )
            Box(
                Modifier
                    .size(160.dp)
                    .testTag("unbox-packaging")
                    .drawBehind { drawPackage(packageKind!!, fill) }
            )
        }
        Box(Modifier.size(190.dp * scale)) {
            NunuAvatar(
                agentId = agentId,
                color = color,
                shape = shape,
                material = material,
                size = 190.dp * scale,
                fullBody = true
            )
        }
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawPackage(kind: UnboxPackage, fill: Color) {
    when (kind) {
        UnboxPackage.SoftTray -> drawRoundRect(fill, cornerRadius = androidx.compose.ui.geometry.CornerRadius(18.dp.toPx(), 18.dp.toPx()), style = Fill)
        UnboxPackage.RoundBox -> drawCircle(fill)
        UnboxPackage.PaperFold -> {
            val path = Path().apply {
                val w = size.width
                val h = size.height
                val fold = w * 0.18f
                moveTo(0f, 0f)
                lineTo(w - fold, 0f)
                lineTo(w, fold)
                lineTo(w, h)
                lineTo(0f, h)
                close()
            }
            drawPath(path, fill)
        }
    }
}
