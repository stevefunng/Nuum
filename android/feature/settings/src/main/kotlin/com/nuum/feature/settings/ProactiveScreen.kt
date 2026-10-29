package com.nuum.feature.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.activity.compose.LocalOnBackPressedDispatcherOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nuum.contracts.ProactiveActivity
import com.nuum.contracts.ProactiveAgentSnapshot
import com.nuum.contracts.ProactiveSnapshot
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * In-app proactive panel opened from Settings. System back returns to General.
 * There is no tray and no Quit control. Agent actions follow
 * [ProactiveSnapshot.actionsAvailable].
 */
@Composable
fun ProactiveScreen(
    dependencies: SettingsDependencies,
    onBack: () -> Unit,
    onOpenAgent: (agentId: String) -> Unit,
    onOpenShell: () -> Unit,
    modifier: Modifier = Modifier,
    systemDark: Boolean = androidx.compose.foundation.isSystemInDarkTheme()
) {
    val viewModel: ProactiveViewModel = viewModel(
        factory = ProactiveViewModel.factory(
            dependencies.settings,
            dependencies.proactive,
            dependencies.clock
        )
    )
    val state by viewModel.state.collectAsState()
    if (LocalOnBackPressedDispatcherOwner.current != null) {
        BackHandler(onBack = onBack)
    }
    NuumTheme(preference = state.theme, systemDark = systemDark) {
        NuumLanguage(language = state.language) {
            ProactiveContent(
                state = state,
                onToggle = viewModel::onToggle,
                onResume = viewModel::onResume,
                onPause = viewModel::onPause,
                onCheck = viewModel::onCheck,
                onRetry = viewModel::onRetry,
                onOpenAgent = onOpenAgent,
                onOpenShell = onOpenShell,
                modifier = modifier
            )
        }
    }
}

@Composable
private fun ProactiveContent(
    state: ProactiveUiState,
    onToggle: () -> Unit,
    onResume: () -> Unit,
    onPause: (Long) -> Unit,
    onCheck: () -> Unit,
    onRetry: () -> Unit,
    onOpenAgent: (String) -> Unit,
    onOpenShell: () -> Unit,
    modifier: Modifier = Modifier
) {
    val palette = LocalNuumPalette.current
    val snapshot = state.snapshot
    val agent = proactiveCompanion(snapshot)
    val loaded = snapshot != null
    Column(
        modifier
            .fillMaxSize()
            .background(palette.bgElevated)
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
            .testTag(palette.modeName)
            .semantics { stateDescription = if (loaded) "loaded" else "loading" },
        verticalArrangement = Arrangement.spacedBy(0.dp)
    ) {
        Row(
            Modifier.fillMaxWidth().padding(bottom = 18.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Bottom
        ) {
            Text(
                text = "Nuum",
                color = palette.textPrimary,
                fontSize = 17.sp,
                fontWeight = FontWeight(650),
                letterSpacing = (-0.5).sp,
                fontFamily = FontFamily.SansSerif
            )
            Text(
                text = "Proactive mode",
                color = palette.textSecondary,
                fontSize = 11.sp,
                fontFamily = FontFamily.SansSerif
            )
        }
        StatusCard(snapshot = snapshot, agent = agent, busy = state.busy, onToggle = onToggle)
        ActionRow(snapshot = snapshot, agent = agent, busy = state.busy, onResume = onResume, onPause = onPause, onCheck = onCheck)
        val resumesAt = agent?.policy?.pausedUntil
        if (agent?.state == "paused" && resumesAt != null) {
            Text(
                text = t("Resumes at {time}", mapOf("time" to hourMinute(resumesAt))),
                color = palette.textSecondary,
                fontSize = 11.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp).testTag("resumes-at"),
                fontFamily = FontFamily.SansSerif
            )
        }
        Connections(snapshot = snapshot)
        Activity(agent = agent)
        if (state.failed) {
            val message = t("Could not update proactive mode.")
            val retry = t("Retry")
            Row(
                Modifier
                    .padding(top = 12.dp)
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .testTag("proactive-retry")
                    .clickable(onClick = onRetry)
                    .semantics {
                        liveRegion = LiveRegionMode.Assertive
                        contentDescription = message
                    },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(message, color = ProactiveError, fontSize = 11.sp, fontFamily = FontFamily.SansSerif)
                Text(
                    text = retry,
                    color = ProactiveError,
                    fontSize = 11.sp,
                    textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline,
                    fontFamily = FontFamily.SansSerif
                )
            }
        }
        Footer(agent = agent, onOpenAgent = onOpenAgent, onOpenShell = onOpenShell)
    }
}

