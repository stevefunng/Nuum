package com.nuum.feature.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.nuum.contracts.CommandGrant
import com.nuum.contracts.CommandPermission
import com.nuum.contracts.ExecutionPreferences
import com.nuum.contracts.NetworkGrant
import com.nuum.feature.shell.chrome.AlertLine
import com.nuum.feature.shell.chrome.SandText
import com.nuum.feature.shell.theme.LocalCopy
import com.nuum.feature.shell.theme.LocalSand

/**
 * Execution preferences shared by the profile column.
 * Saving is the caller's job and must go through [com.nuum.contracts.AgentPort].
 * Settings must not copy this form. `:feature:settings` cannot depend on this module;
 * `:app` places the same composable if a second surface needs it.
 *
 * `externalGrants` are not on the contract [ExecutionPreferences]. When that field
 * exists, add a revoke row here instead of a second form.
 */
@Composable
fun ExecutionPreferencesForm(
    execution: ExecutionPreferences?,
    projectRoot: String?,
    saving: Boolean,
    error: String?,
    onCommands: (CommandPermission) -> Unit,
    onRevokeCommand: (CommandGrant) -> Unit,
    onRevokeNetwork: (NetworkGrant) -> Unit,
    onOpenFolder: () -> Unit,
    modifier: Modifier = Modifier
) {
    val copy = LocalCopy.current
    val sand = LocalSand.current
    val commands = execution?.commands ?: CommandPermission.ASK
    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .semantics { contentDescription = copy.t("Workspace and permissions") },
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        SandText(copy.t("Workspace and permissions"), sand.textPrimary, 13)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            SandText(copy.t("Personal workspace"), sand.textPrimary, 13)
            ChoiceChip(copy.t("Open folder"), !saving, onOpenFolder)
        }
        SandText(
            text = if (projectRoot.isNullOrBlank()) copy.t("No workspace selected") else projectRoot,
            color = sand.textSecondary,
            size = 12,
            family = FontFamily.Monospace
        )
        SandText(copy.t("Room tasks use the shared room workspace."), sand.textSecondary, 12)
        SandText(copy.t("Command execution"), sand.textPrimary, 13, modifier = Modifier.semantics {
            contentDescription = copy.t("Command execution")
        })
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val allow = commands != CommandPermission.NEVER
            ChoiceChip(
                label = copy.t("Allow inside sandbox"),
                enabled = !saving,
                selected = allow,
                onClick = { onCommands(CommandPermission.ASK) }
            )
            ChoiceChip(
                label = copy.t("Deny"),
                enabled = !saving,
                selected = !allow,
                onClick = { onCommands(CommandPermission.NEVER) }
            )
        }
        SandText(
            copy.t("Permission applies only to this Nunu and workspace."),
            sand.textTertiary,
            12
        )
        val grants = execution?.commandGrants.orEmpty()
        if (grants.isNotEmpty()) {
            SandText(copy.t("Remembered commands ({count})", "count" to grants.size), sand.textPrimary, 13)
            grants.forEach { grant ->
                GrantRow(
                    title = grant.command,
                    detail = if (execution != null && grant.workspaceId == execution.workspaceId) {
                        copy.t("Personal workspace")
                    } else {
                        copy.t("Former room")
                    },
                    enabled = !saving,
                    onRevoke = { onRevokeCommand(grant) }
                )
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            SandText(copy.t("Tool network"), sand.textPrimary, 13)
            SandText(copy.t("Denied by default"), sand.textSecondary, 12)
        }
        val network = execution?.networkGrants.orEmpty()
        if (network.isEmpty()) {
            SandText(copy.t("Network access requires your approval."), sand.textSecondary, 12)
        } else {
            network.forEach { grant ->
                GrantRow(
                    title = grant.target,
                    detail = if (execution != null && grant.workspaceId == execution.workspaceId) {
                        copy.t("Personal workspace")
                    } else {
                        copy.t("Former room")
                    },
                    enabled = !saving,
                    onRevoke = { onRevokeNetwork(grant) }
                )
            }
        }
        error?.let { AlertLine(copy.t(it)) }
    }
}

@Composable
private fun ChoiceChip(
    label: String,
    enabled: Boolean,
    onClick: () -> Unit,
    selected: Boolean = false
) {
    val sand = LocalSand.current
    SandText(
        text = label,
        color = if (selected) sand.textOnPrimary else sand.textPrimary,
        size = 12,
        modifier = Modifier
            .background(
                if (selected) sand.fillPrimary else sand.fillSecondary,
                RoundedCornerShape(999.dp)
            )
            .semantics {
                contentDescription = label
                this.selected = selected
            }
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp)
    )
}

@Composable
private fun GrantRow(title: String, detail: String, enabled: Boolean, onRevoke: () -> Unit) {
    val copy = LocalCopy.current
    val sand = LocalSand.current
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            SandText(title, sand.textPrimary, 13, maxLines = 2)
            SandText(detail, sand.textTertiary, 11)
        }
        SandText(
            copy.t("Revoke"),
            sand.textDanger,
            12,
            modifier = Modifier
                .semantics { contentDescription = copy.t("Revoke") + " " + title }
                .clickable(enabled = enabled, onClick = onRevoke)
                .padding(8.dp)
        )
    }
}
