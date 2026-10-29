package com.nuum.feature.conversation

import com.nuum.contracts.AssistantPart
import com.nuum.contracts.HostEvent
import com.nuum.contracts.IMAGE_MIME_TYPES
import com.nuum.contracts.LiveAssistant
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.MAX_ATTACHMENTS
import com.nuum.contracts.MAX_ATTACHMENT_BYTES
import com.nuum.contracts.MAX_ATTACHMENT_TOTAL_BYTES
import com.nuum.contracts.MessagePart
import com.nuum.contracts.ModelRef
import com.nuum.contracts.OutboundMessage
import com.nuum.contracts.PickedFile
import com.nuum.contracts.ProviderId
import com.nuum.contracts.ToolView
import com.nuum.contracts.TranscriptEvent
import com.nuum.contracts.ViewBlock
import com.nuum.contracts.WakeSource
import java.time.Instant
import java.time.ZoneId

internal enum class CopyKey {
    AtMost5,
    TooLarge,
    TotalTooLarge,
    ReadFailed,
    Reading,
    Stopped,
    HostError,
    NoImageSupport
}

internal data class ToolResult(val content: String, val ok: Boolean?)

internal data class LiveText(val messageId: String, val text: String)

/**
 * One-to-one approval. Mac puts `workId` on `agent.tool.pending` when the run
 * belongs to a work, and the conversation surface drops that pending.
 * [HostEvent.AgentToolPending] does not carry `workId` yet, so [workId] stays
 * null for contract events. A non-null id still hides the bar.
 */
internal data class PendingTool(
    val toolCallId: String,
    val name: String,
    val arguments: Map<String, Any?>,
    val action: LocalToolAction,
    val target: String,
    val justification: String? = null,
    val allowAlways: Boolean? = null,
    val details: String? = null,
    val workId: String? = null
) {
    val alwaysEnabled: Boolean get() = allowAlways != false
}

internal fun ViewBlock.blockId(): String = when (this) {
    is ViewBlock.User -> id
    is ViewBlock.Assistant -> id
    is ViewBlock.Message -> id
    is ViewBlock.Peer -> id
    is ViewBlock.Notice -> id
}

internal fun oneToOneApproval(pending: PendingTool?): PendingTool? {
    if (pending == null || !pending.workId.isNullOrEmpty()) return null
    return pending
}

internal fun HostEvent.AgentToolPending.toPending(): PendingTool = PendingTool(
    toolCallId = toolCallId,
    name = toolName,
    arguments = arguments,
    action = action,
    target = target,
    justification = justification,
    allowAlways = allowAlways,
    details = details,
    workId = null
)

internal data class ComposerAttachment(
    val name: String,
    val mimeType: String,
    val bytes: ByteArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ComposerAttachment) return false
        return name == other.name && mimeType == other.mimeType && bytes.contentEquals(other.bytes)
    }

    override fun hashCode(): Int {
        var result = name.hashCode()
        result = 31 * result + mimeType.hashCode()
        result = 31 * result + bytes.contentHashCode()
        return result
    }
}

internal sealed class AttachmentDecision {
    data class Accept(val files: List<ComposerAttachment>) : AttachmentDecision()
    data class Reject(val reason: CopyKey) : AttachmentDecision()
}

internal fun validateAttachments(
    current: List<ComposerAttachment>,
    incoming: List<PickedFile>
): AttachmentDecision {
    if (incoming.isEmpty()) return AttachmentDecision.Accept(current)
    if (current.size + incoming.size > MAX_ATTACHMENTS) {
        return AttachmentDecision.Reject(CopyKey.AtMost5)
    }
    if (incoming.any { it.bytes.size > MAX_ATTACHMENT_BYTES }) {
        return AttachmentDecision.Reject(CopyKey.TooLarge)
    }
    val total = current.sumOf { it.bytes.size.toLong() } + incoming.sumOf { it.bytes.size.toLong() }
    if (total > MAX_ATTACHMENT_TOTAL_BYTES) {
        return AttachmentDecision.Reject(CopyKey.TotalTooLarge)
    }
    val added = incoming.map { file ->
        ComposerAttachment(
            name = file.name,
            mimeType = file.mimeType.ifBlank { "application/octet-stream" },
            bytes = file.bytes
        )
    }
    return AttachmentDecision.Accept(current + added)
}

internal fun isImageMime(mimeType: String): Boolean = mimeType.lowercase() in IMAGE_MIME_TYPES

