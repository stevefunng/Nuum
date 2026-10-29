package com.nuum.agent

import com.nuum.protocol.AssistantPart
import com.nuum.protocol.TranscriptEvent
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/**
 * A finished tool result that was written before the transcript line.
 * Claiming appends the missing tool event. It does not re-run the tool.
 */
@Serializable
data class ExecutionReceipt(
    val requestId: String,
    val runId: String,
    val name: String,
    val arguments: JsonObject = JsonObject(emptyMap()),
    val ok: Boolean,
    val output: String
)

fun claimExecutionResult(
    events: List<TranscriptEvent>,
    record: ExecutionReceipt,
    now: Long,
    newId: () -> String
): List<TranscriptEvent> {
    if (!record.requestId.startsWith("${record.runId}:")) {
        throw IllegalArgumentException("Execution result does not match its Host-owned run")
    }
    val toolCallId = record.requestId.removePrefix("${record.runId}:")
    if (events.any { it is TranscriptEvent.Tool && it.executionId == record.requestId }) return emptyList()
    val call = events.lastOrNull { event ->
        event is TranscriptEvent.Assistant && event.parts.any { part ->
            part is AssistantPart.ToolCall &&
                (part.executionId == record.requestId || (part.executionId == null && part.id == toolCallId))
        }
    } as? TranscriptEvent.Assistant
    if (call != null && events.any { event ->
            event is TranscriptEvent.Tool &&
                event.executionId == null &&
                event.assistantId == call.id &&
                event.toolCallId == toolCallId
        }
    ) {
        return emptyList()
    }
    val appended = mutableListOf<TranscriptEvent>()
    var seq = (events.maxOfOrNull { it.seq } ?: 0) + 1
    val assistantId = call?.id ?: "recovered-call:${record.requestId}"
    if (call == null) {
        appended += TranscriptEvent.Assistant(
            id = assistantId,
            seq = seq,
            createdAt = now,
            parts = listOf(
                AssistantPart.ToolCall(
                    id = toolCallId,
                    executionId = record.requestId,
                    name = record.name,
                    arguments = record.arguments
                )
            )
        )
        seq += 1
    }
    val original = call?.parts?.filterIsInstance<AssistantPart.ToolCall>()?.find { it.id == toolCallId }
    appended += TranscriptEvent.Tool(
        id = newId(),
        seq = seq,
        createdAt = now,
        assistantId = assistantId,
        toolCallId = toolCallId,
        executionId = record.requestId,
        name = original?.name ?: record.name,
        content = record.output,
        ok = record.ok
    )
    return appended
}