@Composable
private fun StatusCard(
    snapshot: ProactiveSnapshot?,
    agent: ProactiveAgentSnapshot?,
    busy: Boolean,
    onToggle: () -> Unit
) {
    val palette = LocalNuumPalette.current
    val stateName = agent?.state ?: if (snapshot == null) null else "disabled"
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(palette.textPrimary.copy(alpha = 0.04f))
            .padding(top = 17.dp)
    ) {
        Row(
            Modifier.padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(
                Modifier
                    .size(6.dp)
                    .background(dotColor(snapshot, stateName, palette.textTertiary), RoundedCornerShape(999.dp))
            )
            Text(
                text = statusSentence(snapshot, stateName),
                color = palette.textSecondary,
                fontSize = 11.sp,
                fontFamily = FontFamily.SansSerif,
                modifier = Modifier.testTag("proactive-status")
            )
        }
        Text(
            text = agent?.name ?: "Nunu",
            color = palette.textPrimary,
            fontSize = 23.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = (-0.6).sp,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 10.dp),
            fontFamily = FontFamily.SansSerif
        )
        Text(
            text = t(
                if (stateName == "paused") {
                    "Your companion will resume after this break."
                } else {
                    "A quieter kind of help, at the right moment."
                }
            ),
            color = palette.textSecondary,
            fontSize = 12.sp,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp),
            fontFamily = FontFamily.SansSerif
        )
        Box(Modifier.fillMaxWidth().height(1.dp).background(palette.borderSubtle))
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = t("Proactive mode"),
                color = palette.textPrimary,
                fontSize = 13.sp,
                fontFamily = FontFamily.SansSerif
            )
            SandSwitch(
                checked = agent?.policy?.enabled == true,
                enabled = !busy && agent != null,
                label = t("Enable proactive mode"),
                onToggle = onToggle,
                modifier = Modifier.testTag("proactive-switch")
            )
        }
    }
}

@Composable
private fun ActionRow(
    snapshot: ProactiveSnapshot?,
    agent: ProactiveAgentSnapshot?,
    busy: Boolean,
    onResume: () -> Unit,
    onPause: (Long) -> Unit,
    onCheck: () -> Unit
) {
    val paused = agent?.state == "paused"
    val enabled = agent?.policy?.enabled == true
    val checkEnabled = snapshot != null && enabled && !paused && agent?.state != "checking" && !busy
    Row(
        Modifier.fillMaxWidth().padding(top = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(Modifier.weight(1f)) {
            if (paused) {
                SecondaryButton(
                    label = t("Resume now"),
                    enabled = !busy,
                    onClick = onResume,
                    modifier = Modifier.testTag("resume-now")
                )
            } else {
                SettingsSelect(
                    label = t("Pause proactive mode"),
                    valueLabel = t("Pause…"),
                    enabled = enabled && !busy,
                    options = listOf(
                        PAUSE_30_MINUTES_MS.toString() to t("For 30 minutes"),
                        PAUSE_1_HOUR_MS.toString() to t("For 1 hour")
                    ),
                    selectedValue = null,
                    onSelect = { onPause(it.toLong()) },
                    modifier = Modifier.fillMaxWidth(),
                    testTag = "pause-select"
                )
            }
        }
        Box(Modifier.weight(1f)) {
            SecondaryButton(
                label = t("Check setup"),
                enabled = checkEnabled,
                onClick = onCheck,
                modifier = Modifier.testTag("check-setup")
            )
        }
    }
}

@Composable
private fun SecondaryButton(
    label: String,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val palette = LocalNuumPalette.current
    val shape = RoundedCornerShape(10.dp)
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .border(1.dp, palette.borderSubtle, shape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 7.dp)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = label,
            color = if (enabled) palette.textPrimary else palette.textTertiary,
            fontSize = 12.sp,
            fontFamily = FontFamily.SansSerif
        )
    }
}

@Composable
private fun Connections(snapshot: ProactiveSnapshot?) {
    val palette = LocalNuumPalette.current
    val sources = if (snapshot == null) {
        ConnectionLabel.NotConnected
    } else {
        contextSourcesLabel(snapshot.availableSourceIds)
    }
    val actions = if (snapshot == null) {
        ConnectionLabel.NotConnected
    } else {
        agentActionsLabel(snapshot.actionsAvailable)
    }
    val connections = t("Connections")
    Column(
        Modifier
            .fillMaxWidth()
            .padding(top = 20.dp)
            .semantics { contentDescription = connections }
            .testTag("connections")
    ) {
        ConnectionLine("Context sources", sources, "context-sources-status")
        ConnectionLine("Agent actions", actions, "agent-actions-status")
        Text(
            text = t("Setup is ready. Context collection and autonomous actions are not enabled in this version."),
            color = palette.textTertiary,
            fontSize = 11.sp,
            modifier = Modifier.padding(top = 8.dp),
            fontFamily = FontFamily.SansSerif
        )
    }
}