/** Mirrors `packages/protocol/src/attachments.ts` `supportsImageInput`. */
internal fun supportsImageInput(model: ModelRef): Boolean {
    if (model.provider == ProviderId.DEEPSEEK) return false
    if (model.provider == ProviderId.ANTHROPIC) {
        return Regex("^claude-(?:3|sonnet-4|opus-4|haiku-4)", RegexOption.IGNORE_CASE)
            .containsMatchIn(model.model)
    }
    return Regex(
        "^(?:gpt-4o|gpt-4\\.1|gpt-4-turbo|gpt-5|o1(?!-mini|-preview)|o3(?!-mini)|o4)",
        RegexOption.IGNORE_CASE
    ).containsMatchIn(model.model)
}

internal fun appendText(current: LiveText?, messageId: String, delta: String): LiveText {
    val base = if (current?.messageId == messageId) current.text else ""
    return LiveText(messageId, base + delta)
}

internal fun appendAssistantDelta(
    parts: List<AssistantPart>,
    kind: MessagePart,
    delta: String
): List<AssistantPart> {
    val next = parts.toMutableList()
    val last = next.lastOrNull()
    if (kind == MessagePart.THINKING && last is AssistantPart.Thinking) {
        next[next.lastIndex] = last.copy(text = last.text + delta)
        return next
    }
    if (kind == MessagePart.TEXT && last is AssistantPart.Text) {
        next[next.lastIndex] = last.copy(text = last.text + delta)
        return next
    }
    next += when (kind) {
        MessagePart.THINKING -> AssistantPart.Thinking(delta)
        MessagePart.TEXT -> AssistantPart.Text(delta)
    }
    return next
}

internal fun groupToolActivity(blocks: List<ViewBlock>): List<ViewBlock> {
    val result = mutableListOf<ViewBlock>()
    for (block in blocks) {
        if (block !is ViewBlock.Assistant) {
            result += block
            continue
        }
        if (!block.live && block.tools.isEmpty()) continue
        val previous = result.lastOrNull()
        if (previous is ViewBlock.Assistant) {
            result[result.lastIndex] = previous.copy(
                live = block.live,
                tools = previous.tools + block.tools
            )
        } else {
            result += block
        }
    }
    return result
}

internal fun withLiveText(blocks: List<ViewBlock>, liveText: LiveText?): List<ViewBlock> {
    if (liveText == null || liveText.text.isEmpty()) return blocks
    val index = blocks.indexOfFirst { block ->
        block is ViewBlock.Message &&
            block.id == liveText.messageId &&
            block.payload is OutboundMessage.Text
    }
    if (index >= 0) {
        val message = blocks[index] as ViewBlock.Message
        val payload = message.payload as OutboundMessage.Text
        val updated = message.copy(payload = payload.copy(content = payload.content + liveText.text))
        return blocks.toMutableList().also { it[index] = updated }
    }
    return blocks + ViewBlock.Message(liveText.messageId, OutboundMessage.Text(liveText.text))
}

