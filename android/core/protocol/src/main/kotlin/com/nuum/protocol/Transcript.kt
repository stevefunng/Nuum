@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

package com.nuum.protocol

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

@Serializable
data class OutboundImage(val path: String, val alt: String? = null)

@Serializable
enum class WidgetOptionStyle {
    @SerialName("default") DEFAULT,
    @SerialName("primary") PRIMARY,
    @SerialName("danger") DANGER
}

@Serializable
data class WidgetOption(
    val label: String,
    val value: String? = null,
    val description: String? = null,
    val style: WidgetOptionStyle? = null
)

@Serializable
data class WidgetPayload(
    val prompt: String,
    val helpText: String? = null,
    val options: List<WidgetOption>,
    val allowCustom: Boolean? = null
)

@Serializable(with = OutboundMessageSerializer::class)
sealed interface OutboundMessage {
    @Serializable
    data class Text(val content: String, val images: List<OutboundImage>? = null) : OutboundMessage

    @Serializable
    data class Attachment(val path: String, val caption: String? = null) : OutboundMessage

    @Serializable
    data class Widget(val widget: WidgetPayload) : OutboundMessage

    @Serializable
    data class LegacyWidget(val widget: String, val props: JsonObject? = null) : OutboundMessage
}

@OptIn(ExperimentalSerializationApi::class)
object OutboundMessageSerializer : KSerializer<OutboundMessage> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("OutboundMessage")

    override fun deserialize(decoder: Decoder): OutboundMessage {
        val json = decoder as? JsonDecoder ?: error("OutboundMessage requires JSON")
        return parseOutboundMessage(json.decodeJsonElement())
    }

    override fun serialize(encoder: Encoder, value: OutboundMessage) {
        val json = encoder as? JsonEncoder ?: error("OutboundMessage requires JSON")
        json.encodeJsonElement(outboundToJson(value))
    }
}

fun parseOutboundMessage(raw: JsonElement): OutboundMessage {
    val obj = raw as? JsonObject
        ?: throw ProtocolParseException(listOf(ProtocolIssue(emptyList(), "Expected an object")))
    val normalized = normalizeOutbound(obj)
    return when (val type = jsonString(normalized, "type")) {
        "text" -> parseTextOutbound(normalized)
        "attachment" -> parseAttachmentOutbound(normalized)
        "widget" -> parseWidgetOutbound(normalized)
        else -> throw ProtocolParseException(
            listOf(ProtocolIssue(listOf("type"), "type must be text, attachment, or widget. Nothing was sent."))
        )
    }
}

/** Legacy `text` payloads and string image paths are normalized before the union runs. */
fun normalizeOutbound(raw: JsonObject): JsonObject {
    if (jsonString(raw, "type") != "text") return raw
    val normalized = raw.toMutableMap()
    val legacyText = raw["text"]
    if (legacyText is JsonPrimitive && legacyText.isString && "content" !in raw) {
        normalized["content"] = legacyText
    }
    val images = raw["images"]
    if (images is JsonArray) {
        normalized["images"] = JsonArray(images.map { image ->
            if (image is JsonPrimitive && image.isString) JsonObject(mapOf("path" to image)) else image
        })
    }
    return JsonObject(normalized)
}

private fun parseTextOutbound(raw: JsonObject): OutboundMessage.Text {
    val content = jsonString(raw, "content")
        ?: throw ProtocolParseException(listOf(ProtocolIssue(listOf("content"), "content is required when type is text. Nothing was sent.")))
    val images = when (val value = raw["images"]) {
        null, is JsonNull -> null
        is JsonArray -> value.mapIndexed { index, image ->
            val obj = image as? JsonObject
                ?: throw ProtocolParseException(listOf(ProtocolIssue(listOf("images", index.toString()), "Expected an image object")))
            val path = jsonString(obj, "path")
                ?: throw ProtocolParseException(listOf(ProtocolIssue(listOf("images", index.toString(), "path"), "path is required")))
            OutboundImage(path = path, alt = jsonString(obj, "alt"))
        }
        else -> throw ProtocolParseException(listOf(ProtocolIssue(listOf("images"), "Expected an array")))
    }
    return OutboundMessage.Text(content, images)
}

