package com.nuum.feature.shell.profile

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nuum.contracts.AgentView
import com.nuum.feature.shell.ExecutionPreferencesForm
import com.nuum.feature.shell.avatar.NunuAvatar
import com.nuum.feature.shell.chrome.AlertLine
import com.nuum.feature.shell.chrome.Glyph
import com.nuum.feature.shell.chrome.IconHit
import com.nuum.feature.shell.chrome.PillButton
import com.nuum.feature.shell.chrome.SandText
import com.nuum.feature.shell.chrome.nuum
import com.nuum.feature.shell.model.NAME_EMPTY
import com.nuum.feature.shell.model.ShellModel
import com.nuum.feature.shell.motion.isReducedMotion
import com.nuum.feature.shell.theme.LocalCopy
import com.nuum.feature.shell.theme.LocalSand
import java.time.Instant
import java.time.ZoneId

private data class RoleTemplate(
    val nameKey: String,
    val descriptionKey: String,
    val tagsKey: String,
    val colorId: String,
    val shape: String
)

private val templates = listOf(
    RoleTemplate(
        "Researcher",
        "Track a topic, read sources, and bring back concise findings.",
        "Research, sources",
        "blue",
        "droplet"
    ),
    RoleTemplate(
        "Project partner",
        "Stay with one project, remember decisions, and help move it forward.",
        "Projects, follow-ups",
        "green",
        "blob"
    ),
    RoleTemplate(
        "Daily operator",
        "Handle recurring local tasks and keep an eye on follow-ups.",
        "Daily tasks, reminders",
        "orange",
        "tablet"
    )
)

@Composable
internal fun ProfilePane(model: ShellModel, agent: AgentView?, modifier: Modifier = Modifier) {
    val copy = LocalCopy.current
    val sand = LocalSand.current
    Box(modifier.background(sand.bgEditor).semantics { contentDescription = copy.t("Nunu identity") }) {
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            SandText(copy.t("Nunu identity"), sand.textPrimary, 14, Modifier.weight(1f))
            IconHit(copy.t("Close profile"), Glyph.ChevronRight, onClick = { model.closeProfile() })
        }
        if (agent == null) {
            Box(Modifier.fillMaxWidth().heightIn(min = 390.dp))
        } else {
        Column(Modifier.verticalScroll(rememberScrollState()).weight(1f)) {
            Badge(agent, onEdit = { model.identityOpen = true; model.identityError = null })
            val root = if (agent.profile.id in model.workspaceRevoked) {
                null
            } else {
                agent.settings.workspace?.projectRoot
            }
            ExecutionPreferencesForm(
                execution = agent.settings.execution,
                projectRoot = root,
                saving = model.executionSaving,
                error = model.executionError,
                onCommands = { model.setCommands(agent, it) },
                onRevokeCommand = { model.revokeCommand(agent, it) },
                onRevokeNetwork = { model.revokeNetwork(agent, it) },
                onOpenFolder = { model.openFolder(agent) },
                modifier = Modifier.padding(bottom = 24.dp)
            )
        }
        }
    }
    if (agent != null && model.identityOpen) {
        IdentityDialog(model, agent)
    }
    }
}

@Composable
private fun Badge(agent: AgentView, onEdit: () -> Unit) {
    val copy = LocalCopy.current
    val sand = LocalSand.current
    val profile = agent.profile
    var reaction by remember(profile.id) { mutableIntStateOf(0) }
    val reduced = isReducedMotion()
    val scale = remember(profile.id) { Animatable(1f) }
    LaunchedEffect(reaction, reduced) {
        if (reduced || reaction == 0) {
            scale.snapTo(1f)
            return@LaunchedEffect
        }
        scale.animateTo(1.04f, tween(150))
        scale.animateTo(1f, tween(150))
    }
    val date = remember(profile.createdAt) { formatDate(profile.createdAt) }
    Column(
        Modifier
            .padding(16.dp)
            .fillMaxWidth()
            .heightIn(min = 390.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(Brush.linearGradient(listOf(sand.badgePaperTop, sand.badgePaperBottom)))
            .clickable(onClick = onEdit)
            .semantics { contentDescription = copy.t("Click to edit profile") }
            .padding(start = 24.dp, end = 24.dp, top = 28.dp, bottom = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(Modifier.fillMaxWidth(0.88f).heightIn(min = 180.dp), contentAlignment = Alignment.Center) {
            androidx.compose.foundation.Canvas(Modifier.fillMaxSize()) {
                val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                    color = android.graphics.Color.parseColor("#171F24")
                    textSize = 11.dp.toPx()
                    textAlign = android.graphics.Paint.Align.LEFT
                }
                val ring = android.graphics.Path().apply {
                    addCircle(center.x, center.y, size.minDimension * 0.42f, android.graphics.Path.Direction.CW)
                }
                drawContext.canvas.nativeCanvas.drawTextOnPath(
                    "NUUM · A MIND OF YOUR OWN · NUUM · ALWAYS WITH YOU · ",
                    ring,
                    0f,
                    -4f,
                    paint
                )
                drawCircle(
                    color = sand.badgeInk.copy(alpha = 0.35f),
                    radius = size.minDimension * 0.38f,
                    style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.dp.toPx())
                )
            }
            Box(
                Modifier
                    .size(120.dp)
                    .graphicsLayer {
                        scaleX = scale.value
                        scaleY = scale.value
                    }
                    .clip(CircleShape)
                    .clickable {
                        reaction += 1
                    }
                    .semantics { contentDescription = copy.t("Greet {name}", "name" to profile.name) },
                contentAlignment = Alignment.Center
            ) {
                NunuAvatar(
                    agentId = profile.id,
                    color = profile.avatarColor,
                    shape = profile.avatarShape,
                    material = profile.avatarMaterial,
                    size = 108.dp,
                    fullBody = true
                )
            }
        }
        SandText(profile.name, sand.badgeInk, 24, weight = FontWeight.SemiBold, maxLines = 1, modifier = Modifier.padding(top = 12.dp))
        if (profile.tags.isNotEmpty()) {
            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                profile.tags.forEach { tag ->
                    SandText(
                        tag,
                        sand.badgeInk,
                        11,
                        modifier = Modifier
                            .border(1.dp, sand.badgeInk.copy(alpha = 0.2f), RoundedCornerShape(999.dp))
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                    )
                }
            }
        }
        val description = profile.description.ifBlank { copy.t("What should this Agent do?") }
        SandText(
            description,
            sand.badgeInk.copy(alpha = if (profile.description.isBlank()) 0.55f else 1f),
            13,
            modifier = Modifier.padding(top = 8.dp)
        )
        Row(Modifier.fillMaxWidth().padding(top = 16.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
            SandText(copy.t("Created on") + " " + date, sand.badgeInk, 11)
            SandText("Nuum", sand.badgeInk, 13, weight = FontWeight.SemiBold, modifier = Modifier.semantics { contentDescription = "Nuum" })
        }
    }
}

