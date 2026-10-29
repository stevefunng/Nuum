package com.nuum.agent

import com.nuum.contracts.AgentStore
import com.nuum.protocol.ProtocolJson
import com.nuum.protocol.TranscriptEvent
import com.nuum.protocol.WorkEvent
import com.nuum.protocol.tryParseTranscriptLine
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer

internal suspend fun <T> AgentStore.readDoc(path: String, serializer: KSerializer<T>): T? {
    val text = readText(path)?.trim()?.ifEmpty { null } ?: return null
    return try {
        ProtocolJson.decodeFromString(serializer, text)
    } catch (_: Exception) {
        null
    }
}

internal suspend fun <T> AgentStore.writeDoc(path: String, serializer: KSerializer<T>, value: T) {
    writeTextAtomic(path, ProtocolJson.encodeToString(serializer, value) + "\n")
}

internal suspend fun AgentStore.readTranscript(path: String): List<TranscriptEvent> {
    val raw = readText(path) ?: return emptyList()
    val committed = if (raw.endsWith("\n")) raw else raw.substringBeforeLast('\n', missingDelimiterValue = "")
    if (committed.isEmpty()) return emptyList()
    return committed.lineSequence().filter { it.isNotBlank() }.mapNotNull { tryParseTranscriptLine(it) }.toList()
}

internal suspend fun AgentStore.appendTranscript(path: String, event: TranscriptEvent) {
    appendLine(path, ProtocolJson.encodeToString(TranscriptEvent.serializer(), event))
}

internal suspend fun AgentStore.readWorkEvents(path: String): List<WorkEvent> {
    val raw = readText(path) ?: return emptyList()
    val committed = if (raw.endsWith("\n")) raw else raw.substringBeforeLast('\n', missingDelimiterValue = "")
    if (committed.isEmpty()) return emptyList()
    return committed.lineSequence().filter { it.isNotBlank() }.mapNotNull { line ->
        try {
            ProtocolJson.decodeFromString(WorkEvent.serializer(), line)
        } catch (_: Exception) {
            null
        }
    }.toList()
}

internal suspend fun AgentStore.appendWork(path: String, event: WorkEvent) {
    appendLine(path, ProtocolJson.encodeToString(WorkEvent.serializer(), event))
}

internal suspend fun AgentStore.readReceipts(path: String): List<ExecutionReceipt> {
    val text = readText(path)?.trim()?.ifEmpty { null } ?: return emptyList()
    return try {
        ProtocolJson.decodeFromString(ListSerializer(ExecutionReceipt.serializer()), text)
    } catch (_: Exception) {
        emptyList()
    }
}
