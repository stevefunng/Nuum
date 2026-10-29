package com.nuum.feature.work

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nuum.contracts.AgentView
import com.nuum.contracts.WorkActor
import com.nuum.contracts.WorkEvent
import com.nuum.contracts.WorkInterruption

@Composable
internal fun InterruptionList(
    items: List<WorkInterruption>,
    members: List<AgentView>,
    chat: List<WorkEvent>,
    onContinue: (eventId: String, inputAfterSeq: Int?) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (items.isEmpty()) return
    var requested by remember { mutableStateOf(24) }
    val maxCount = maxOf(1, chat.size)
    val count = requested.coerceIn(1, maxCount)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .semantics { liveRegion = LiveRegionMode.Polite }
            .padding(horizontal = 24.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items.forEach { item ->
            val name = item.agentId?.let { id -> members.find { it.profile.id == id }?.profile?.name ?: id }
            val body = interruptionText(item.error)
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(WorkColors.bgElevated, WorkRadiusLg)
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = if (name != null) "$name: $body" else body,
                    color = WorkColors.textPrimary,
                    fontSize = 13.sp,
                )
                WorkTextButton(
                    text = stringResource(R.string.work_continue),
                    onClick = { onContinue(item.eventId, null) },
                    primary = true,
                )
                if (item.taskId == null) {
                    var open by remember(item.eventId) { mutableStateOf(false) }
                    Text(
                        text = stringResource(R.string.work_use_less_history),
                        color = WorkColors.textSecondary,
                        fontSize = 13.sp,
                        modifier = Modifier.clickable { open = !open },
                    )
                    if (open) {
                        Text(
                            text = stringResource(R.string.work_recent_messages),
                            color = WorkColors.textSecondary,
                            fontSize = 12.sp,
                        )
                        val recentLabel = stringResource(R.string.work_recent_messages)
                        BasicTextField(
                            value = count.toString(),
                            onValueChange = { raw ->
                                requested = raw.filter { it.isDigit() }.toIntOrNull()?.coerceAtLeast(1) ?: 1
                            },
                            textStyle = TextStyle(color = WorkColors.textPrimary, fontSize = 13.sp),
                            cursorBrush = SolidColor(WorkColors.textPrimary),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                            modifier = Modifier.semantics { contentDescription = recentLabel },
                        )
                        WorkTextButton(
                            text = stringResource(R.string.work_continue_history),
                            onClick = { onContinue(item.eventId, inputAfterSeq(chat, count)) },
                            primary = true,
                        )
                    }
                }
            }
        }
    }
}

@Composable
internal fun interruptionText(error: String): String {
    val id = INTERRUPTION_STRINGS[error] ?: return error
    return stringResource(id)
}

private val INTERRUPTION_STRINGS = mapOf(
    "Discussion interrupted. Continue starts a new bounded discussion." to R.string.work_interrupt_discussion,
    "Execution interrupted. Check tools and published results before continuing." to R.string.work_interrupt_execution,
    "Execution failed. Check the result before continuing." to R.string.work_interrupt_failed,
    "Card execution ended without a handoff. Continue or cancel the card." to R.string.work_interrupt_card,
    "Legacy execution requires confirmation before continuing." to R.string.work_interrupt_legacy,
    "Previous room history is preserved. Continue only if this discussion still needs a response." to R.string.work_interrupt_previous,
    "Room context is too large. No new room input was consumed; narrow the history range before continuing." to R.string.work_interrupt_context,
    "A room response failed. Check the model settings and dispatch again." to R.string.work_interrupt_response,
)