private fun parseAttachmentOutbound(raw: JsonObject): OutboundMessage.Attachment {
    val path = jsonString(raw, "path")
        ?: throw ProtocolParseException(listOf(ProtocolIssue(listOf("path"), "path is required when type is attachment. Nothing was sent.")))
    return OutboundMessage.Attachment(path, jsonString(raw, "caption"))
}

private fun parseWidgetOutbound(raw: JsonObject): OutboundMessage {
    return when (val widget = raw["widget"]) {
        is JsonPrimitive -> {
            if (!widget.isString) {
                throw ProtocolParseException(listOf(ProtocolIssue(listOf("widget"), "widget is required when type is widget: an object with prompt and options. Nothing was sent.")))
            }
            val props = when (val value = raw["props"]) {
                null, is JsonNull -> null
                is JsonObject -> value
                else -> throw ProtocolParseException(listOf(ProtocolIssue(listOf("props"), "Expected an object")))
            }
            OutboundMessage.LegacyWidget(widget.content, props)
        }
        is JsonObject -> OutboundMessage.Widget(parseWidgetPayload(widget))
        else -> throw ProtocolParseException(
            listOf(ProtocolIssue(listOf("widget"), "widget is required when type is widget: an object with prompt and options. Nothing was sent."))
        )
    }
}

private fun parseWidgetPayload(raw: JsonObject): WidgetPayload {
    val prompt = jsonString(raw, "prompt")?.takeIf { it.isNotEmpty() }
        ?: throw ProtocolParseException(listOf(ProtocolIssue(listOf("widget", "prompt"), "String must contain at least 1 character(s)")))
    val optionsRaw = raw["options"] as? JsonArray
        ?: throw ProtocolParseException(listOf(ProtocolIssue(listOf("widget", "options"), "Required")))
    if (optionsRaw.isEmpty() || optionsRaw.size > 6) {
        throw ProtocolParseException(listOf(ProtocolIssue(listOf("widget", "options"), "Array must contain between 1 and 6 element(s)")))
    }
    val options = optionsRaw.mapIndexed { index, element ->
        val obj = element as? JsonObject
            ?: throw ProtocolParseException(listOf(ProtocolIssue(listOf("widget", "options", index.toString()), "Expected an object")))
        val label = jsonString(obj, "label")?.takeIf { it.isNotEmpty() }
            ?: throw ProtocolParseException(listOf(ProtocolIssue(listOf("widget", "options", index.toString(), "label"), "String must contain at least 1 character(s)")))
        val style = jsonString(obj, "style")?.let { wire ->
            WidgetOptionStyle.entries.firstOrNull { ProtocolJson.encodeToString(WidgetOptionStyle.serializer(), it).trim('"') == wire }
                ?: throw ProtocolParseException(listOf(ProtocolIssue(listOf("widget", "options", index.toString(), "style"), "Invalid enum value")))
        }
        WidgetOption(label = label, value = jsonString(obj, "value"), description = jsonString(obj, "description"), style = style)
    }
    val allowCustom = when (val value = raw["allowCustom"]) {
        null, is JsonNull -> null
        is JsonPrimitive -> value.booleanOrNull
            ?: throw ProtocolParseException(listOf(ProtocolIssue(listOf("widget", "allowCustom"), "Expected a boolean")))
        else -> throw ProtocolParseException(listOf(ProtocolIssue(listOf("widget", "allowCustom"), "Expected a boolean")))
    }
    return WidgetPayload(prompt = prompt, helpText = jsonString(raw, "helpText"), options = options, allowCustom = allowCustom)
}

