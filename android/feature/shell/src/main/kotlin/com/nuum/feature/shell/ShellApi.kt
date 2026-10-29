package com.nuum.feature.shell

import androidx.compose.runtime.Composable
import com.nuum.contracts.AgentPort
import com.nuum.contracts.DesktopPort
import com.nuum.contracts.SettingsPort
import com.nuum.contracts.WorkPort

/**
 * Narrow ports the navigation shell is allowed to call.
 * Work is listed for the sidebar; member moves go through [WorkPort] only as a drop target.
 */
data class ShellPorts(
    val agents: AgentPort,
    val settings: SettingsPort,
    val desktop: DesktopPort,
    val work: WorkPort
)

/**
 * What the center slot should show. The shell does not compose conversation, NunuBar, or settings.
 *
 * Priority for the host activity: [createWork], then [showSettings], then [workId], then [agentId].
 * [dismissOverlay] clears the settings and work-creation flags. [openProfile] opens the identity
 * column owned by this module.
 */
class ShellSelection(
    val agentId: String?,
    val workId: String?,
    val showSettings: Boolean,
    val createWork: Boolean,
    val dismissOverlay: () -> Unit,
    val openProfile: (agentId: String) -> Unit
)

/**
 * Single-activity chrome: sidebar or drawer, theme, create-Nunu, 2D unbox, and profile.
 * [content] is the center column (`:app` fills it with conversation or NunuBar).
 */
@Composable
fun NuumShell(
    ports: ShellPorts,
    content: @Composable (ShellSelection) -> Unit
) {
    NuumShellScaffold(ports, content)
}
