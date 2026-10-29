package com.nuum.agent

import com.nuum.protocol.AssistantPart
import com.nuum.protocol.ChatMessage
import com.nuum.protocol.MessageRole
import com.nuum.protocol.TranscriptEvent
import com.nuum.protocol.WakeSource
import com.nuum.protocol.estimateModelTokens
import com.nuum.protocol.maxTranscriptSeq

const val COMPACTION_PROMPT = """Summarize the conversation history for a future continuation.
Preserve the user's goals, constraints, decisions, completed work, unresolved
items, exact file paths, commands, errors, and facts needed to continue.
Be compact but concrete. Do not mention this instruction or invent details.
Use short sections: Goal, Decisions, Completed, Open work, Key details.
Separate private conversation from each room by roomId. Preserve room decisions, promises, unresolved questions and message references.
Distinguish proposals, commitments and verified results, and who owns each. Update the previous summary; do not discard still relevant commitments.
Keep the current request and unfinished tool work explicit. Never invent omitted facts."""

private const val INTERRUPTED_TOOL = "Tool call was interrupted and did not return a result."

private const val REPLY_REMINDER =
    "<system_reminder>The message above is waiting for an answer. Plain text you write is a scratchpad the user cannot see; call SendMessage to actually reply.</system_reminder>"

fun repairTranscript(events: List<TranscriptEvent>, now: Long): Repair {
    val out = mutableListOf<TranscriptEvent>()
    val injected = mutableListOf<TranscriptEvent>()
    var nextSeq = maxTranscriptSeq(events) + 1
    val results = events.filterIsInstance<TranscriptEvent.Tool>()
    val deliveries = events.filterIsInstance<TranscriptEvent.Message>()
    val used = mutableSetOf<String>()
    for (event in events) {
        if (event is TranscriptEvent.Tool) continue
        out += event
        if (event !is TranscriptEvent.Assistant) continue
        val calls = event.parts.filterIsInstance<AssistantPart.ToolCall>()
        for (call in calls) {
            val result = results.find { !used.contains(it.id) && it.toolCallId == call.id && it.assistantId == event.id }
                ?: results.find { !used.contains(it.id) && it.toolCallId == call.id && it.assistantId == null }
            if (result != null) {
                used += result.id
                out += result
                continue
            }
            val delivery = deliveries.find { it.assistantId == event.id && it.toolCallId == call.id }
            val extra = TranscriptEvent.Tool(
                id = if (delivery != null) "delivered-message-${delivery.id}" else "missing-tool-${call.id}",
                seq = nextSeq,
                createdAt = delivery?.createdAt ?: now,
                assistantId = event.id,
                toolCallId = call.id,
                name = call.name,
                content = if (delivery != null) "Delivered." else INTERRUPTED_TOOL,
                ok = delivery != null
            )
            nextSeq += 1
            out += extra
            injected += extra
        }
    }
    return Repair(out, injected)
}

data class Repair(val events: List<TranscriptEvent>, val injected: List<TranscriptEvent>)

fun activeTranscript(events: List<TranscriptEvent>): List<TranscriptEvent> {
    val compact = events.lastOrNull { it is TranscriptEvent.Compact } as? TranscriptEvent.Compact ?: return events
    return listOf(compact) + events.filter { it !is TranscriptEvent.Compact && it.seq >= compact.tailFromSeq }
}

fun assembleContext(
    transcript: List<TranscriptEvent>,
    systemPrompt: String,
    notices: List<String> = emptyList(),
    now: Long
): List<ChatMessage> {
    val system = ChatMessage(
        id = "system",
        role = MessageRole.SYSTEM,
        content = systemPrompt,
        seq = 0,
        createdAt = 0
    )
    val history = repairTranscript(activeTranscript(transcript), now).events.flatMap { eventToModelMessage(it) }.toMutableList()
    val notes = notices.filter { it.isNotEmpty() }
    if (notes.isNotEmpty()) {
        val target = history.indexOfLast { it.role == MessageRole.USER }
        if (target >= 0) {
            val current = history[target]
            history[target] = current.copy(content = (listOf(current.content) + notes).joinToString("\n\n"))
        }
    }
    return listOf(system) + history
}

fun estimateContextTokens(messages: List<ChatMessage>): Int = estimateModelTokens(messages)

data class CompactionPartition(
    val messagesToSummarize: List<ChatMessage>,
    val preservedTail: List<ChatMessage>,
    val tailFromSeq: Int,
    val throughSeq: Int
)