@Composable
internal fun WorkChatDock(
    expanded: Boolean,
    chat: List<WorkEvent>,
    members: List<AgentView>,
    onPost: (String) -> Unit,
    modifier: Modifier = Modifier,
    fill: Boolean = false,
) {
    var opened by remember { mutableStateOf(false) }
    val open = expanded || opened
    var draft by remember { mutableStateOf("") }
    val messages = chat.mapNotNull { event -> chatBody(event)?.let { event to it } }
    val logLabel = stringResource(R.string.work_shared_room_messages)
    val fieldLabel = stringResource(R.string.work_message_work)
    val placeholder = stringResource(R.string.work_message_work_placeholder)
    val scroll = rememberScrollState()
    LaunchedEffect(open, messages.size) {
        if (open) scroll.scrollTo(scroll.maxValue)
    }
    Column(modifier = modifier.fillMaxWidth()) {
        if (open) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .then(if (fill) Modifier.weight(1f, fill = true) else Modifier.heightIn(min = 180.dp, max = 420.dp))
                    .padding(horizontal = 16.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = stringResource(R.string.work_shared_room) + " " + messages.size,
                        color = WorkColors.textPrimary,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    WorkIconButton(
                        label = stringResource(R.string.work_close_shared_room),
                        onClick = { opened = false },
                    ) {
                        Text("×", color = WorkColors.textSecondary, fontSize = 16.sp)
                    }
                }
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(if (fill) Modifier.weight(1f) else Modifier.heightIn(max = 320.dp))
                        .verticalScroll(scroll)
                        .semantics { contentDescription = logLabel },
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (messages.isEmpty()) {
                        Text(
                            text = stringResource(R.string.work_no_messages),
                            color = WorkColors.textTertiary,
                            fontSize = 13.sp,
                        )
                    }
                    messages.forEach { (event, body) ->
                        val fromUser = event.actor is WorkActor.User
                        val author = when (val actor = event.actor) {
                            is WorkActor.Agent -> members.find { it.profile.id == actor.id }?.profile?.name
                                ?: stringResource(R.string.work_agent)
                            is WorkActor.System -> stringResource(R.string.work_agent)
                            is WorkActor.User -> null
                        }
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalAlignment = if (fromUser) Alignment.End else Alignment.Start,
                        ) {
                            if (author != null) {
                                Text(author, color = WorkColors.textSecondary, fontSize = 12.sp)
                            }
                            Box(
                                modifier = Modifier
                                    .widthIn(max = 560.dp)
                                    .fillMaxWidth(0.88f)
                                    .background(
                                        if (fromUser) WorkColors.fillBubbleUser else WorkColors.bgElevated,
                                        RoundedCornerShape(18.dp),
                                    )
                                    .padding(horizontal = 12.dp, vertical = 8.dp),
                            ) {
                                if (fromUser) {
                                    Text(body.body, color = WorkColors.textOnColor, fontSize = 14.sp, lineHeight = 22.sp)
                                } else {
                                    MarkdownBody(body.body)
                                }
                            }
                        }
                    }
                }
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp)
                .background(WorkColors.bgInput, WorkRadius2xl)
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicTextField(
                value = draft,
                onValueChange = { draft = it },
                textStyle = TextStyle(color = WorkColors.textPrimary, fontSize = 14.sp),
                cursorBrush = SolidColor(WorkColors.textPrimary),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = {
                    if (draft.isNotBlank()) {
                        onPost(draft)
                        draft = ""
                    }
                }),
                modifier = Modifier
                    .weight(1f)
                    .onFocusChanged { if (it.isFocused) opened = true }
                    .semantics { contentDescription = fieldLabel },
                decorationBox = { inner ->
                    Box {
                        if (draft.isEmpty()) {
                            Text(placeholder, color = WorkColors.textTertiary, fontSize = 14.sp)
                        }
                        inner()
                    }
                },
            )
            val postLabel = stringResource(R.string.work_post_message)
            Text(
                text = "↑",
                color = if (draft.isBlank()) WorkColors.textTertiary else WorkColors.textOnPrimary,
                modifier = Modifier
                    .padding(start = 8.dp)
                    .background(
                        if (draft.isBlank()) WorkColors.fillSecondary else WorkColors.fillPrimary,
                        WorkRadiusFull,
                    )
                    .semantics { contentDescription = postLabel }
                    .clickable(enabled = draft.isNotBlank()) {
                        onPost(draft)
                        draft = ""
                    }
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun MarkdownBody(source: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        source.split('\n').forEach { line ->
            val trimmed = line.trim()
            val content = when {
                trimmed.startsWith("- ") -> "• " + trimmed.removePrefix("- ")
                trimmed.startsWith("* ") -> "• " + trimmed.removePrefix("* ")
                else -> line
            }
            Text(
                text = inlineMarkdown(content),
                color = WorkColors.textPrimary,
                fontSize = 14.sp,
                lineHeight = 22.sp,
            )
        }
    }
}

private fun inlineMarkdown(source: String) = buildAnnotatedString {
    var index = 0
    while (index < source.length) {
        if (source.startsWith("**", index)) {
            val end = source.indexOf("**", index + 2)
            if (end > index) {
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) {
                    append(source.substring(index + 2, end))
                }
                index = end + 2
                continue
            }
        }
        if (source[index] == '`') {
            val end = source.indexOf('`', index + 1)
            if (end > index) {
                withStyle(SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 12.sp)) {
                    append(source.substring(index + 1, end))
                }
                index = end + 1
                continue
            }
        }
        append(source[index])
        index++
    }
}
