package com.nuum.feature.work

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.collectAsState
import com.nuum.contracts.WorkKind

/**
 * Room when the snapshot kind is `room`, NunuBar when it is `work`.
 * Cards are read from the snapshot. This screen does not offer a control that creates a task.
 */
@Composable
fun WorkScreen(
    workId: String,
    ports: WorkPorts,
    onOpenAgents: () -> Unit = {},
    fallbackTitle: String? = null,
    modifier: Modifier = Modifier,
) {
    val controller = remember(workId, ports) { WorkController(workId, ports) }
    LaunchedEffect(controller) { controller.activate(this) }
    val state by controller.state.collectAsState()
    val wide = LocalConfiguration.current.screenWidthDp >= 840
    var page by remember { mutableStateOf(BoardPage.TASKS) }
    var catalogOpen by remember { mutableStateOf(false) }
    var selectedTaskId by remember { mutableStateOf<String?>(null) }
    val snapshot = state.snapshot
    val title = snapshot?.let { workDisplayTitle(it.profile.name) } ?: fallbackTitle.orEmpty()
    val blocked = snapshot?.tasks?.count { it.task.state == com.nuum.contracts.WorkTaskState.BLOCKED } ?: 0
    Column(modifier = modifier.fillMaxSize().background(WorkColors.bgEditor)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (!wide) {
                WorkIconButton(label = stringResource(R.string.work_agents), onClick = onOpenAgents) {
                    Text("☰", color = WorkColors.textPrimary, fontSize = 16.sp)
                }
            }
            Text(
                text = title,
                color = WorkColors.textPrimary,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
            )
            if (snapshot?.discussionRunning == true) {
                WorkTextButton(
                    text = stringResource(R.string.work_stop_discussion),
                    onClick = controller::stopDiscussion,
                )
            }
            if (blocked > 0) {
                Text(
                    text = "$blocked " + stringResource(R.string.work_blocked),
                    color = WorkColors.textWarning,
                    fontSize = 13.sp,
                )
            }
        }
        ApprovalList(
            approvals = state.approvals,
            members = snapshot?.members.orEmpty(),
            onDecide = controller::decide,
        )
        if (state.notice != null) {
            WorkAlert(state.notice!!, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
        }
        if (snapshot == null) {
            Box(Modifier.weight(1f).fillMaxWidth())
            if (state.loading || snapshot?.profile?.kind != WorkKind.WORK) {
                UpgradeButton(enabled = false, onClick = {})
            }
        } else if (wide) {
            Row(Modifier.weight(1f).fillMaxWidth()) {
                WorkColumn(
                    snapshot = snapshot,
                    page = page,
                    onPage = { page = it },
                    controller = controller,
                    onOpenTask = { selectedTaskId = it },
                    bounded = true,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                )
                Inspector(
                    snapshot = snapshot,
                    onAdd = { catalogOpen = true },
                    onRemove = controller::removeCatalog,
                    onDetach = controller::detach,
                    onAttach = controller::attach,
                    pending = state.approvals.map { it.agentId }.toSet(),
                )
            }
        } else {
            Column(Modifier.weight(1f).fillMaxWidth()) {
                WorkColumn(
                    snapshot = snapshot,
                    page = page,
                    onPage = { page = it },
                    controller = controller,
                    onOpenTask = { selectedTaskId = it },
                    bounded = true,
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                )
                Column(
                    Modifier
                        .heightIn(max = 280.dp)
                        .verticalScroll(rememberScrollState()),
                ) {
                    CapabilitySection(
                        catalog = snapshot.catalog,
                        onAdd = { catalogOpen = true },
                        onRemove = controller::removeCatalog,
                    )
                    MemberSection(
                        workId = snapshot.profile.id,
                        members = snapshot.members,
                        snapshot = snapshot,
                        pendingAgentIds = state.approvals.map { it.agentId }.toSet(),
                        onDetach = controller::detach,
                        onAttach = controller::attach,
                    )
                }
            }
        }
    }
    if (catalogOpen && snapshot != null) {
        CapabilityDialog(controller = controller, wide = wide, onClose = { catalogOpen = false })
    }
    val current = snapshot
    val selected = current?.tasks?.firstOrNull { it.task.id == selectedTaskId }
    if (current != null && selected != null) {
        TaskDetailDialog(
            view = selected,
            members = current.members,
            wide = wide,
            controller = controller,
            onClose = { selectedTaskId = null },
        )
    }
}