@Composable
private fun IdentityDialog(model: ShellModel, agent: AgentView) {
    val copy = LocalCopy.current
    val sand = LocalSand.current
    val profile = agent.profile
    var name by remember(profile.id) { mutableStateOf(profile.name) }
    var tags by remember(profile.id) { mutableStateOf(profile.tags.joinToString(", ")) }
    var description by remember(profile.id) { mutableStateOf(profile.description) }
    val showTemplates = profile.id !in model.identityEdited
    Box(
        Modifier
            .fillMaxSize()
            .background(sand.scrim)
            .clickable(enabled = !model.identitySaving) { model.closeIdentity() },
        contentAlignment = Alignment.Center
    ) {
        Column(
            Modifier
                .padding(16.dp)
                .widthIn(max = 440.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(18.dp))
                .background(sand.bgElevated)
                .clickable(onClick = {})
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SandText(copy.t("Nunu identity"), sand.textPrimary, 14, Modifier.weight(1f))
                IconHit(copy.t("Close dialog"), Glyph.Close, enabled = !model.identitySaving, onClick = { model.closeIdentity() })
            }
            IdentityField(copy.t("Name"), name, !model.identitySaving, placeholder = "") { name = it }
            IdentityField(copy.t("Tags (optional)"), tags, !model.identitySaving, copy.t("Research, design, operations")) { tags = it }
            IdentityField(copy.t("Description"), description, !model.identitySaving, copy.t("What should this Agent do?" )) { description = it }
            if (showTemplates) {
                SandText(copy.t("Recommended templates"), sand.textSecondary, 12)
                templates.forEach { template ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clickable(enabled = !model.identitySaving) {
                                name = copy.t(template.nameKey)
                                tags = copy.t(template.tagsKey)
                                description = copy.t(template.descriptionKey)
                            }
                            .padding(vertical = 6.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        NunuAvatar(template.nameKey, template.colorId, template.shape, "matte", 18.dp, fullBody = false)
                        Column {
                            SandText(copy.t(template.nameKey), sand.textPrimary, 13, weight = FontWeight.SemiBold)
                            SandText(copy.t(template.descriptionKey), sand.textSecondary, 12)
                        }
                    }
                }
            }
            model.identityError?.let { AlertLine(copy.t(it)) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                PillButton(copy.t("Cancel"), primary = false, enabled = !model.identitySaving, onClick = { model.closeIdentity() })
                PillButton(
                    label = if (model.identitySaving) copy.t("Saving…") else copy.t("Finish"),
                    primary = true,
                    enabled = !model.identitySaving,
                    onClick = {
                        if (name.trim().isEmpty()) model.identityError = NAME_EMPTY
                        else model.saveIdentity(profile.id, name, tags, description)
                    }
                )
            }
        }
    }
}

@Composable
private fun IdentityField(
    label: String,
    value: String,
    enabled: Boolean,
    placeholder: String,
    onValue: (String) -> Unit
) {
    val sand = LocalSand.current
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        SandText(label, sand.textSecondary, 12)
        BasicTextField(
            value = value,
            onValueChange = onValue,
            enabled = enabled,
            textStyle = TextStyle(color = sand.textPrimary, fontSize = 14.nuum()),
            modifier = Modifier
                .fillMaxWidth()
                .border(1.dp, sand.borderDefault, RoundedCornerShape(10.dp))
                .padding(horizontal = 10.dp, vertical = 8.dp)
                .semantics { contentDescription = label },
            decorationBox = { inner ->
                Box {
                    if (value.isEmpty() && placeholder.isNotEmpty()) SandText(placeholder, sand.textTertiary, 13)
                    inner()
                }
            }
        )
    }
}

private fun formatDate(epochMillis: Long): String {
    val date = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()).toLocalDate()
    return "%04d/%02d/%02d".format(date.year, date.monthValue, date.dayOfMonth)
}

@Composable
internal fun profileWidthModifier(): Modifier = Modifier
    .fillMaxHeight()
    .widthIn(min = 300.dp, max = 420.dp)
    .fillMaxWidth(0.33f)
    .border(width = 1.dp, color = LocalSand.current.borderSubtle)
