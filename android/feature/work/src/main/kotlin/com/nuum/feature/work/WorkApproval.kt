package com.nuum.feature.work

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nuum.contracts.AgentView
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.ToolResolution
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
internal fun ApprovalList(
    approvals: List<PendingApproval>,
    members: List<AgentView>,
    onDecide: suspend (PendingApproval, ToolResolution) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (approvals.isEmpty()) return
    Column(
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        approvals.forEach { approval ->
            val name = members.find { it.profile.id == approval.agentId }?.profile?.name
                ?: stringResource(R.string.work_agent)
            ApprovalBar(approval = approval, agentName = name, onDecide = { onDecide(approval, it) })
        }
    }
}

@Composable
private fun ApprovalBar(
    approval: PendingApproval,
    agentName: String,
    onDecide: suspend (ToolResolution) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var detailsOpen by remember { mutableStateOf(false) }
    val action = actionLabel(approval.action)
    val title = approval.justification ?: stringResource(R.string.work_allow_action, action)
    val dynamic = stringResource(R.string.work_dynamic_commands)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(WorkColors.bgElevated, WorkRadius2xl)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = "$agentName · $title",
            color = WorkColors.textPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
        )
        if (approval.action != LocalToolAction.RUN_COMMAND) {
            Text(
                text = approval.target.lineSequence().firstOrNull().orEmpty(),
                color = WorkColors.textTertiary,
                fontSize = 12.sp,
                fontFamily = FontFamily.Monospace,
            )
        }
        Text(
            text = stringResource(R.string.work_execution_details),
            color = WorkColors.textSecondary,
            fontSize = 12.sp,
            modifier = Modifier.clickable { detailsOpen = !detailsOpen },
        )
        if (detailsOpen) {
            Text(
                text = approval.details ?: approval.target,
                color = WorkColors.textTertiary,
                fontSize = 12.sp,
                fontFamily = FontFamily.Monospace,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            DecisionButton(
                text = stringResource(R.string.work_deny),
                enabled = !busy,
                foreground = WorkColors.textSecondary,
                background = androidx.compose.ui.graphics.Color.Transparent,
                onClick = {
                    scope.launch {
                        busy = true
                        error = null
                        try {
                            onDecide(ToolResolution.DENY)
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (failure: Exception) {
                            error = failure.message
                        } finally {
                            busy = false
                        }
                    }
                },
            )
            DecisionButton(
                text = stringResource(R.string.work_allow_once),
                enabled = !busy,
                foreground = WorkColors.textPrimary,
                background = WorkColors.fillSecondary,
                onClick = {
                    scope.launch {
                        busy = true
                        error = null
                        try {
                            onDecide(ToolResolution.ONCE)
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (failure: Exception) {
                            error = failure.message
                        } finally {
                            busy = false
                        }
                    }
                },
            )
            DecisionButton(
                text = stringResource(R.string.work_always_allow),
                enabled = !busy && approval.allowAlways,
                foreground = WorkColors.textOnPrimary,
                background = WorkColors.fillPrimary,
                hint = if (!approval.allowAlways) dynamic else null,
                onClick = {
                    scope.launch {
                        busy = true
                        error = null
                        try {
                            onDecide(ToolResolution.ALWAYS)
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (failure: Exception) {
                            error = failure.message
                        } finally {
                            busy = false
                        }
                    }
                },
            )
        }
        if (error != null) WorkAlert(error!!)
    }
}

@Composable
private fun DecisionButton(
    text: String,
    enabled: Boolean,
    foreground: androidx.compose.ui.graphics.Color,
    background: androidx.compose.ui.graphics.Color,
    onClick: () -> Unit,
    hint: String? = null,
) {
    Text(
        text = text,
        color = foreground,
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        modifier = Modifier
            .background(background, WorkRadiusLg)
            .semantics {
                role = Role.Button
                if (hint != null) {
                    contentDescription = text
                    stateDescription = hint
                }
            }
            .clickable(enabled = enabled, onClick = onClick, role = Role.Button)
            .padding(horizontal = 10.dp, vertical = 6.dp),
    )
}

@Composable
internal fun actionLabel(action: LocalToolAction): String = stringResource(
    when (action) {
        LocalToolAction.READ_FILE -> R.string.work_action_read_file
        LocalToolAction.LIST_DIRECTORY -> R.string.work_action_list_directory
        LocalToolAction.WRITE_FILE -> R.string.work_action_write_file
        LocalToolAction.RUN_COMMAND -> R.string.work_action_run_command
        LocalToolAction.NETWORK -> R.string.work_action_network
    },
)
