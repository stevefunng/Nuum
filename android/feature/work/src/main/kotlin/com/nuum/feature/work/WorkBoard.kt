package com.nuum.feature.work

import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.zIndex
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.nuum.contracts.AgentView
import com.nuum.contracts.TranscriptEvent
import com.nuum.contracts.TranscriptPage
import com.nuum.contracts.WorkTask
import com.nuum.contracts.WorkTaskPriority
import com.nuum.contracts.WorkTaskState
import com.nuum.contracts.WorkTaskView
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

internal enum class BoardPage { TASKS, DELIVERABLES }

@Composable
internal fun reducedMotion(): Boolean {
    val resolver = LocalContext.current.contentResolver
    val scale = Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
    return scale == 0f
}

@Composable
internal fun stateLabel(state: WorkTaskState): String = stringResource(
    when (state) {
        WorkTaskState.PROPOSED -> R.string.work_proposed
        WorkTaskState.READY -> R.string.work_ready
        WorkTaskState.IN_PROGRESS -> R.string.work_in_progress
        WorkTaskState.BLOCKED -> R.string.work_blocked
        WorkTaskState.REVIEW -> R.string.work_review
        WorkTaskState.DONE -> R.string.work_done
        WorkTaskState.CANCELLED -> R.string.work_cancelled
    },
)

@Composable
internal fun PageSwitch(page: BoardPage, onChange: (BoardPage) -> Unit) {
    val toDeliverables = stringResource(R.string.work_switch_deliverables)
    val toTasks = stringResource(R.string.work_switch_tasks)
    val label = if (page == BoardPage.TASKS) toDeliverables else toTasks
    val strong = if (page == BoardPage.TASKS) stringResource(R.string.work_tasks) else stringResource(R.string.work_deliverables)
    val weak = if (page == BoardPage.TASKS) stringResource(R.string.work_deliverables) else stringResource(R.string.work_tasks)
    Row(
        modifier = Modifier
            .semantics {
                role = Role.Button
                contentDescription = label
            }
            .clickable {
                onChange(if (page == BoardPage.TASKS) BoardPage.DELIVERABLES else BoardPage.TASKS)
            }
            .padding(horizontal = 24.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(strong, color = WorkColors.textPrimary, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
        Text("/", color = WorkColors.textTertiary, fontSize = 14.sp)
        Text(weak, color = WorkColors.textTertiary, fontSize = 14.sp)
    }
}

@Composable
internal fun TaskLanes(
    tasks: List<WorkTaskView>,
    members: List<AgentView>,
    onOpen: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scroll = rememberScrollState()
    val scope = rememberCoroutineScope()
    val reduced = reducedMotion()
    var focused by remember { mutableStateOf(WorkTaskState.READY) }
    val offsets = remember { mutableMapOf<WorkTaskState, Int>() }
    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(scroll)
                .padding(horizontal = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            LANE_ORDER.forEach { state ->
                val items = tasksIn(tasks, state)
                val title = stateLabel(state)
                val laneLabel = stringResource(R.string.work_state_tasks, title)
                Column(
                    modifier = Modifier
                        .width(200.dp)
                        .onGloballyPositioned { offsets[state] = it.positionInParent().x.toInt() }
                        .semantics { contentDescription = laneLabel },
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        LaneDot(state)
                        Text(title, color = WorkColors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        Text(items.size.toString(), color = WorkColors.textTertiary, fontSize = 12.sp)
                    }
                    if (items.isEmpty()) {
                        Text(
                            text = stringResource(R.string.work_no_tasks),
                            color = WorkColors.textTertiary,
                            fontSize = 12.sp,
                            modifier = Modifier.padding(top = 12.dp),
                        )
                    }
                    items.forEach { task ->
                        TaskCard(task = task, members = members, onOpen = onOpen)
                    }
                }
            }
        }
        val navLabel = stringResource(R.string.work_task_states)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp)
                .semantics { contentDescription = navLabel },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                LANE_ORDER.forEach { state ->
                    val title = stateLabel(state)
                    val count = tasksIn(tasks, state).size
                    Text(
                        text = title,
                        color = if (focused == state) WorkColors.textPrimary else WorkColors.textTertiary,
                        fontSize = 12.sp,
                        modifier = Modifier
                            .semantics { selected = focused == state }
                            .clickable {
                                focused = state
                                val x = offsets[state] ?: return@clickable
                                scope.launch {
                                    if (reduced) scroll.scrollTo(x) else scroll.animateScrollTo(x)
                                }
                            }
                            .padding(horizontal = 4.dp, vertical = 4.dp),
                    )
                    Text(count.toString(), color = WorkColors.textTertiary, fontSize = 11.sp)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
                LANE_ORDER.forEach { state ->
                    val title = stateLabel(state)
                    val count = tasksIn(tasks, state).size
                    val dotLabel = "$title: $count"
                    val scale = if (!reduced && focused == state) 1.3f else 1f
                    Box(
                        modifier = Modifier
                            .size((4 * scale).dp)
                            .semantics {
                                role = Role.Button
                                selected = focused == state
                                contentDescription = dotLabel
                            }
                            .clickable {
                                focused = state
                                val x = offsets[state] ?: return@clickable
                                scope.launch {
                                    if (reduced) scroll.scrollTo(x) else scroll.animateScrollTo(x)
                                }
                            }
                            .background(
                                if (focused == state) WorkColors.textSecondary else WorkColors.textTertiary.copy(alpha = 0.4f),
                                CircleShape,
                            ),
                    )
                }
            }
        }
    }
}