@Composable
private fun ConnectionLine(labelKey: String, value: ConnectionLabel, tag: String) {
    val palette = LocalNuumPalette.current
    val valueKey = if (value == ConnectionLabel.Available) "Available" else "Not connected"
    Row(
        Modifier.fillMaxWidth().padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(t(labelKey), color = palette.textPrimary, fontSize = 12.sp, fontFamily = FontFamily.SansSerif)
        Text(
            text = t(valueKey),
            color = palette.textSecondary,
            fontSize = 11.sp,
            modifier = Modifier.testTag(tag),
            fontFamily = FontFamily.SansSerif
        )
    }
}

@Composable
private fun Activity(agent: ProactiveAgentSnapshot?) {
    val palette = LocalNuumPalette.current
    Column(Modifier.fillMaxWidth().padding(top = 18.dp, bottom = 18.dp)) {
        Text(
            text = t("Recent activity"),
            color = palette.textSecondary,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            fontFamily = FontFamily.SansSerif
        )
        val items = agent?.activity.orEmpty().take(3)
        if (items.isEmpty()) {
            Text(
                text = t("Activity will appear here when you turn it on."),
                color = palette.textTertiary,
                fontSize = 11.sp,
                modifier = Modifier.padding(top = 8.dp),
                fontFamily = FontFamily.SansSerif
            )
        } else {
            items.forEach { item ->
                ActivityRow(item)
            }
        }
    }
}

@Composable
private fun ActivityRow(item: ProactiveActivity) {
    val palette = LocalNuumPalette.current
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = activityText(item.kind),
            color = palette.textPrimary,
            fontSize = 11.sp,
            modifier = Modifier.weight(1f),
            fontFamily = FontFamily.SansSerif
        )
            Text(
                text = hourMinute(item.at),
            color = palette.textTertiary,
            fontSize = 11.sp,
            fontFamily = FontFamily.SansSerif
        )
    }
}

@Composable
private fun Footer(
    agent: ProactiveAgentSnapshot?,
    onOpenAgent: (String) -> Unit,
    onOpenShell: () -> Unit
) {
    val palette = LocalNuumPalette.current
    val label = t(if (agent != null) "Open Nunu" else "Open Nuum")
    Box(
        Modifier
            .fillMaxWidth()
            .padding(top = 12.dp)
            .height(1.dp)
            .background(palette.borderSubtle)
    )
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .testTag(if (agent != null) "open-nunu" else "open-nuum")
            .clickable {
                if (agent != null) onOpenAgent(agent.agentId) else onOpenShell()
            }
            .semantics { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(label, color = palette.textPrimary, fontSize = 12.sp, fontFamily = FontFamily.SansSerif)
        SettingsIcon("chevron-right", palette.textPrimary, Modifier.size(12.dp))
    }
}

@Composable
private fun statusSentence(snapshot: ProactiveSnapshot?, stateName: String?): String {
    if (snapshot == null) return t("Connecting to Nuum…")
    val key = when (stateName) {
        "disabled" -> "Proactive is off"
        "paused" -> "Taking a pause"
        "waiting-context" -> "Waiting for context"
        "ready" -> "Ready to check"
        "checking" -> "Checking context"
        "error" -> "Check needs attention"
        else -> "Proactive is off"
    }
    return t(key)
}

@Composable
private fun activityText(kind: String): String {
    val key = when (kind) {
        "enabled" -> "Proactive enabled"
        "disabled" -> "Proactive disabled"
        "paused" -> "Paused"
        "resumed" -> "Resumed"
        "configured" -> "Configuration updated"
        "waiting-context" -> "No context sources connected"
        "context-ready" -> "Context ready; actions not connected"
        "no-change" -> "No new context"
        "error" -> "Context check failed"
        else -> null
    }
    return if (key == null) kind else t(key)
}

private fun dotColor(snapshot: ProactiveSnapshot?, stateName: String?, tertiary: Color): Color {
    if (snapshot == null) return tertiary
    return when (stateName) {
        "paused" -> Color(0xFFAA8A52)
        "waiting-context", "ready" -> Color(0xFF80856B)
        "error" -> Color(0xFFBD615A)
        else -> tertiary
    }
}

private val ProactiveError = Color(0xFFB85850)

@Composable
private fun hourMinute(epochMillis: Long): String =
    formatHourMinute(epochMillis, LocalSettingsLanguage.current)

internal fun formatHourMinute(
    epochMillis: Long,
    language: com.nuum.contracts.Language = com.nuum.contracts.Language.EN,
    zone: ZoneId = ZoneId.systemDefault()
): String {
    val locale = when (language) {
        com.nuum.contracts.Language.ZH_CN -> Locale.forLanguageTag("zh-CN")
        com.nuum.contracts.Language.EN -> Locale.ENGLISH
    }
    return DateTimeFormatter.ofPattern("HH:mm", locale)
        .withZone(zone)
        .format(Instant.ofEpochMilli(epochMillis))
}