internal fun projectAgent(
    events: List<TranscriptEvent>,
    live: LiveAssistant? = null,
    extraResults: Map<String, ToolResult> = emptyMap()
): List<ViewBlock> {
    val blocks = mutableListOf<ViewBlock>()
    val results = linkedMapOf<String, ToolResult>()
    for ((id, result) in extraResults) results.putIfAbsent(id, result)
    val knownCalls = mutableSetOf<String>()
    for (event in events) {
        if (event is TranscriptEvent.Assistant) {
            for (part in event.parts) {
                if (part is AssistantPart.ToolCallPart) {
                    knownCalls += part.id
                    knownCalls += "${event.id}\u0000${part.id}"
                }
            }
        }
        if (event is TranscriptEvent.Tool) {
            val result = ToolResult(event.content, event.ok)
            results.putIfAbsent(event.toolCallId, result)
            val assistantId = event.assistantId
            if (assistantId != null) results.putIfAbsent("$assistantId\u0000${event.toolCallId}", result)
        }
    }
    for (event in events) {
        when (event) {
            is TranscriptEvent.User -> blocks += ViewBlock.User(
                id = event.id,
                text = event.text,
                attachments = event.attachments,
                widgetAnswerTo = event.widgetAnswerTo
            )
            is TranscriptEvent.Wake -> blocks += wakeBlock(event)
            is TranscriptEvent.Message -> blocks += ViewBlock.Message(event.id, event.payload)
            is TranscriptEvent.Compact -> blocks += ViewBlock.Notice(
                id = event.id,
                kind = "compact",
                text = "Earlier messages were summarized to fit the context window. The originals are still on disk."
            )
            is TranscriptEvent.Profile -> blocks += ViewBlock.Notice(
                id = event.id,
                kind = "profile",
                text = describeProfile(event)
            )
            is TranscriptEvent.Assistant -> {
                val causal = causalResults(event, results)
                val block = assistantBlock(event.id, event.parts, causal, live = false)
                if (block.thinking.isNotEmpty() || block.tools.isNotEmpty()) blocks += block
                blocks += outboundPeerBlocks(event.parts, causal)
            }
            is TranscriptEvent.Tool -> {
                val known = knownCalls.contains("${event.assistantId.orEmpty()}\u0000${event.toolCallId}") ||
                    knownCalls.contains(event.toolCallId)
                if (!known) {
                    blocks += ViewBlock.Assistant(
                        id = event.id,
                        thinking = "",
                        tools = listOf(
                            ToolView(
                                id = event.toolCallId,
                                name = event.name,
                                arguments = emptyMap(),
                                output = event.content,
                                status = if (event.ok == false) "error" else "ok"
                            )
                        )
                    )
                }
            }
        }
    }
    if (live != null && blocks.none { it is ViewBlock.Assistant && it.id == live.messageId }) {
        val block = assistantBlock(live.messageId, live.parts, extraResults, live = true)
        if (block.thinking.isNotEmpty() || block.tools.isNotEmpty()) blocks += block
        blocks += outboundPeerBlocks(live.parts, extraResults)
    }
    return blocks
}

private fun wakeBlock(event: TranscriptEvent.Wake): ViewBlock {
    val source = event.source
    if (source is WakeSource.Agent) {
        return ViewBlock.Peer(
            id = event.id,
            direction = "inbound",
            agentId = source.fromId,
            agentName = source.fromName,
            text = event.text,
            priority = source.priority
        )
    }
    val text = if (source is WakeSource.Work) {
        "Participated in room: ${source.workName}"
    } else {
        describeWake(event)
    }
    return ViewBlock.Notice(id = event.id, kind = "wake", text = text)
}

private fun describeWake(event: TranscriptEvent.Wake): String = when (val source = event.source) {
    is WakeSource.Agent -> {
        val priority = if (source.priority) " (priority)" else ""
        "From ${source.fromName}$priority: ${event.text}"
    }
    is WakeSource.Work -> {
        val task = if (source.taskId != null) " task ${source.taskId}" else ""
        "From Work ${source.workName}$task: ${event.text}"
    }
    is WakeSource.Routine -> "Routine ${source.routineName}: ${event.text}"
}

internal fun describeProfile(event: TranscriptEvent.Profile): String {
    val parts = mutableListOf<String>()
    if (event.name != null) parts += "name to \"${event.name}\""
    if (event.description != null) parts += "its description"
    if (event.tags != null) parts += "its tags"
    return if (parts.isEmpty()) {
        "This agent changed its profile."
    } else {
        "This agent changed ${parts.joinToString(" and ")}."
    }
}

private fun causalResults(
    event: TranscriptEvent.Assistant,
    results: Map<String, ToolResult>
): Map<String, ToolResult> {
    val causal = linkedMapOf<String, ToolResult>()
    for (part in event.parts) {
        if (part !is AssistantPart.ToolCallPart) continue
        val result = results["${event.id}\u0000${part.id}"] ?: results[part.id]
        if (result != null) causal[part.id] = result
    }
    return causal
}

internal fun assistantBlock(
    id: String,
    parts: List<AssistantPart>,
    results: Map<String, ToolResult>,
    live: Boolean
): ViewBlock.Assistant {
    val tools = parts.mapNotNull { part ->
        if (part !is AssistantPart.ToolCallPart) return@mapNotNull null
        if (part.name == "SendMessage") return@mapNotNull null
        if (part.name == "SendToAgent") {
            val result = results[part.id]
            if (result != null && result.ok != false) return@mapNotNull null
        }
        val result = results[part.id]
        ToolView(
            id = part.id,
            name = part.name,
            arguments = part.arguments,
            output = result?.content,
            status = when {
                result == null -> "pending"
                result.ok == false -> "error"
                else -> "ok"
            }
        )
    }
    val thinking = parts.filterIsInstance<AssistantPart.Thinking>().joinToString("") { it.text }
    return ViewBlock.Assistant(id = id, thinking = thinking, tools = tools, live = live)
}

