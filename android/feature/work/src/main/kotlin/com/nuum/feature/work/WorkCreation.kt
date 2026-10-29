package com.nuum.feature.work

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nuum.contracts.WorkCreateParams
import com.nuum.contracts.WorkKind
import com.nuum.contracts.WorkProfile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
fun WorkCreation(
    ports: WorkPorts,
    canCancel: Boolean,
    onCancel: () -> Unit,
    onCreated: (WorkProfile) -> Unit,
    modifier: Modifier = Modifier,
) {
    var kind by remember { mutableStateOf(WorkKind.WORK) }
    var name by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Box(
        modifier = modifier.fillMaxSize().background(WorkColors.bgEditor),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 520.dp)
                .fillMaxWidth()
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = stringResource(R.string.work_place_for_job),
                color = WorkColors.textTertiary,
                fontSize = 12.sp,
            )
            Text(
                text = stringResource(R.string.work_create_title),
                color = WorkColors.textPrimary,
                fontSize = 22.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = stringResource(R.string.work_create_body),
                color = WorkColors.textSecondary,
                fontSize = 14.sp,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                WorkTextButton(
                    text = stringResource(R.string.work_local_room),
                    selected = kind == WorkKind.ROOM,
                    enabled = !busy,
                    onClick = { kind = WorkKind.ROOM },
                )
                WorkTextButton(
                    text = "NunuBar",
                    selected = kind == WorkKind.WORK,
                    enabled = !busy,
                    primary = kind == WorkKind.WORK,
                    onClick = { kind = WorkKind.WORK },
                )
            }
            Text(stringResource(R.string.work_name), color = WorkColors.textSecondary, fontSize = 12.sp)
            WorkInput(
                value = name,
                onValueChange = { name = it },
                placeholder = stringResource(R.string.work_name_placeholder),
                label = stringResource(R.string.work_name),
                enabled = !busy,
                tag = "work-create-name",
            )
            if (error != null) WorkAlert(error!!)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End), modifier = Modifier.fillMaxWidth()) {
                if (canCancel) {
                    WorkTextButton(
                        text = stringResource(R.string.work_cancel),
                        enabled = !busy,
                        onClick = onCancel,
                    )
                }
                WorkTextButton(
                    text = stringResource(R.string.work_create_submit),
                    primary = true,
                    enabled = !busy && name.isNotBlank(),
                    onClick = {
                        val trimmed = name.trim()
                        if (trimmed.isEmpty() || busy) return@WorkTextButton
                        scope.launch {
                            busy = true
                            error = null
                            try {
                                val profile = ports.work.create(WorkCreateParams(name = trimmed, kind = kind))
                                onCreated(profile)
                            } catch (cancelled: CancellationException) {
                                throw cancelled
                            } catch (failure: Exception) {
                                error = failure.message
                                busy = false
                            }
                        }
                    },
                )
            }
        }
    }
}
