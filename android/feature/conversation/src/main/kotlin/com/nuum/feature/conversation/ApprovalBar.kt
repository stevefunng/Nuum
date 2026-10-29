package com.nuum.feature.conversation

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.ToolResolution

@Composable
internal fun ApprovalBar(
    pending: PendingTool,
    busy: Boolean,
    error: String?,
    onDecide: (ToolResolution) -> Unit,
    modifier: Modifier = Modifier,
    agentName: String? = null
) {
    val action = actionLabel(pending.action)
    val titleCore = pending.justification?.takeIf { it.isNotBlank() }
        ?: copy(R.string.allow_action, "action" to action)
    val title = if (agentName.isNullOrBlank()) titleCore else "$agentName · $titleCore"
    val dynamic = copy(R.string.dynamic_commands)
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val narrow = maxWidth < 840.dp
        val shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp)
        Column(
            Modifier
                .widthIn(max = 640.dp)
                .fillMaxWidth()
                .background(Sand.bgElevated, shape)
                .border(1.dp, Sand.borderSubtle, shape)
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (narrow) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ApprovalCopy(pending, title)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        ApprovalActions(pending, busy, dynamic, onDecide)
                    }
                }
            } else {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        ApprovalCopy(pending, title)
                    }
                    ApprovalActions(pending, busy, dynamic, onDecide)
                }
            }
            if (!error.isNullOrBlank()) {
                Text(
                    error,
                    color = Sand.textDanger,
                    fontSize = 12.sp,
                    modifier = Modifier.semantics {
                        liveRegion = LiveRegionMode.Assertive
                        contentDescription = error
                    }
                )
            }
        }
    }
}

@Composable
private fun ApprovalCopy(pending: PendingTool, title: String) {
    var open by remember(pending.toolCallId) { mutableStateOf(false) }
    Text(title, color = Sand.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    if (pending.action != LocalToolAction.RUN_COMMAND) {
        Text(
            pending.target.lineSequence().firstOrNull().orEmpty(),
            color = Sand.textTertiary,
            fontSize = 12.sp,
            fontFamily = FontFamily.Monospace
        )
    }
    Text(
        copy(R.string.execution_details),
        color = Sand.textSecondary,
        fontSize = 12.sp,
        modifier = Modifier
            .clickable { open = !open }
            .semantics { role = Role.Button }
    )
    if (open) {
        Text(
            pending.details ?: pending.target,
            color = Sand.textTertiary,
            fontSize = 12.sp,
            fontFamily = FontFamily.Monospace
        )
    }
}

@Composable
private fun ApprovalActions(
    pending: PendingTool,
    busy: Boolean,
    dynamicHint: String,
    onDecide: (ToolResolution) -> Unit
) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        DecisionButton(
            label = copy(R.string.deny),
            enabled = !busy,
            background = Color.Transparent,
            content = Sand.textSecondary,
            pressedBackground = Sand.fillDangerSubtle,
            pressedContent = Sand.textDanger,
            onClick = { onDecide(ToolResolution.DENY) }
        )
        DecisionButton(
            label = copy(R.string.allow_once),
            enabled = !busy,
            background = Sand.fillSecondary,
            content = Sand.textPrimary,
            pressedBackground = Sand.fillGhostHover,
            pressedContent = Sand.textPrimary,
            onClick = { onDecide(ToolResolution.ONCE) }
        )
        DecisionButton(
            label = copy(R.string.always_allow),
            enabled = !busy && pending.alwaysEnabled,
            background = Sand.fillPrimary,
            content = Sand.textOnPrimary,
            pressedBackground = Sand.fillPrimaryHover,
            pressedContent = Sand.textOnPrimary,
            hint = if (!pending.alwaysEnabled) dynamicHint else null,
            onClick = { onDecide(ToolResolution.ALWAYS) }
        )
    }
}

@Composable
private fun DecisionButton(
    label: String,
    enabled: Boolean,
    background: Color,
    content: Color,
    pressedBackground: Color,
    pressedContent: Color,
    onClick: () -> Unit,
    hint: String? = null
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val bg = if (pressed && enabled) pressedBackground else background
    val fg = if (pressed && enabled) pressedContent else content
    Box(
        modifier = Modifier
            .heightIn(min = 48.dp)
            .clickable(
                interactionSource = interaction,
                indication = null,
                enabled = enabled,
                onClick = onClick
            )
            .semantics {
                role = Role.Button
                if (hint != null) stateDescription = hint
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            Modifier
                .height(28.dp)
                .background(bg, androidx.compose.foundation.shape.RoundedCornerShape(10.dp))
                .padding(horizontal = 12.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(label, color = fg, fontSize = 12.sp, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
internal fun actionLabel(action: LocalToolAction): String = when (action) {
    LocalToolAction.READ_FILE -> copy(R.string.action_read_file)
    LocalToolAction.LIST_DIRECTORY -> copy(R.string.action_list_directory)
    LocalToolAction.WRITE_FILE -> copy(R.string.action_write_file)
    LocalToolAction.RUN_COMMAND -> copy(R.string.action_run_command)
    LocalToolAction.NETWORK -> copy(R.string.action_network)
}