private fun outboundToJson(value: OutboundMessage): JsonObject = when (value) {
    is OutboundMessage.Text -> buildJsonObject {
        put("type", "text")
        put("content", value.content)
        value.images?.let { images ->
            put("images", JsonArray(images.map { image ->
                buildJsonObject {
                    put("path", image.path)
                    image.alt?.let { put("alt", it) }
                }
            }))
        }
    }
    is OutboundMessage.Attachment -> buildJsonObject {
        put("type", "attachment")
        put("path", value.path)
        value.caption?.let { put("caption", it) }
    }
    is OutboundMessage.Widget -> buildJsonObject {
        put("type", "widget")
        put("widget", ProtocolJson.encodeToJsonElement(WidgetPayload.serializer(), value.widget))
    }
    is OutboundMessage.LegacyWidget -> buildJsonObject {
        put("type", "widget")
        put("widget", value.widget)
        value.props?.let { put("props", it) }
    }
}

private fun jsonString(obj: JsonObject, key: String): String? {
    val raw = obj[key] as? JsonPrimitive ?: return null
    if (raw is JsonNull || !raw.isString) return null
    return raw.content
}

@Serializable
sealed interface AssistantPart {
    @Serializable
    @SerialName("thinking")
    data class Thinking(val text: String) : AssistantPart

    @Serializable
    @SerialName("text")
    data class Text(val text: String) : AssistantPart

    @Serializable
    @SerialName("tool_call")
    data class ToolCall(
        val id: String,
        val executionId: String? = null,
        val name: String,
        val arguments: JsonObject
    ) : AssistantPart
}

@Serializable
enum class RoomInputMode {
    @SerialName("background") BACKGROUND,
    @SerialName("continuation") CONTINUATION
}

@Serializable
data class RoomInput(
    val membershipRevision: Int,
    val fromSeq: Int,
    val throughSeq: Int,
    val messageIds: List<String>,
    val epoch: Int? = null,
    val mode: RoomInputMode? = null
)

@Serializable
@kotlinx.serialization.json.JsonClassDiscriminator("kind")
sealed interface WakeSource {
    @Serializable
    @SerialName("agent")
    data class Agent(val fromId: String, val fromName: String, val priority: Boolean? = null) : WakeSource

    @Serializable
    @SerialName("work")
    data class Work(
        val workId: String,
        val workName: String,
        val bridgeId: String,
        val taskId: String? = null,
        val roomInput: RoomInput? = null
    ) : WakeSource

    /** Not produced in this version. Placeholder for a later scheduled wake. */
    @Serializable
    @SerialName("routine")
    data class Routine(val routineId: String, val routineName: String) : WakeSource
}

@Serializable
data class ProfilePatch(
    val name: String? = null,
    val description: String? = null,
    val tags: List<String>? = null
)

@Serializable
data class CompactRoomInput(
    val workId: String,
    val membershipRevision: Int,
    val throughSeq: Int
)

@Serializable
sealed interface TranscriptEvent {
    val id: String
    val seq: Int
    val createdAt: Long

    @Serializable
    @SerialName("user")
    data class User(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val text: String,
        val attachments: List<UserAttachment>? = null,
        val widgetAnswerTo: String? = null
    ) : TranscriptEvent

    @Serializable
    @SerialName("wake")
    data class Wake(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val source: WakeSource,
        val text: String,
        val hops: Int = 0
    ) : TranscriptEvent

    @Serializable
    @SerialName("assistant")
    data class Assistant(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val parts: List<AssistantPart>
    ) : TranscriptEvent

    @Serializable
    @SerialName("tool")
    data class Tool(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val assistantId: String? = null,
        val toolCallId: String,
        val executionId: String? = null,
        val permissionTaskKey: String? = null,
        val name: String,
        val content: String,
        val ok: Boolean? = null,
        val spillPath: String? = null
    ) : TranscriptEvent

    @Serializable
    @SerialName("message")
    data class Message(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val assistantId: String? = null,
        val toolCallId: String? = null,
        val payload: OutboundMessage
    ) : TranscriptEvent

    @Serializable
    @SerialName("compact")
    data class Compact(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val epoch: Int,
        val throughSeq: Int,
        val tailFromSeq: Int,
        val summary: String,
        val activeRequest: String? = null,
        val roomInputs: List<CompactRoomInput>? = null
    ) : TranscriptEvent

