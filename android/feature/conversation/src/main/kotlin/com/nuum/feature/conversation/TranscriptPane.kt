package com.nuum.feature.conversation

import android.graphics.BitmapFactory
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.Image
import com.nuum.contracts.AgentView
import com.nuum.contracts.OutboundMessage
import com.nuum.contracts.UserAttachment
import com.nuum.contracts.ViewBlock
import com.nuum.contracts.WidgetOption
import com.nuum.contracts.WidgetPayload
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@Composable
internal fun TranscriptList(
    blocks: List<ViewBlock>,
    timestamps: Map<String, Long>,
    listState: LazyListState,
    peers: List<AgentView>,
    chat: Color,
    widgetAnswers: Map<String, String>,
    widgetErrors: Map<String, String>,
    widgetBusy: String?,
    onAnswer: (String, String) -> Unit,
    onOpenAttachment: (String) -> Unit,
    onOpenPeer: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val ids = blocks.map { it.blockId() }
    val transcriptLabel = copy(R.string.conversation_transcript)
    LazyColumn(
        state = listState,
        modifier = modifier.semantics { contentDescription = transcriptLabel },
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            start = 18.dp,
            end = 18.dp,
            top = 48.dp,
            bottom = 28.dp
        ),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        itemsIndexed(blocks, key = { index, block -> "${block.blockId()}:$index" }) { index, block ->
            val stamp = showTimeBefore(ids, index, timestamps)
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                if (stamp != null) TimeSeparator(stamp)
                when (block) {
                    is ViewBlock.User -> UserBubble(block, chat, onOpenAttachment)
                    is ViewBlock.Message -> MessageBubble(
                        block = block,
                        answered = widgetAnswers[block.blockId()],
                        error = widgetErrors[block.blockId()],
                        busy = widgetBusy == block.blockId(),
                        onAnswer = { value -> onAnswer(block.blockId(), value) },
                        onOpenAttachment = onOpenAttachment
                    )
                    is ViewBlock.Notice -> NoticeLine(block)
                    is ViewBlock.Peer -> PeerLine(block, peers, onOpenPeer)
                    is ViewBlock.Assistant -> AssistantActivity(block)
                }
            }
        }
    }
}

@Composable
private fun TimeSeparator(timestamp: Long) {
    val label = formatTranscriptTime(timestamp)
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Text(
            label,
            color = Sand.textTertiary,
            fontSize = 12.sp,
            modifier = Modifier
                .background(Sand.bgElevated, RoundedCornerShape(999.dp))
                .padding(horizontal = 10.dp, vertical = 2.dp)
        )
    }
}

@Composable
internal fun formatTranscriptTime(timestamp: Long, now: Long = System.currentTimeMillis()): String {
    val zone = ZoneId.systemDefault()
    val date = Instant.ofEpochMilli(timestamp).atZone(zone)
    val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
    val time = DateTimeFormatter.ofPattern("h:mm a").format(date)
    return when (date.toLocalDate()) {
        today -> copy(R.string.today_time, "time" to time)
        today.minusDays(1) -> copy(R.string.yesterday_time, "time" to time)
        else -> DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT).format(date)
    }
}

@Composable
private fun UserBubble(block: ViewBlock.User, chat: Color, onOpenAttachment: (String) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        Column(
            Modifier
                .widthIn(max = 560.dp)
                .fillMaxWidth(0.88f)
                .background(chat, RoundedCornerShape(18.dp))
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            if (block.text.isNotEmpty()) {
                Text(block.text, color = Sand.textOnColor, fontSize = 14.sp, lineHeight = 22.sp)
            }
            block.attachments.forEach { file ->
                HistoryAttachment(file, Sand.textOnColor, onOpenAttachment)
            }
        }
    }
}