@Composable
private fun UpgradeButton(enabled: Boolean, onClick: () -> Unit) {
    WorkTextButton(
        text = stringResource(R.string.work_enable_task_board),
        enabled = enabled,
        onClick = onClick,
        modifier = Modifier.padding(horizontal = 16.dp),
    )
}

@Composable
private fun WorkColumn(
    snapshot: com.nuum.contracts.WorkSnapshot,
    page: BoardPage,
    onPage: (BoardPage) -> Unit,
    controller: WorkController,
    onOpenTask: (String) -> Unit,
    bounded: Boolean,
    modifier: Modifier = Modifier,
) {
    val room = snapshot.profile.kind == WorkKind.ROOM
    Column(modifier) {
        if (room) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.work_local_room),
                    color = WorkColors.textPrimary,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 13.sp,
                    modifier = Modifier.weight(1f),
                )
                UpgradeButton(enabled = true, onClick = controller::upgrade)
            }
        } else if (snapshot.profile.kind == WorkKind.WORK) {
            PageSwitch(page = page, onChange = onPage)
            BoardStack(
                page = page,
                tasks = snapshot.tasks,
                members = snapshot.members,
                onOpen = onOpenTask,
                modifier = if (bounded) Modifier.weight(1f).fillMaxWidth() else Modifier.fillMaxWidth(),
            )
        }
        InterruptionList(
            items = snapshot.interruptions,
            members = snapshot.members,
            chat = snapshot.chat,
            onContinue = controller::continueDiscussion,
        )
        WorkChatDock(
            expanded = room,
            chat = snapshot.chat,
            members = snapshot.members,
            onPost = controller::post,
            fill = bounded && room,
            modifier = if (bounded && room) Modifier.weight(1f) else Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun Inspector(
    snapshot: com.nuum.contracts.WorkSnapshot,
    onAdd: () -> Unit,
    onRemove: (String) -> Unit,
    onDetach: (String, Int) -> Unit,
    onAttach: (String) -> Unit,
    pending: Set<String>,
) {
    val density = LocalDensity.current
    var widthPx by remember { mutableFloatStateOf(with(density) { 250.dp.toPx() }) }
    val minPx = with(density) { 184.dp.toPx() }
    val maxPx = with(density) { 380.dp.toPx() }
    val resize = stringResource(R.string.work_resize_inspector)
    Row(modifier = Modifier.fillMaxHeight().width(with(density) { widthPx.toDp() })) {
        Box(
            modifier = Modifier
                .width(48.dp)
                .fillMaxHeight()
                .semantics { contentDescription = resize }
                .pointerInput(minPx, maxPx) {
                    detectHorizontalDragGestures { _, delta ->
                        widthPx = (widthPx - delta).coerceIn(minPx, maxPx)
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.width(1.dp).fillMaxHeight().background(WorkColors.edge))
        }
        val splitLabel = stringResource(R.string.work_resize_split)
        Column(Modifier.weight(1f).fillMaxHeight().background(WorkColors.bgEditor)) {
            CapabilitySection(catalog = snapshot.catalog, onAdd = onAdd, onRemove = onRemove, modifier = Modifier.weight(0.32f))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = splitLabel }
                    .padding(vertical = 4.dp),
            ) {
                Box(Modifier.fillMaxWidth().width(1.dp).background(WorkColors.edge))
            }
            MemberSection(
                workId = snapshot.profile.id,
                members = snapshot.members,
                snapshot = snapshot,
                pendingAgentIds = pending,
                onDetach = onDetach,
                onAttach = onAttach,
                modifier = Modifier.weight(0.68f),
            )
        }
    }
}
