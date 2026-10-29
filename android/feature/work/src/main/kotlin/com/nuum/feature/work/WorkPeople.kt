package com.nuum.feature.work

import android.content.ClipDescription
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.draganddrop.dragAndDropTarget
import androidx.compose.ui.draganddrop.DragAndDropEvent
import androidx.compose.ui.draganddrop.DragAndDropTarget
import androidx.compose.ui.draganddrop.toAndroidDragEvent
import com.nuum.contracts.AgentStatus
import com.nuum.contracts.AgentView
import com.nuum.contracts.WorkCatalog
import com.nuum.contracts.WorkCatalogEntry
import com.nuum.contracts.WorkSnapshot

internal const val WORK_AGENT_DRAG_PREFIX = "nuum-agent:"

@Composable
internal fun CapabilitySection(
    catalog: WorkCatalog,
    onAdd: () -> Unit,
    onRemove: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = stringResource(R.string.work_capabilities),
                    color = WorkColors.textPrimary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = catalog.entries.size.toString(),
                    color = WorkColors.textTertiary,
                    fontSize = 12.sp,
                )
            }
            WorkIconButton(label = stringResource(R.string.work_add_capability), onClick = onAdd) {
                Text("+", color = WorkColors.textPrimary, fontSize = 16.sp)
            }
        }
        catalog.entries.forEach { entry ->
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(entry.name, color = WorkColors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    Text(catalogKindLabel(entry), color = WorkColors.textTertiary, fontSize = 11.sp)
                }
                val remove = stringResource(R.string.work_remove_name, entry.name)
                WorkIconButton(label = remove, onClick = { onRemove(entry.id) }) {
                    Text("×", color = WorkColors.textSecondary, fontSize = 14.sp)
                }
            }
        }
    }
}

@Composable
private fun catalogKindLabel(entry: WorkCatalogEntry): String = stringResource(
    when (entry) {
        is WorkCatalogEntry.LocalTool -> R.string.work_local_tool
        is WorkCatalogEntry.Skill -> R.string.work_skill
        is WorkCatalogEntry.Cli -> R.string.work_cli
        is WorkCatalogEntry.Knowledge -> R.string.work_knowledge
    },
)

@Composable
internal fun MemberSection(
    workId: String,
    members: List<AgentView>,
    snapshot: WorkSnapshot,
    pendingAgentIds: Set<String>,
    onDetach: (agentId: String, revision: Int) -> Unit,
    onAttach: (agentId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var bounds by remember { mutableStateOf<Rect?>(null) }
    var dragging by remember { mutableStateOf(false) }
    var outside by remember { mutableStateOf(false) }
    var openId by remember { mutableStateOf<String?>(null) }
    val dropTarget = remember(onAttach) {
        object : DragAndDropTarget {
            override fun onDrop(event: DragAndDropEvent): Boolean {
                val text = event.toAndroidDragEvent().clipData?.getItemAt(0)?.text?.toString().orEmpty()
                val agentId = text.removePrefix(WORK_AGENT_DRAG_PREFIX).trim()
                if (agentId.isEmpty()) return false
                onAttach(agentId)
                return true
            }
        }
    }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .onGloballyPositioned { bounds = it.boundsInWindow() }
            .dragAndDropTarget(
                shouldStartDragAndDrop = { event ->
                    event.toAndroidDragEvent().clipDescription?.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) == true
                },
                target = dropTarget,
            )
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = stringResource(R.string.work_agents),
                color = WorkColors.textPrimary,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(members.size.toString(), color = WorkColors.textTertiary, fontSize = 12.sp)
        }
        members.forEach { member ->
            val open = openId == member.profile.id
            var origin by remember(member.profile.id) { mutableStateOf(Offset.Zero) }
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .onGloballyPositioned { origin = it.boundsInWindow().topLeft }
                        .pointerInput(member.profile.id, bounds) {
                            detectDragGesturesAfterLongPress(
                                onDragStart = {
                                    dragging = true
                                    outside = false
                                },
                                onDragCancel = {
                                    dragging = false
                                    outside = false
                                },
                                onDragEnd = {
                                    if (outside) onDetach(member.profile.id, membershipRevision(member, workId))
                                    dragging = false
                                    outside = false
                                },
                                onDrag = { change, _ ->
                                    val window = bounds
                                    val point = origin + change.position
                                    outside = window != null && !window.contains(point)
                                },
                            )
                        },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Row(
                        modifier = Modifier
                            .weight(1f)
                            .clickable {
                                openId = if (open) null else member.profile.id
                            }
                            .padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        MemberAvatar(
                            member = member,
                            waiting = member.profile.id in pendingAgentIds,
                        )
                        Text(member.profile.name, color = WorkColors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    }
                    val remove = stringResource(R.string.work_remove_name, member.profile.name)
                    WorkIconButton(
                        label = remove,
                        onClick = { onDetach(member.profile.id, membershipRevision(member, workId)) },
                    ) {
                        Text("×", color = WorkColors.textSecondary, fontSize = 14.sp)
                    }
                }
                if (open) {
                    val status = statusText(memberActivity(member, snapshot))
                    val label = stringResource(R.string.work_status_of, member.profile.name)
                    Text(
                        text = status,
                        color = WorkColors.textSecondary,
                        fontSize = 12.sp,
                        modifier = Modifier
                            .padding(start = 42.dp, bottom = 6.dp)
                            .semantics { contentDescription = label },
                    )
                }
            }
        }
        val hint = when {
            dragging && outside -> stringResource(R.string.work_drop_out)
            dragging -> stringResource(R.string.work_drop_active)
            members.isEmpty() -> stringResource(R.string.work_drop_idle)
            else -> null
        }
        if (hint != null) {
            Text(
                text = hint,
                color = WorkColors.textTertiary,
                fontSize = 12.sp,
                modifier = Modifier.padding(vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun statusText(activity: MemberActivity): String = when (activity) {
    MemberActivity.Idle -> stringResource(R.string.work_idle)
    MemberActivity.Error -> stringResource(R.string.work_run_failed)
    MemberActivity.Discussion -> stringResource(R.string.work_discussing)
    MemberActivity.Elsewhere -> stringResource(R.string.work_elsewhere)
    is MemberActivity.Card -> {
        val base = stringResource(R.string.work_working_on_card)
        if (activity.title.isNullOrBlank()) base else "$base：${activity.title}"
    }
}

@Composable
internal fun MemberAvatar(member: AgentView, waiting: Boolean, size: Int = 34) {
    val dot = when {
        waiting -> WorkColors.warningFill
        member.runtime.status == AgentStatus.ERROR -> WorkColors.dangerFill
        member.runtime.status == AgentStatus.RUNNING -> WorkColors.accentFill
        else -> Color.Transparent
    }
    Box(modifier = Modifier.size(size.dp)) {
        Box(
            modifier = Modifier
                .size(size.dp)
                .background(avatarColor(member.profile.avatarColor), CircleShape),
        )
        if (dot != Color.Transparent) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .size(8.dp)
                    .background(dot, CircleShape)
                    .border(1.dp, WorkColors.bgEditor, CircleShape),
            )
        }
    }
}