@Composable
private fun HistoryAttachment(
    file: UserAttachment,
    tint: Color,
    onOpen: (String) -> Unit
) {
    Row(
        Modifier
            .clickable { onOpen(file.path) }
            .semantics { contentDescription = file.path },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SandIcon("attach", Modifier.size(16.dp), tint)
        Text(file.name, color = tint, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun MessageBubble(
    block: ViewBlock.Message,
    answered: String?,
    error: String?,
    busy: Boolean,
    onAnswer: (String) -> Unit,
    onOpenAttachment: (String) -> Unit
) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Start) {
        Column(Modifier.widthIn(max = 640.dp).fillMaxWidth(0.88f)) {
            when (val payload = block.payload) {
                is OutboundMessage.Text -> Column(
                    Modifier
                        .background(Sand.fillBubbleAgent, RoundedCornerShape(18.dp))
                        .padding(horizontal = 12.dp, vertical = 8.dp)
                ) {
                    MarkdownText(payload.content, Sand.textPrimary)
                    payload.images.forEach { image ->
                        Text(
                            image.alt ?: fileNameOf(image.path),
                            color = Sand.textLink,
                            modifier = Modifier.clickable { onOpenAttachment(image.path) }
                        )
                    }
                }
                is OutboundMessage.Attachment -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    AttachmentButton(fileNameOf(payload.path), payload.path, onOpenAttachment)
                    val caption = payload.caption
                    if (!caption.isNullOrBlank()) {
                        Text(caption, color = Sand.textPrimary, fontSize = 14.sp, lineHeight = 22.sp)
                    }
                }
                is OutboundMessage.Widget -> WidgetCard(payload.widget, answered, error, busy, onAnswer)
                is OutboundMessage.LegacyWidget -> Text(
                    "${payload.widget} ${prettyJson(payload.props)}",
                    color = Sand.textPrimary,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 12.sp,
                    modifier = Modifier
                        .background(Sand.bgElevated, RoundedCornerShape(8.dp))
                        .padding(8.dp)
                )
            }
        }
    }
}