    @Serializable
    @SerialName("profile")
    data class Profile(
        override val id: String,
        override val seq: Int,
        override val createdAt: Long,
        val patch: ProfilePatch
    ) : TranscriptEvent
}

@Serializable
data class LiveAssistant(val messageId: String, val parts: List<AssistantPart>)

@Serializable
enum class ToolRunStatus {
    @SerialName("pending") PENDING,
    @SerialName("ok") OK,
    @SerialName("error") ERROR
}

@Serializable
data class ToolView(
    val id: String,
    val name: String,
    val arguments: JsonObject,
    val output: String? = null,
    val status: ToolRunStatus
)

@Serializable
enum class PeerDirection {
    @SerialName("inbound") INBOUND,
    @SerialName("outbound") OUTBOUND
}

@Serializable
enum class NoticeKind {
    @SerialName("wake") WAKE,
    @SerialName("profile") PROFILE,
    @SerialName("compact") COMPACT
}

@Serializable
sealed interface ViewBlock {
    @Serializable
    @SerialName("user")
    data class User(
        val id: String,
        val text: String,
        val attachments: List<UserAttachment>? = null,
        val widgetAnswerTo: String? = null
    ) : ViewBlock

    @Serializable
    @SerialName("assistant")
    data class Assistant(
        val id: String,
        val thinking: String,
        val tools: List<ToolView>,
        val live: Boolean? = null
    ) : ViewBlock

    @Serializable
    @SerialName("message")
    data class Message(val id: String, val payload: OutboundMessage) : ViewBlock

    @Serializable
    @SerialName("peer")
    data class Peer(
        val id: String,
        val direction: PeerDirection,
        val agentId: String,
        val agentName: String,
        val text: String,
        val priority: Boolean
    ) : ViewBlock

    @Serializable
    @SerialName("notice")
    data class Notice(val id: String, val kind: NoticeKind, val text: String) : ViewBlock
}

@Serializable
data class AgentProjection(val blocks: List<ViewBlock>)

fun maxTranscriptSeq(events: List<TranscriptEvent>): Int =
    events.fold(0) { max, event -> maxOf(max, event.seq) }

fun eventFromChatMessage(message: ChatMessage): TranscriptEvent? = when (message.role) {
    MessageRole.SYSTEM -> null
    MessageRole.USER -> TranscriptEvent.User(
        id = message.id,
        seq = message.seq,
        createdAt = message.createdAt,
        text = message.content
    )
    MessageRole.TOOL -> TranscriptEvent.Tool(
        id = message.id,
        seq = message.seq,
        createdAt = message.createdAt,
        toolCallId = message.toolCallId ?: "",
        name = message.name ?: "",
        content = message.content
    )
    MessageRole.ASSISTANT -> {
        val parts = mutableListOf<AssistantPart>()
        if (!message.thinking.isNullOrEmpty()) parts += AssistantPart.Thinking(message.thinking)
        if (message.content.isNotEmpty()) parts += AssistantPart.Text(message.content)
        for (call in message.toolCalls.orEmpty()) {
            parts += AssistantPart.ToolCall(id = call.id, name = call.name, arguments = call.arguments)
        }
        TranscriptEvent.Assistant(
            id = message.id,
            seq = message.seq,
            createdAt = message.createdAt,
            parts = parts
        )
    }
}

fun parseTranscriptLine(raw: JsonElement): TranscriptEvent? {
    val obj = raw as? JsonObject ?: throw ProtocolParseException(listOf(ProtocolIssue(emptyList(), "Expected an object")))
    if ("type" in obj && "role" !in obj) {
        return ProtocolJson.decodeFromJsonElement(TranscriptEvent.serializer(), obj)
    }
    return eventFromChatMessage(ProtocolJson.decodeFromJsonElement(ChatMessage.serializer(), obj))
}

/** A bad line is skipped. One corrupt JSONL row must not wipe the transcript. */
fun tryParseTranscriptLine(line: String): TranscriptEvent? = try {
    parseTranscriptLine(ProtocolJson.parseToJsonElement(line))
} catch (_: Exception) {
    null
}

