package com.nuum.feature.shell

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.nuum.feature.shell.chrome.Glyph
import com.nuum.feature.shell.chrome.IconHit
import com.nuum.feature.shell.chrome.SandText
import com.nuum.feature.shell.create.CreateNunuLayer
import com.nuum.feature.shell.model.ShellModel
import com.nuum.feature.shell.motion.isReducedMotion
import com.nuum.feature.shell.profile.ProfilePane
import com.nuum.feature.shell.profile.profileWidthModifier
import com.nuum.feature.shell.sidebar.SidebarOverlays
import com.nuum.feature.shell.sidebar.SidebarPane
import com.nuum.feature.shell.theme.LocalCopy
import com.nuum.feature.shell.theme.LocalSand
import com.nuum.feature.shell.theme.SandTheme

@Composable
internal fun NuumShellScaffold(
    ports: ShellPorts,
    content: @Composable (ShellSelection) -> Unit
) {
    val scope = rememberCoroutineScope()
    val model = remember(ports) { ShellModel(ports, scope) }
    LaunchedEffect(model) { model.activate() }
    SandTheme(theme = model.theme, language = model.language) {
        BackHandler(enabled = model.canInterceptBack) { model.back() }
        val sand = LocalSand.current
        BoxWithConstraints(
            Modifier
                .fillMaxSize()
                .background(sand.bgEditor)
                .windowInsetsPadding(WindowInsets.safeDrawing)
        ) {
            val wide = maxWidth >= 840.dp
            val windowDp = maxWidth.value.toInt().coerceAtLeast(1)
            SideEffect { model.compact = !wide }
            LaunchedEffect(wide) {
                if (wide) {
                    model.drawerOpen = false
                } else if (
                    model.selectedAgentId == null &&
                    model.selectedWorkId == null &&
                    !model.createOpen &&
                    !model.showSettings
                ) {
                    model.drawerOpen = true
                }
            }
            val selection = ShellSelection(
                agentId = model.selectedAgentId,
                workId = model.selectedWorkId,
                showSettings = model.showSettings,
                createWork = model.createWork,
                dismissOverlay = { model.dismissOverlay() },
                openProfile = { model.openProfile(it) }
            )
            Row(Modifier.fillMaxSize()) {
                if (wide) {
                    SidebarPane(model, showResize = true, windowDp = windowDp)
                }
                Row(Modifier.weight(1f).fillMaxHeight()) {
                    Column(Modifier.weight(1f).fillMaxHeight()) {
                        if (!wide && model.profileId == null && !model.createOpen) {
                            PhoneBar(model)
                        }
                        Box(Modifier.weight(1f).fillMaxWidth()) { content(selection) }
                    }
                    if (wide && model.profileId != null) {
                        val agent = model.agents.find { it.profile.id == model.profileId }
                        ProfilePane(model, agent, profileWidthModifier())
                    }
                }
            }
            if (!wide) {
                Drawer(model, maxWidth)
            }
            if (!wide && model.profileId != null) {
                val agent = model.agents.find { it.profile.id == model.profileId }
                ProfilePane(model, agent, Modifier.fillMaxSize())
            }
            if (model.createOpen) {
                CreateNunuLayer(model) { if (!model.creating) model.closeCreate() }
            }
            SidebarOverlays(model)
        }
    }
}

@Composable
private fun PhoneBar(model: ShellModel) {
    val copy = LocalCopy.current
    val sand = LocalSand.current
    val agent = model.agents.find { it.profile.id == model.selectedAgentId }
    val work = model.works.find { it.profile.id == model.selectedWorkId }
    Row(
        Modifier.fillMaxWidth().height(56.dp).background(sand.bgChrome),
        verticalAlignment = Alignment.CenterVertically
    ) {
        IconHit(copy.t("Agents"), Glyph.Sidebar, onClick = { model.drawerOpen = true })
        when {
            agent != null -> SandText(
                agent.profile.name,
                sand.textPrimary,
                14,
                Modifier
                    .weight(1f)
                    .clickable { model.openProfile(agent.profile.id) }
                    .semantics { contentDescription = copy.t("Open {name} profile", "name" to agent.profile.name) },
                maxLines = 1
            )
            work != null -> SandText(work.profile.name, sand.textPrimary, 14, Modifier.weight(1f), maxLines = 1)
            else -> Box(Modifier.weight(1f))
        }
    }
}

@Composable
private fun Drawer(model: ShellModel, window: androidx.compose.ui.unit.Dp) {
    val reduced = isReducedMotion()
    val sand = LocalSand.current
    val drawerWidth = minOf(360.dp, window * 0.86f)
    val shift = remember { Animatable(if (reduced || model.drawerOpen) 0f else -1f) }
    LaunchedEffect(model.drawerOpen, reduced) {
        val target = if (model.drawerOpen) 0f else -1f
        if (reduced) shift.snapTo(target) else shift.animateTo(target, tween(300))
    }
    if (!model.drawerOpen && shift.value <= -0.99f) return
    Box(Modifier.fillMaxSize()) {
        if (model.drawerOpen) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(sand.scrim.copy(alpha = sand.scrim.alpha * (1f + shift.value)))
                    .clickable { model.drawerOpen = false }
            )
        }
        Box(
            Modifier
                .width(drawerWidth)
                .fillMaxHeight()
                .graphicsLayer { translationX = shift.value * drawerWidth.toPx() }
        ) {
            SidebarPane(model, Modifier.fillMaxHeight(), showResize = false)
        }
    }
}