private fun outboundPeerBlocks(
    parts: List<AssistantPart>,
    results: Map<String, ToolResult>
): List<ViewBlock.Peer> = parts.mapNotNull { part ->
    if (part !is AssistantPart.ToolCallPart || part.name != "SendToAgent") return@mapNotNull null
    val agentId = part.arguments["agent_id"] as? String
    val text = part.arguments["message"] as? String
    val result = results[part.id]
    if (agentId.isNullOrEmpty() || text.isNullOrEmpty() || result == null || result.ok == false) {
        return@mapNotNull null
    }
    ViewBlock.Peer(
        id = part.id,
        direction = "outbound",
        agentId = agentId,
        agentName = agentNameFromDelivery(result.content) ?: agentId,
        text = text,
        priority = part.arguments["priority"] == true
    )
}

private fun agentNameFromDelivery(content: String): String? {
    val match = Regex("^(?:Sent|Delivered) to (.+?)(?: as priority|,|\\.|$)").find(content)
    return match?.groupValues?.getOrNull(1)?.trim()?.ifEmpty { null }
}

internal fun mergeEvents(current: List<TranscriptEvent>, event: TranscriptEvent): List<TranscriptEvent> {
    return (current.filterNot { it.id == event.id } + event)
        .sortedWith(compareBy<TranscriptEvent> { it.seq }.thenBy { it.id })
}

internal fun transcriptTimestamps(events: List<TranscriptEvent>): Map<String, Long> {
    val timestamps = linkedMapOf<String, Long>()
    for (event in events) {
        timestamps[event.id] = event.createdAt
        if (event is TranscriptEvent.Assistant) {
            for (part in event.parts) {
                if (part is AssistantPart.ToolCallPart) timestamps[part.id] = event.createdAt
            }
        }
    }
    return timestamps
}

internal fun showTimeBefore(
    ids: List<String>,
    index: Int,
    timestamps: Map<String, Long>,
    zone: ZoneId = ZoneId.systemDefault()
): Long? {
    val id = ids.getOrNull(index) ?: return null
    val timestamp = timestamps[id] ?: return null
    if (index == 0) return timestamp
    val previous = timestamps[ids[index - 1]] ?: return timestamp
    val day = Instant.ofEpochMilli(timestamp).atZone(zone).toLocalDate()
    val previousDay = Instant.ofEpochMilli(previous).atZone(zone).toLocalDate()
    if (timestamp - previous >= 5 * 60 * 1000L || day != previousDay) return timestamp
    return null
}

internal fun hasExecutingTool(blocks: List<ViewBlock>): Boolean = blocks.any { block ->
    block is ViewBlock.Assistant && block.live && block.tools.any { it.status == "pending" }
}

internal fun widgetAnswers(blocks: List<ViewBlock>): Map<String, String> {
    val answers = linkedMapOf<String, String>()
    for (block in blocks) {
        if (block is ViewBlock.User) {
            val target = block.widgetAnswerTo ?: continue
            answers[target] = block.text
        }
    }
    return answers
}

internal fun fileNameOf(path: String): String {
    val name = path.substringAfterLast('/').substringAfterLast('\\')
    return name.ifBlank { path }
}

internal fun prettyJson(value: Any?): String = when (value) {
    null -> "null"
    is String -> buildString {
        append('"')
        value.forEach { char ->
            when (char) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> append(char)
            }
        }
        append('"')
    }
    is Number, is Boolean -> value.toString()
    is Map<*, *> -> {
        if (value.isEmpty()) {
            "{}"
        } else {
            value.entries.joinToString(separator = ",\n", prefix = "{\n", postfix = "\n}") { (key, nested) ->
                "  ${prettyJson(key?.toString())}: ${prettyJson(nested).prependIndent("  ").trimStart()}"
            }
        }
    }
    is Iterable<*> -> value.joinToString(prefix = "[", postfix = "]") { prettyJson(it) }
    else -> prettyJson(value.toString())
}

internal fun ensureToolCall(
    live: LiveAssistant?,
    toolCallId: String,
    toolName: String,
    arguments: Map<String, Any?>
): LiveAssistant {
    val messageId = live?.messageId ?: toolCallId
    val parts = (live?.parts ?: emptyList()).toMutableList()
    val exists = parts.any { it is AssistantPart.ToolCallPart && it.id == toolCallId }
    if (!exists) parts += AssistantPart.ToolCallPart(id = toolCallId, name = toolName, arguments = arguments)
    return LiveAssistant(messageId, parts)
}
