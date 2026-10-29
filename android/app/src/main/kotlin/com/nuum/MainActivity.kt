package com.nuum

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.nuum.contracts.HostEvent
import com.nuum.contracts.PublicSettings
import com.nuum.contracts.SettingsPort
import com.nuum.contracts.ThemePreference
import com.nuum.feature.conversation.ConversationScreen
import com.nuum.feature.settings.NuumLanguage
import com.nuum.feature.settings.NuumTheme
import com.nuum.feature.settings.ProactiveScreen
import com.nuum.feature.settings.SettingsScreen
import com.nuum.feature.shell.NuumShell
import com.nuum.feature.shell.ShellSelection
import com.nuum.feature.work.WorkCreation
import com.nuum.feature.work.WorkScreen
import com.nuum.graph.AppGraph
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val graph = (application as NuumApplication).graph
        graph.desktop.attach(this)
        setContent { NuumHost(graph) }
    }
}

@Composable
private fun NuumHost(graph: AppGraph) {
    val settings = rememberPublicSettings(graph.settingsPort)
    val systemDark = isSystemInDarkTheme()
    NuumTheme(preference = settings?.theme) {
        NuumLanguage(language = settings?.language) {
            NuumShell(ports = graph.shellPorts) { selection ->
                CenterSlot(
                    graph = graph,
                    selection = selection,
                    dark = conversationDark(settings?.theme, systemDark)
                )
            }
        }
    }
}

@Composable
private fun CenterSlot(
    graph: AppGraph,
    selection: ShellSelection,
    dark: Boolean
) {
    var showProactive by remember { mutableStateOf(false) }
    LaunchedEffect(selection.showSettings) {
        if (!selection.showSettings) showProactive = false
    }
    val workId = selection.workId
    val agentId = selection.agentId
    when {
        selection.createWork -> WorkCreation(
            ports = graph.workPorts,
            canCancel = agentId != null || workId != null,
            onCancel = selection.dismissOverlay,
            onCreated = { selection.dismissOverlay() },
            modifier = Modifier.fillMaxSize()
        )
        selection.showSettings && showProactive -> ProactiveScreen(
            dependencies = graph.settingsDependencies,
            onBack = { showProactive = false },
            onOpenAgent = { id ->
                showProactive = false
                selection.dismissOverlay()
                selection.openProfile(id)
            },
            onOpenShell = {
                showProactive = false
                selection.dismissOverlay()
            },
            modifier = Modifier.fillMaxSize()
        )
        selection.showSettings -> SettingsScreen(
            dependencies = graph.settingsDependencies,
            onClose = selection.dismissOverlay,
            onOpenProactive = { showProactive = true },
            modifier = Modifier.fillMaxSize()
        )
        workId != null -> WorkScreen(
            workId = workId,
            ports = graph.workPorts,
            modifier = Modifier.fillMaxSize()
        )
        agentId != null -> ConversationScreen(
            agentId = agentId,
            ports = graph.conversationPorts,
            onOpenProfile = { selection.openProfile(agentId) },
            dark = dark,
            modifier = Modifier.fillMaxSize()
        )
        else -> Box(Modifier.fillMaxSize())
    }
}

@Composable
private fun rememberPublicSettings(port: SettingsPort): PublicSettings? {
    var settings by remember { mutableStateOf<PublicSettings?>(null) }
    LaunchedEffect(port) {
        val pending = mutableListOf<PublicSettings>()
        var ready = false
        launch {
            port.events.collect { event ->
                if (event is HostEvent.SettingsUpdated) {
                    if (ready) settings = event.settings else pending += event.settings
                }
            }
        }
        val loaded = runCatching { port.get() }.getOrNull()
        settings = pending.lastOrNull() ?: loaded
        ready = true
    }
    return settings
}

private fun conversationDark(preference: ThemePreference?, systemDark: Boolean): Boolean = when (preference) {
    null, ThemePreference.DARK -> true
    ThemePreference.LIGHT -> false
    ThemePreference.SYSTEM -> systemDark
}