fun appendAssistantDelta(parts: List<AssistantPart>, kind: String, delta: String): List<AssistantPart> {
    val next = parts.toMutableList()
    val last = next.lastOrNull()
    if (kind == "text" && last is AssistantPart.Text) {
        next[next.lastIndex] = last.copy(text = last.text + delta)
        return next
    }
    if (kind == "thinking" && last is AssistantPart.Thinking) {
        next[next.lastIndex] = last.copy(text = last.text + delta)
        return next
    }
    next += if (kind == "thinking") AssistantPart.Thinking(delta) else AssistantPart.Text(delta)
    return next
}

fun appendAssistantToolCall(parts: List<AssistantPart>, call: AssistantPart.ToolCall): List<AssistantPart> =
    parts + call

private data class ToolResult(val content: String, val ok: Boolean?)

fun projectAgent(events: List<TranscriptEvent>, live: LiveAssistant? = null): AgentProjection {
    val blocks = mutableListOf<ViewBlock>()
    val results = linkedMapOf<String, ToolResult>()
    val knownCalls = mutableSetOf<String>()
    for (event in events) {
        if (event is TranscriptEvent.Assistant) {
            for (part in event.parts) {
                if (part is AssistantPart.ToolCall) {
                    knownCalls += part.id
                    knownCalls += "${event.id}\u0000${part.id}"
                }
            }
        }
        if (event is TranscriptEvent.Tool) {
            val result = ToolResult(event.content, event.ok)
            if (event.toolCallId !in results) results[event.toolCallId] = result
            if (event.assistantId != null) results["${event.assistantId}\u0000${event.toolCallId}"] = result
        }
    }
    for (event in events) {
        when (event) {
            is TranscriptEvent.User -> blocks += ViewBlock.User(
                id = event.id,
                text = event.text,
                attachments = event.attachments?.takeIf { it.isNotEmpty() },
                widgetAnswerTo = event.widgetAnswerTo?.takeIf { it.isNotEmpty() }
            )
            is TranscriptEvent.Wake -> {
                val source = event.source
                if (source is WakeSource.Agent) {
                    blocks += ViewBlock.Peer(
                        id = event.id,
                        direction = PeerDirection.INBOUND,
                        agentId = source.fromId,
                        agentName = source.fromName,
                        text = event.text,
                        priority = source.priority == true
                    )
                } else {
                    val text = if (source is WakeSource.Work) {
                        "Participated in room: ${source.workName}"
                    } else {
                        describeWake(event)
                    }
                    blocks += ViewBlock.Notice(event.id, NoticeKind.WAKE, text)
                }
            }
            is TranscriptEvent.Message -> blocks += ViewBlock.Message(event.id, event.payload)
            is TranscriptEvent.Compact -> blocks += ViewBlock.Notice(
                id = event.id,
                kind = NoticeKind.COMPACT,
                text = "Earlier messages were summarized to fit the context window. The originals are still on disk."
            )
            is TranscriptEvent.Profile -> blocks += ViewBlock.Notice(
                id = event.id,
                kind = NoticeKind.PROFILE,
                text = describeProfilePatch(event.patch)
            )
            is TranscriptEvent.Assistant -> {
                val causal = linkedMapOf<String, ToolResult>()
                for (part in event.parts) {
                    if (part !is AssistantPart.ToolCall) continue
                    val result = results["${event.id}\u0000${part.id}"] ?: results[part.id]
                    if (result != null) causal[part.id] = result
                }
                val block = assistantBlock(event.id, event.parts, causal, live = false)
                if (block.thinking.isNotEmpty() || block.tools.isNotEmpty()) blocks += block
                blocks += outboundPeerBlocks(event.parts, causal)
            }
            is TranscriptEvent.Tool -> {
                if ("${event.assistantId ?: ""}\u0000${event.toolCallId}" in knownCalls || event.toolCallId in knownCalls) {
                    continue
                }
                blocks += ViewBlock.Assistant(
                    id = event.id,
                    thinking = "",
                    tools = listOf(
                        ToolView(
                            id = event.toolCallId,
                            name = event.name,
                            arguments = JsonObject(emptyMap()),
                            output = event.content,
                            status = if (event.ok == false) ToolRunStatus.ERROR else ToolRunStatus.OK
                        )
                    )
                )
            }
        }
    }
    if (live != null && blocks.none { it is ViewBlock.Assistant && it.id == live.messageId }) {
        val block = assistantBlock(live.messageId, live.parts, emptyMap(), live = true)
        if (block.thinking.isNotEmpty() || block.tools.isNotEmpty()) blocks += block
        blocks += outboundPeerBlocks(live.parts, emptyMap())
    }
    return AgentProjection(blocks)
}