@Composable
private fun AttachmentButton(name: String, path: String, onOpen: (String) -> Unit) {
    Row(
        Modifier
            .widthIn(max = 560.dp)
            .background(Sand.bgTertiary, RoundedCornerShape(10.dp))
            .border(1.dp, Sand.borderDefault, RoundedCornerShape(10.dp))
            .clickable { onOpen(path) }
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .semantics { contentDescription = path },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SandIcon("attach", Modifier.size(16.dp), Sand.textPrimary)
        Text(name, color = Sand.textPrimary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun WidgetCard(
    widget: WidgetPayload,
    answered: String?,
    error: String?,
    busy: Boolean,
    onAnswer: (String) -> Unit
) {
    val resolved = answered != null
    var custom by remember(widget.prompt) { mutableStateOf("") }
    Column(Modifier.widthIn(min = 0.dp, max = 380.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(widget.prompt, color = Sand.textPrimary, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, lineHeight = 22.sp)
        val help = widget.helpText
        if (!help.isNullOrBlank()) {
            Text(help, color = Sand.textSecondary, fontSize = 12.sp)
        }
        widget.options.forEach { option ->
            WidgetOptionButton(option, answered, resolved, busy, onAnswer)
        }
        if (widget.allowCustom && !resolved) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                androidx.compose.foundation.text.BasicTextField(
                    value = custom,
                    onValueChange = { custom = it },
                    textStyle = TextStyle(color = Sand.textPrimary, fontSize = 14.sp),
                    modifier = Modifier.weight(1f),
                    decorationBox = { inner ->
                        Box {
                            if (custom.isEmpty()) {
                                Text(copy(R.string.custom_answer_hint), color = Sand.textTertiary, fontSize = 14.sp)
                            }
                            inner()
                        }
                    }
                )
                val sendLabel = copy(R.string.send)
                Text(
                    sendLabel,
                    color = if (custom.isBlank()) Sand.textTertiary else Sand.textPrimary,
                    modifier = Modifier
                        .clickable(enabled = custom.isNotBlank() && !busy) { onAnswer(custom.trim()) }
                        .semantics { role = Role.Button; contentDescription = sendLabel }
                )
            }
        }
        if (answered != null) {
            Text(copy(R.string.your_answer, "answer" to answered), color = Sand.textSecondary, fontSize = 12.sp)
        }
        if (!error.isNullOrBlank()) {
            Text(error, color = Sand.textDanger, fontSize = 12.sp)
        }
    }
}

@Composable
private fun WidgetOptionButton(
    option: WidgetOption,
    answered: String?,
    resolved: Boolean,
    busy: Boolean,
    onAnswer: (String) -> Unit
) {
    val value = option.value ?: option.label
    val chosen = resolved && answered == value
    val border = when {
        chosen -> Sand.borderFocus
        option.style == "danger" -> Sand.borderDanger
        option.style == "primary" -> Sand.borderStrong
        else -> Sand.borderDefault
    }
    val background = if (chosen) Sand.fillGhostSelected else Sand.bgInput
    val textColor = if (option.style == "danger") Sand.textDanger else Sand.textPrimary
    Column(
        Modifier
            .fillMaxWidth()
            .alpha(if (resolved && !chosen) 0.55f else 1f)
            .background(background, RoundedCornerShape(12.dp))
            .border(1.dp, border, RoundedCornerShape(12.dp))
            .clickable(enabled = !resolved && !busy) { onAnswer(value) }
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Text(
            option.label,
            color = textColor,
            fontSize = 14.sp,
            fontWeight = if (option.style == "primary") FontWeight.SemiBold else FontWeight.Normal
        )
        val description = option.description
        if (!description.isNullOrBlank()) {
            Text(description, color = Sand.textSecondary, fontSize = 12.sp)
        }
    }
}

@Composable
private fun NoticeLine(block: ViewBlock.Notice) {
    val renamed = remember(block.text) {
        Regex("""^This agent changed name to "(.*)"\.$""").find(block.text)
    }
    val label = when {
        block.kind == "profile" && renamed != null -> copy(R.string.nunu_renamed, "name" to renamed.groupValues[1])
        block.kind == "profile" -> copy(R.string.nunu_profile_changed)
        block.kind == "wake" && block.text.startsWith("Participated in room: ") ->
            copy(R.string.participated_in_room, "name" to block.text.removePrefix("Participated in room: "))
        block.text == "Earlier conversation was summarized." -> copy(R.string.earlier_summarized)
        block.text == "Earlier messages were summarized to fit the context window. The originals are still on disk." ->
            copy(R.string.earlier_messages_summarized)
        else -> block.text
    }
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Text(
            label,
            color = Sand.textTertiary,
            fontSize = 12.sp,
            modifier = Modifier
                .background(Sand.bgElevated, RoundedCornerShape(999.dp))
                .padding(horizontal = 10.dp, vertical = 4.dp)
        )
    }
}

@Composable
private fun PeerLine(block: ViewBlock.Peer, peers: List<AgentView>, onOpen: (String) -> Unit) {
    val peer = peers.firstOrNull { it.profile.id == block.agentId }
    val name = peer?.profile?.name ?: block.agentName
    val outbound = block.direction == "outbound"
    Row(
        Modifier
            .fillMaxWidth()
            .clickable { onOpen(block.agentId) }
            .semantics { role = Role.Button },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            if (outbound) copy(R.string.sent_a_message_to) else copy(R.string.message_from),
            color = Sand.textTertiary,
            fontSize = 12.sp
        )
        NunuAvatar(
            agentId = block.agentId,
            colorId = peer?.profile?.avatarColor,
            shapeId = peer?.profile?.avatarShape,
            materialId = peer?.profile?.avatarMaterial,
            size = 20.dp,
            activity = if (outbound) "sending" else "receiving"
        )
        Text(name, color = Sand.textPrimary, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
        if (block.priority) {
            Text(copy(R.string.priority), color = Sand.textSecondary, fontSize = 12.sp)
        }
        SandIcon("chevron-right", Modifier.size(12.dp), Sand.textTertiary)
    }
}

@Composable
private fun AssistantActivity(block: ViewBlock.Assistant) {
    Column(Modifier.widthIn(max = 640.dp).fillMaxWidth(0.88f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (block.live && block.tools.isEmpty()) {
            Text(copy(R.string.thinking), color = Sand.textTertiary, fontSize = 12.sp)
        }
        if (block.tools.size > 1) {
            ToolGroup(block.tools)
        } else {
            block.tools.forEach { tool -> ToolCard(tool) }
        }
    }
}

@Composable
private fun ToolGroup(tools: List<com.nuum.contracts.ToolView>) {
    val status = when {
        tools.any { it.status == "pending" } -> "pending"
        tools.any { it.status == "error" } -> "error"
        else -> "ok"
    }
    var open by remember(tools.joinToString { it.id }) { mutableStateOf(false) }
    Column(
        Modifier
            .fillMaxWidth()
            .background(Sand.bgElevated, RoundedCornerShape(12.dp))
            .border(1.dp, Sand.borderSubtle, RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            "${copy(R.string.tool_calls, "count" to tools.size.toString())} · ${toolStatusLabel(status)}",
            color = Sand.textPrimary,
            fontSize = 12.sp,
            modifier = Modifier.clickable { open = !open }
        )
        if (open) tools.forEach { ToolCard(it) }
    }
}

@Composable
private fun ToolCard(tool: com.nuum.contracts.ToolView) {
    var open by remember(tool.id) { mutableStateOf(false) }
    Column(
        Modifier
            .fillMaxWidth()
            .background(Sand.bgElevated, RoundedCornerShape(12.dp))
            .border(1.dp, Sand.borderSubtle, RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            "${toolLabel(tool.name)} ${toolStatusLabel(tool.status)}",
            color = Sand.textPrimary,
            fontSize = 12.sp,
            modifier = Modifier.clickable { open = !open }
        )
        if (open) {
            Text(copy(R.string.arguments), color = Sand.textTertiary, fontSize = 12.sp)
            Text(prettyJson(tool.arguments), color = Sand.textSecondary, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
            val output = tool.output
            if (output != null) {
                Text(copy(R.string.output), color = Sand.textTertiary, fontSize = 12.sp)
                Text(
                    output.ifEmpty { copy(R.string.no_output) },
                    color = Sand.textSecondary,
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
        }
    }
}

@Composable
private fun toolLabel(name: String): String = when (name.lowercase()) {
    "bash", "shell" -> copy(R.string.tool_bash)
    "external_operation" -> copy(R.string.tool_local_operation)
    "request_network" -> copy(R.string.tool_network_access)
    "read" -> copy(R.string.tool_read)
    "ls" -> copy(R.string.tool_list)
    "write" -> copy(R.string.tool_write)
    else -> name.replace(Regex("([a-z])([A-Z])"), "$1 $2")
}

@Composable
private fun toolStatusLabel(status: String): String = when (status) {
    "pending" -> copy(R.string.status_running)
    "error" -> copy(R.string.status_failed)
    else -> copy(R.string.status_completed)
}

@Composable
internal fun MarkdownText(text: String, color: Color, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        parseMarkdown(text).forEach { block ->
            when (block) {
                is MdBlock.Paragraph -> InlineText(block.text, color)
                is MdBlock.Code -> Text(
                    block.text,
                    color = color,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 12.sp,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Sand.bgElevated, RoundedCornerShape(8.dp))
                        .padding(8.dp)
                )
                is MdBlock.Bullets -> block.items.forEach { item -> InlineText("• $item", color) }
                is MdBlock.Numbers -> block.items.forEachIndexed { index, item -> InlineText("${index + 1}. $item", color) }
            }
        }
    }
}

@Composable
private fun InlineText(text: String, color: Color) {
    val uriHandler = LocalUriHandler.current
    val annotated = buildAnnotatedString {
        val pattern = Regex("\\[([^\\]]+)]\\(([^)]+)\\)|`([^`]+)`")
        var cursor = 0
        for (match in pattern.findAll(text)) {
            append(text.substring(cursor, match.range.first))
            val label = match.groupValues[1]
            val url = match.groupValues[2]
            val code = match.groupValues[3]
            if (code.isNotEmpty()) {
                withStyle(SpanStyle(fontFamily = FontFamily.Monospace, background = Sand.bgElevated)) {
                    append(code)
                }
            } else {
                pushStringAnnotation("url", url)
                withStyle(SpanStyle(color = Sand.textLink)) { append(label) }
                pop()
            }
            cursor = match.range.last + 1
        }
        append(text.substring(cursor))
    }
    Text(
        annotated,
        color = color,
        fontSize = 14.sp,
        lineHeight = 22.sp,
        modifier = Modifier.clickable {
            annotated.getStringAnnotations("url", 0, annotated.length).firstOrNull()?.let { link ->
                runCatching { uriHandler.openUri(link.item) }
            }
        }
    )
}

private sealed class MdBlock {
    data class Paragraph(val text: String) : MdBlock()
    data class Code(val text: String) : MdBlock()
    data class Bullets(val items: List<String>) : MdBlock()
    data class Numbers(val items: List<String>) : MdBlock()
}

private fun parseMarkdown(text: String): List<MdBlock> {
    val blocks = mutableListOf<MdBlock>()
    val lines = text.replace("\r\n", "\n").split('\n')
    var index = 0
    while (index < lines.size) {
        val line = lines[index]
        if (line.startsWith("```")) {
            val body = mutableListOf<String>()
            index += 1
            while (index < lines.size && !lines[index].startsWith("```")) {
                body += lines[index]
                index += 1
            }
            if (index < lines.size) index += 1
            blocks += MdBlock.Code(body.joinToString("\n"))
            continue
        }
        if (line.isBlank()) {
            index += 1
            continue
        }
        if (line.startsWith("- ") || line.startsWith("* ")) {
            val items = mutableListOf<String>()
            while (index < lines.size && (lines[index].startsWith("- ") || lines[index].startsWith("* "))) {
                items += lines[index].drop(2)
                index += 1
            }
            blocks += MdBlock.Bullets(items)
            continue
        }
        if (Regex("""\d+\.\s+""").containsMatchIn(line) && line.first().isDigit()) {
            val items = mutableListOf<String>()
            while (index < lines.size && lines[index].matches(Regex("""\d+\.\s+.*"""))) {
                items += lines[index].substringAfter(". ").trim()
                index += 1
            }
            blocks += MdBlock.Numbers(items)
            continue
        }
        val paragraph = mutableListOf<String>()
        while (index < lines.size && lines[index].isNotBlank() && !lines[index].startsWith("```") &&
            !lines[index].startsWith("- ") && !lines[index].startsWith("* ")
        ) {
            paragraph += lines[index]
            index += 1
        }
        blocks += MdBlock.Paragraph(paragraph.joinToString(" "))
    }
    if (blocks.isEmpty()) blocks += MdBlock.Paragraph(text)
    return blocks
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun AttachmentChips(
    files: List<ComposerAttachment>,
    enabled: Boolean,
    onRemove: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val attachmentsLabel = copy(R.string.attachments)
    FlowRow(
        modifier = modifier.semantics { contentDescription = attachmentsLabel },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        files.forEachIndexed { index, file ->
            Row(
                Modifier
                    .widthIn(max = 210.dp)
                    .heightIn(min = 48.dp)
                    .background(Sand.bgTertiary, RoundedCornerShape(10.dp))
                    .border(1.dp, Sand.borderDefault, RoundedCornerShape(10.dp))
                    .padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (isImageMime(file.mimeType)) {
                    val bitmap = remember(file.name, file.bytes.size) {
                        BitmapFactory.decodeByteArray(file.bytes, 0, file.bytes.size)?.asImageBitmap()
                    }
                    if (bitmap != null) {
                        Image(
                            bitmap,
                            contentDescription = file.name,
                            modifier = Modifier.size(32.dp).clip(RoundedCornerShape(4.dp)),
                            contentScale = ContentScale.Crop
                        )
                    } else {
                        SandIcon("attach", Modifier.size(18.dp), Sand.textSecondary)
                    }
                } else {
                    SandIcon("attach", Modifier.size(18.dp), Sand.textSecondary)
                }
                Column(Modifier.weight(1f, fill = false)) {
                    Text(file.name, color = Sand.textPrimary, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(sizeLabel(file.bytes.size), color = Sand.textTertiary, fontSize = 11.sp)
                }
                val remove = copy(R.string.remove_name, "name" to file.name)
                Box(
                    Modifier
                        .size(48.dp)
                        .clickable(enabled = enabled) { onRemove(index) }
                        .semantics { role = Role.Button; contentDescription = remove },
                    contentAlignment = Alignment.Center
                ) {
                    SandIcon("close", Modifier.size(14.dp), Sand.textSecondary)
                }
            }
        }
    }
}

private fun sizeLabel(bytes: Int): String {
    val kb = maxOf(1, (bytes + 1023) / 1024)
    return "$kb KB"
}

internal fun activityState(status: com.nuum.contracts.AgentStatus, awaitingApproval: Boolean, executingTool: Boolean): String {
    if (awaitingApproval) return "waiting"
    if (status == com.nuum.contracts.AgentStatus.ERROR) return "error"
    if (status != com.nuum.contracts.AgentStatus.RUNNING) return "idle"
    return if (executingTool) "working" else "thinking"
}

@Composable
internal fun activityLabel(activity: String): String = when (activity) {
    "waiting" -> copy(R.string.waiting_for_approval)
    "thinking" -> copy(R.string.thinking)
    else -> copy(R.string.working)
}