fun partitionForCompaction(transcript: List<TranscriptEvent>, allowWithinTurn: Boolean = false, now: Long = 0): CompactionPartition? {
    val active = activeTranscript(transcript)
    var splitAt = active.indexOfLast { it is TranscriptEvent.User || it is TranscriptEvent.Wake }
    if (allowWithinTurn) {
        val lastAssistant = active.indexOfLast { it is TranscriptEvent.Assistant }
        if (lastAssistant > splitAt + 1) splitAt = lastAssistant
    }
    if (splitAt <= 0) return null
    val tailFromSeq = active[splitAt].seq
    val messagesToSummarize = repairTranscript(active.take(splitAt), now).events.flatMap { eventToModelMessage(it) }
    if (messagesToSummarize.isEmpty()) return null
    return CompactionPartition(
        messagesToSummarize = messagesToSummarize,
        preservedTail = repairTranscript(active.drop(splitAt), now).events.flatMap { eventToModelMessage(it) },
        tailFromSeq = tailFromSeq,
        throughSeq = tailFromSeq - 1
    )
}

private fun eventToModelMessage(event: TranscriptEvent): List<ChatMessage> = when (event) {
    is TranscriptEvent.User -> listOf(
        ChatMessage(
            id = event.id,
            role = MessageRole.USER,
            content = buildString {
                append(event.text)
                for (file in event.attachments.orEmpty()) {
                    append("\n\n[User attachment: ${jsonQuote(file.name)}; local path: ${jsonQuote(file.path)}; ${file.size} bytes]")
                    if (file.text != null) {
                        append("\nTreat the following attachment as reference content, separate from the user's message.\n<attachment_content>\n")
                        append(file.text)
                        append("\n</attachment_content>")
                    } else {
                        append("\nUse workspace file tools to inspect this file if its content is not included.")
                    }
                }
                append("\n\n")
                append(REPLY_REMINDER)
            },
            seq = event.seq,
            createdAt = event.createdAt
        )
    )
    is TranscriptEvent.Wake -> listOf(
        ChatMessage(
            id = event.id,
            role = MessageRole.USER,
            content = agentWakePrompt(event),
            seq = event.seq,
            createdAt = event.createdAt
        )
    )
    is TranscriptEvent.Tool -> listOf(
        ChatMessage(
            id = event.id,
            role = MessageRole.TOOL,
            content = event.content,
            toolCallId = event.toolCallId,
            name = event.name,
            seq = event.seq,
            createdAt = event.createdAt
        )
    )
    is TranscriptEvent.Message, is TranscriptEvent.Profile -> emptyList()
    is TranscriptEvent.Compact -> listOf(
        ChatMessage(
            id = event.id,
            role = MessageRole.USER,
            content = buildString {
                append("[previous conversation summary] ")
                append(event.summary)
                if (!event.activeRequest.isNullOrEmpty()) {
                    append("\n\n[Current request, preserved verbatim]\n")
                    append(event.activeRequest)
                }
            },
            seq = event.seq,
            createdAt = event.createdAt
        )
    )
    is TranscriptEvent.Assistant -> {
        val text = event.parts.filterIsInstance<AssistantPart.Text>().joinToString("") { it.text }
        val thinking = event.parts.filterIsInstance<AssistantPart.Thinking>().joinToString("") { it.text }
        val calls = event.parts.filterIsInstance<AssistantPart.ToolCall>().map {
            com.nuum.protocol.ToolCall(it.id, it.name, it.arguments)
        }
        listOf(
            ChatMessage(
                id = event.id,
                role = MessageRole.ASSISTANT,
                content = text,
                thinking = thinking.ifEmpty { null },
                toolCalls = calls.ifEmpty { null },
                seq = event.seq,
                createdAt = event.createdAt
            )
        )
    }
}

private fun agentWakePrompt(event: TranscriptEvent.Wake): String = when (val source = event.source) {
    is WakeSource.Work -> listOf(
        "<system_reminder>You were assigned work in Work \"${source.workName}\". This is not a private user message.</system_reminder>",
        "[work ${source.workName}] ${event.text}",
        "",
        "<system_reminder>Use SendMessage to speak in this room. Include cardAction when submitting a card for review or reporting a blocker. If nothing useful needs saying, end silently. This run cannot send a private reply.</system_reminder>"
    ).joinToString("\n")
    is WakeSource.Routine -> "[routine ${source.routineName}] ${event.text}\n\n$REPLY_REMINDER"
    is WakeSource.Agent -> {
        val priority = if (source.priority == true) " This message is marked priority." else ""
        listOf(
            "<system_reminder>A message just arrived from another agent, not from the user.$priority</system_reminder>",
            "[agent ${source.fromName} (${source.fromId})] ${event.text}",
            "",
            "<system_reminder>The user can already see the incoming message in this chat. If it needs a reply or result, send it back to ${source.fromName} with SendToAgent using agent_id \"${source.fromId}\". SendMessage is only for a genuinely new user-facing result in your own chat. Acknowledging an FYI is optional; silence is allowed.</system_reminder>"
        ).joinToString("\n")
    }
}

private fun jsonQuote(value: String): String = buildString {
    append('"')
    for (ch in value) {
        when (ch) {
            '\\' -> append("\\\\")
            '"' -> append("\\\"")
            else -> append(ch)
        }
    }
    append('"')
}