private fun assistantBlock(
    id: String,
    parts: List<AssistantPart>,
    results: Map<String, ToolResult>,
    live: Boolean
): ViewBlock.Assistant {
    val tools = parts.filterIsInstance<AssistantPart.ToolCall>().filter { part ->
        if (part.name == "SendMessage") return@filter false
        if (part.name != "SendToAgent") return@filter true
        val result = results[part.id]
        result == null || result.ok == false
    }.map { part ->
        val result = results[part.id]
        ToolView(
            id = part.id,
            name = part.name,
            arguments = part.arguments,
            output = result?.content,
            status = when {
                result == null -> ToolRunStatus.PENDING
                result.ok == false -> ToolRunStatus.ERROR
                else -> ToolRunStatus.OK
            }
        )
    }
    return ViewBlock.Assistant(
        id = id,
        thinking = parts.filterIsInstance<AssistantPart.Thinking>().joinToString("") { it.text },
        tools = tools,
        live = if (live) true else null
    )
}

private fun outboundPeerBlocks(parts: List<AssistantPart>, results: Map<String, ToolResult>): List<ViewBlock.Peer> =
    parts.mapNotNull { part ->
        if (part !is AssistantPart.ToolCall || part.name != "SendToAgent") return@mapNotNull null
        val agentId = stringArgument(part.arguments, "agent_id") ?: return@mapNotNull null
        val text = stringArgument(part.arguments, "message") ?: return@mapNotNull null
        val result = results[part.id] ?: return@mapNotNull null
        if (result.ok == false) return@mapNotNull null
        ViewBlock.Peer(
            id = part.id,
            direction = PeerDirection.OUTBOUND,
            agentId = agentId,
            agentName = agentNameFromDelivery(result.content) ?: agentId,
            text = text,
            priority = (part.arguments["priority"] as? JsonPrimitive)?.booleanOrNull == true
        )
    }

private fun stringArgument(arguments: JsonObject, key: String): String? {
    val value = arguments[key] as? JsonPrimitive ?: return null
    if (!value.isString || value.content.isEmpty()) return null
    return value.content
}

private val deliveryName = Regex("""^(?:Sent|Delivered) to (.+?)(?: as priority|,|\.|$)""")

private fun agentNameFromDelivery(content: String?): String? {
    if (content.isNullOrEmpty()) return null
    val name = deliveryName.find(content)?.groupValues?.getOrNull(1)?.trim().orEmpty()
    return name.ifEmpty { null }
}

fun describeWake(event: TranscriptEvent.Wake): String = when (val source = event.source) {
    is WakeSource.Agent -> {
        val priority = if (source.priority == true) " (priority)" else ""
        "From ${source.fromName}$priority: ${event.text}"
    }
    is WakeSource.Work -> {
        val task = if (source.taskId != null) " task ${source.taskId}" else ""
        "From Work ${source.workName}$task: ${event.text}"
    }
    is WakeSource.Routine -> "Routine ${source.routineName}: ${event.text}"
}

private fun describeProfilePatch(patch: ProfilePatch): String {
    val parts = mutableListOf<String>()
    if (patch.name != null) parts += "name to \"${patch.name}\""
    if (patch.description != null) parts += "its description"
    if (patch.tags != null) parts += "its tags"
    return if (parts.isNotEmpty()) "This agent changed ${parts.joinToString(" and ")}." else "This agent changed its profile."
}