@Composable
private fun LaneDot(state: WorkTaskState) {
    val fill = when (state) {
        WorkTaskState.IN_PROGRESS -> WorkColors.blue
        WorkTaskState.BLOCKED -> WorkColors.orange
        WorkTaskState.DONE -> WorkColors.green
        else -> Color.Transparent
    }
    val stroke = when (state) {
        WorkTaskState.IN_PROGRESS -> WorkColors.blue
        WorkTaskState.BLOCKED -> WorkColors.orange
        WorkTaskState.DONE -> WorkColors.green
        WorkTaskState.REVIEW -> WorkColors.magenta
        else -> WorkColors.textTertiary
    }
    Box(
        modifier = Modifier
            .size(6.dp)
            .border(1.dp, stroke, CircleShape)
            .background(fill, CircleShape),
    )
}

@Composable
private fun TaskCard(task: WorkTask, members: List<AgentView>, onOpen: (String) -> Unit) {
    val open = stringResource(R.string.work_open_task, task.title)
    val agentLabel = stringResource(R.string.work_agent)
    val names = if (task.assigneeIds.isEmpty()) {
        stringResource(R.string.work_unassigned)
    } else {
        task.assigneeIds.joinToString(", ") { id ->
            members.find { it.profile.id == id }?.profile?.name ?: agentLabel
        }
    }
    Column(
        modifier = Modifier
            .padding(top = 10.dp)
            .fillMaxWidth()
            .heightIn(min = 112.dp)
            .background(WorkColors.bgElevated, WorkRadiusLg)
            .border(1.dp, WorkColors.edge, WorkRadiusLg)
            .semantics { contentDescription = open }
            .clickable { onOpen(task.id) }
            .padding(15.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(task.title, color = WorkColors.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 2)
        if (task.description.isNotBlank()) {
            Text(
                task.description,
                color = WorkColors.textSecondary,
                fontSize = 10.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Row {
                task.assigneeIds.take(3).forEach { id ->
                    val member = members.find { it.profile.id == id } ?: return@forEach
                    MemberAvatar(member = member, waiting = false, size = 20)
                }
            }
            Text(names, color = WorkColors.textSecondary, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (task.deliverables.isNotEmpty()) {
            Text(
                stringResource(R.string.work_count_files, task.deliverables.size),
                color = WorkColors.textTertiary,
                fontSize = 11.sp,
            )
        }
    }
}

@Composable
internal fun DeliverablePage(
    tasks: List<WorkTaskView>,
    members: List<AgentView>,
    onOpen: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val completed = tasks.map { it.task }.filter { it.state == WorkTaskState.DONE }
    val files = completed.flatMap { it.deliverables }
    var copiedId by remember { mutableStateOf<String?>(null) }
    var copyError by remember { mutableStateOf<String?>(null) }
    val clipboard = LocalClipboardManager.current
    val failed = stringResource(R.string.work_copy_failed)
    Column(
        modifier = modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (completed.isEmpty()) {
            Text("⌂", color = WorkColors.textTertiary, fontSize = 22.sp)
            Text(stringResource(R.string.work_no_deliverables), color = WorkColors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            Text(stringResource(R.string.work_no_deliverables_body), color = WorkColors.textSecondary, fontSize = 13.sp)
        }
        val agentLabel = stringResource(R.string.work_agent)
        val unassigned = stringResource(R.string.work_unassigned)
        completed.forEach { task ->
            val names = if (task.assigneeIds.isEmpty()) {
                unassigned
            } else {
                task.assigneeIds.joinToString(", ") { id ->
                    members.find { it.profile.id == id }?.profile?.name ?: agentLabel
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = task.title,
                    color = WorkColors.textPrimary,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clickable { onOpen(task.id) },
                )
                Text(stateLabel(task.state), color = WorkColors.textTertiary, fontSize = 12.sp)
                Text(names, color = WorkColors.textSecondary, fontSize = 12.sp)
                task.deliverables.forEach { file ->
                    val whenText = DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(file.createdAt))
                    Column {
                        Text(file.name, color = WorkColors.textPrimary, fontSize = 13.sp)
                        Text(
                            (file.mimeType ?: stringResource(R.string.work_file)) + " · " + whenText,
                            color = WorkColors.textTertiary,
                            fontSize = 12.sp,
                        )
                        Text(
                            file.uri,
                            color = WorkColors.textSecondary,
                            fontSize = 12.sp,
                            fontFamily = FontFamily.Monospace,
                        )
                        WorkTextButton(
                            text = if (copiedId == file.id) stringResource(R.string.work_copied) else stringResource(R.string.work_copy_path),
                            onClick = {
                                try {
                                    clipboard.setText(AnnotatedString(file.uri))
                                    copiedId = file.id
                                    copyError = null
                                } catch (_: Exception) {
                                    copyError = failed
                                }
                            },
                        )
                    }
                }
            }
        }
        if (completed.isNotEmpty() && files.isEmpty()) {
            Text(stringResource(R.string.work_no_files_yet), color = WorkColors.textSecondary, fontSize = 13.sp)
        }
        if (copyError != null) WorkAlert(copyError!!)
    }
}

@Composable
internal fun BoardStack(
    page: BoardPage,
    tasks: List<WorkTaskView>,
    members: List<AgentView>,
    onOpen: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.fillMaxWidth()) {
        val tasksActive = page == BoardPage.TASKS
        TaskLanes(
            tasks = tasks,
            members = members,
            onOpen = onOpen,
            modifier = Modifier
                .zIndex(if (tasksActive) 1f else 0f)
                .alpha(if (tasksActive) 1f else 0f)
                .then(if (tasksActive) Modifier else Modifier.semantics { hideFromAccessibility() }.focusProperties { canFocus = false }),
        )
        DeliverablePage(
            tasks = tasks,
            members = members,
            onOpen = onOpen,
            modifier = Modifier
                .zIndex(if (tasksActive) 0f else 1f)
                .alpha(if (!tasksActive) 1f else 0f)
                .then(if (!tasksActive) Modifier else Modifier.semantics { hideFromAccessibility() }.focusProperties { canFocus = false }),
        )
    }
}

@Composable
internal fun TaskDetailDialog(
    view: WorkTaskView,
    members: List<AgentView>,
    wide: Boolean,
    controller: WorkController,
    onClose: () -> Unit,
) {
    val task = view.task
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf<String?>(null) }
    var workerId by remember { mutableStateOf("") }
    var instruction by remember { mutableStateOf("") }
    var trace by remember { mutableStateOf<TranscriptPage?>(null) }
    var traceEntries by remember { mutableStateOf<List<TranscriptEvent>>(emptyList()) }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(modifier = Modifier.fillMaxSize().background(WorkColors.scrim), contentAlignment = Alignment.Center) {
            Column(
                modifier = Modifier
                    .then(if (wide) Modifier.widthIn(max = 560.dp).heightIn(max = 720.dp) else Modifier.fillMaxSize())
                    .background(WorkColors.bgElevated, if (wide) WorkRadius2xl else androidx.compose.foundation.shape.RoundedCornerShape(0.dp))
                    .verticalScroll(rememberScrollState())
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                DialogHeader(title = task.title, subtitle = stateLabel(task.state), onClose = onClose)
                if (task.description.isNotBlank()) {
                    Text(task.description, color = WorkColors.textPrimary, fontSize = 14.sp)
                }
                val ownerId = task.ownerAgentId
                if (ownerId != null) {
                    val owner = members.find { it.profile.id == ownerId }?.profile?.name ?: ownerId
                    Meta(stringResource(R.string.work_card_owner), owner)
                }
                Text(stringResource(R.string.work_workers), color = WorkColors.textSecondary, fontSize = 12.sp)
                if (task.assigneeIds.isEmpty()) {
                    Text(stringResource(R.string.work_unassigned), color = WorkColors.textPrimary, fontSize = 13.sp)
                } else {
                    task.assigneeIds.forEach { id ->
                        val member = members.find { it.profile.id == id } ?: return@forEach
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            MemberAvatar(member, waiting = false, size = 24)
                            Text(member.profile.name, color = WorkColors.textPrimary, fontSize = 13.sp)
                        }
                    }
                }
                Meta(stringResource(R.string.work_priority), priorityLabel(task.priority))
                if (task.acceptanceCriteria.isNotEmpty()) {
                    Text(stringResource(R.string.work_acceptance), color = WorkColors.textPrimary, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    task.acceptanceCriteria.forEach { item ->
                        Text("• $item", color = WorkColors.textPrimary, fontSize = 13.sp)
                    }
                }
                val blocker = task.blocker
                if (blocker != null) {
                    Text(
                        stringResource(R.string.work_blocked_prefix) + " " + blocker.reason,
                        color = WorkColors.textWarning,
                        fontSize = 13.sp,
                    )
                }
                if (task.deliverables.isNotEmpty()) {
                    Text(stringResource(R.string.work_deliverables), color = WorkColors.textPrimary, fontWeight = FontWeight.SemiBold)
                    task.deliverables.forEach { file ->
                        Text(file.name, color = WorkColors.textPrimary, fontSize = 13.sp)
                        Text(file.uri, color = WorkColors.textTertiary, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                    }
                }
                if (task.state == WorkTaskState.BLOCKED) {
                    Text(stringResource(R.string.work_paused), color = WorkColors.textSecondary, fontSize = 13.sp)
                    WorkTextButton(
                        text = stringResource(R.string.work_confirm_resume),
                        primary = true,
                        onClick = {
                            scope.launch {
                                error = null
                                try {
                                    controller.transition(task, WorkTaskState.IN_PROGRESS)
                                } catch (cancelled: CancellationException) {
                                    throw cancelled
                                } catch (failure: Exception) {
                                    error = failure.message
                                }
                            }
                        },
                    )
                    WorkTextButton(
                        text = stringResource(R.string.work_cancel_task),
                        onClick = {
                            scope.launch {
                                error = null
                                try {
                                    controller.transition(task, WorkTaskState.CANCELLED)
                                } catch (cancelled: CancellationException) {
                                    throw cancelled
                                } catch (failure: Exception) {
                                    error = failure.message
                                }
                            }
                        },
                    )
                }
                if (task.state == WorkTaskState.REVIEW) {
                    WorkTextButton(
                        text = stringResource(R.string.work_request_changes),
                        onClick = {
                            scope.launch {
                                error = null
                                try {
                                    controller.transition(task, WorkTaskState.IN_PROGRESS)
                                } catch (cancelled: CancellationException) {
                                    throw cancelled
                                } catch (failure: Exception) {
                                    error = failure.message
                                }
                            }
                        },
                    )
                    WorkTextButton(
                        text = stringResource(R.string.work_accept_delivery),
                        primary = true,
                        onClick = {
                            scope.launch {
                                error = null
                                try {
                                    controller.transition(task, WorkTaskState.DONE)
                                } catch (cancelled: CancellationException) {
                                    throw cancelled
                                } catch (failure: Exception) {
                                    error = failure.message
                                }
                            }
                        },
                    )
                }
                WorkTextButton(
                    text = stringResource(R.string.work_execution_history),
                    onClick = {
                        scope.launch {
                            error = null
                            try {
                                val page = controller.loadTrace(task.id, null, null)
                                trace = page
                                traceEntries = page.entries
                            } catch (cancelled: CancellationException) {
                                throw cancelled
                            } catch (failure: Exception) {
                                error = failure.message
                            }
                        }
                    },
                )
                if (trace != null) {
                    val session = trace?.id.orEmpty()
                    val historyLabel = stringResource(R.string.work_execution_history)
                    Text(
                        text = session,
                        color = WorkColors.textSecondary,
                        fontSize = 12.sp,
                        modifier = Modifier.semantics { contentDescription = historyLabel },
                    )
                    if (traceEntries.isEmpty()) {
                        Text(stringResource(R.string.work_no_history), color = WorkColors.textTertiary, fontSize = 13.sp)
                    }
                    traceEntries.forEach { event ->
                        var open by remember(event.id) { mutableStateOf(false) }
                        Text(
                            text = "${event.seq} · ${event.type}",
                            color = WorkColors.textPrimary,
                            fontSize = 12.sp,
                            modifier = Modifier.clickable { open = !open },
                        )
                        if (open) {
                            Text(traceText(event), color = WorkColors.textSecondary, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                        }
                    }
                    val before = trace?.nextBeforeSeq
                    if (before != null) {
                        WorkTextButton(
                            text = stringResource(R.string.work_load_earlier),
                            onClick = {
                                scope.launch {
                                    error = null
                                    try {
                                        val older = controller.loadTrace(task.id, trace?.id, before)
                                        trace = older
                                        traceEntries = older.entries + traceEntries
                                    } catch (cancelled: CancellationException) {
                                        throw cancelled
                                    } catch (failure: Exception) {
                                        error = failure.message
                                    }
                                }
                            },
                        )
                    }
                }
                if (task.state == WorkTaskState.READY || task.state == WorkTaskState.IN_PROGRESS) {
                    val workers = members.filter { canDispatch(it) }
                    val choose = stringResource(R.string.work_choose_worker)
                    Column(Modifier.semantics { contentDescription = choose }) {
                        Text(
                            text = workers.find { it.profile.id == workerId }?.profile?.name ?: choose,
                            color = WorkColors.textSecondary,
                            fontSize = 13.sp,
                        )
                        workers.forEach { member ->
                            Text(
                                text = member.profile.name,
                                color = WorkColors.textPrimary,
                                fontSize = 13.sp,
                                modifier = Modifier
                                    .semantics { selected = workerId == member.profile.id }
                                    .clickable { workerId = member.profile.id }
                                    .padding(vertical = 4.dp),
                            )
                        }
                    }
                    WorkInput(
                        value = instruction,
                        onValueChange = { instruction = it },
                        placeholder = stringResource(R.string.work_instruction),
                        label = stringResource(R.string.work_instruction),
                        enabled = true,
                        tag = "dispatch-instruction",
                    )
                    val runnable = instruction.isNotBlank() && workers.any { it.profile.id == workerId }
                    WorkTextButton(
                        text = stringResource(R.string.work_run),
                        primary = true,
                        enabled = runnable,
                        onClick = {
                            scope.launch {
                                error = null
                                try {
                                    controller.dispatch(workerId, task.id, instruction.trim())
                                    instruction = ""
                                } catch (cancelled: CancellationException) {
                                    throw cancelled
                                } catch (failure: Exception) {
                                    error = failure.message
                                }
                            }
                        },
                    )
                }
                if (error != null) WorkAlert(error!!)
            }
        }
    }
}

@Composable
private fun Meta(label: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, color = WorkColors.textSecondary, fontSize = 12.sp)
        Text(value, color = WorkColors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun priorityLabel(priority: WorkTaskPriority): String = stringResource(
    when (priority) {
        WorkTaskPriority.LOW -> R.string.work_low
        WorkTaskPriority.NORMAL -> R.string.work_normal
        WorkTaskPriority.HIGH -> R.string.work_high
    },
)
