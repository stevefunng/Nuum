@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

package com.nuum.protocol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonClassDiscriminator
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull

object DelegatedToolNames {
    const val createTask = "CreateTask"
    const val claimTask = "ClaimTask"
    const val readTask = "ReadTask"
    const val sendMessage = "SendMessage"
    const val updateState = "update_state"
    const val createAgent = "CreateAgent"
    const val updateAgent = "UpdateAgent"
    const val sendToAgent = "SendToAgent"
    const val readAgentTranscript = "ReadAgentTranscript"
    const val checkAgent = "CheckAgent"
    const val stopAgent = "StopAgent"
    const val postToWork = "PostToWork"
    const val handoffTask = "HandoffTask"
    const val readWorkTimeline = "ReadWorkTimeline"
    const val runWorkCli = "RunWorkCLI"
    const val delegateWork = "DelegateWork"
}

private val outboundFieldTypes: Map<String, List<String>> = linkedMapOf(
    "content" to listOf("text"),
    "images" to listOf("text"),
    "path" to listOf("attachment"),
    "caption" to listOf("attachment"),
    "widget" to listOf("widget"),
    "props" to listOf("widget")
)

/**
 * Field misuse is reported before [OutboundMessage] parsing so a `path` on
 * `type:text` is not silently dropped. The sentences are returned to the model unchanged.
 */
fun parseSendMessage(args: JsonObject): OutboundMessage {
    val issues = mutableListOf<ProtocolIssue>()
    val type = (args["type"] as? JsonPrimitive)?.takeIf { it.isString }?.content
    if (type != null) {
        for ((field, allowed) in outboundFieldTypes) {
            if (field in args && type !in allowed) {
                issues += ProtocolIssue(
                    listOf(field),
                    "$field is only valid with type:${allowed.joinToString(" or ")}, not type:$type — it would be silently dropped. Nothing was sent. Re-send as separate SendMessage calls, one per type."
                )
            }
        }
        if (type == "text" && contentMissing(args) && "text" !in args) {
            issues += ProtocolIssue(listOf("content"), "content is required when type is text. Nothing was sent.")
        }
        if (type == "attachment" && pathMissing(args)) {
            issues += ProtocolIssue(listOf("path"), "path is required when type is attachment. Nothing was sent.")
        }
        if (type == "widget" && "widget" !in args) {
            issues += ProtocolIssue(
                listOf("widget"),
                "widget is required when type is widget: an object with prompt and options. Nothing was sent."
            )
        }
    }
    if (issues.isNotEmpty()) throw ProtocolParseException(issues)
    return parseOutboundMessage(normalizeOutbound(args))
}

private fun contentMissing(args: JsonObject): Boolean {
    if ("content" !in args) return true
    val content = args["content"] as? JsonPrimitive ?: return false
    return content.isString && content.content.isEmpty()
}

private fun pathMissing(args: JsonObject): Boolean {
    if ("path" !in args) return true
    val path = args["path"] as? JsonPrimitive ?: return false
    return path.isString && path.content.isEmpty()
}

@Serializable
@JsonClassDiscriminator("target")
sealed interface UpdateStateParams {
    @Serializable
    @SerialName("profile")
    data class Profile(
        val action: String = "set",
        val name: String? = null,
        val description: String? = null,
        val tags: List<String>? = null
    ) : UpdateStateParams

    @Serializable
    @SerialName("memory")
    data class Memory(
        val action: String,
        val fact: String,
        val tier: String = "log"
    ) : UpdateStateParams
}

fun parseUpdateState(args: JsonObject): UpdateStateParams {
    val target = args.string("target")
    return when (target) {
        "profile" -> {
            val action = args.string("action")
            if (action != "set") fail("action", "Invalid enum value. Expected 'set', received '$action'")
            val tags = args.stringListOrNull("tags")?.let { normalizeAgentTags(it) }
            UpdateStateParams.Profile(
                action = "set",
                name = args.stringOrAbsent("name"),
                description = args.stringOrAbsent("description"),
                tags = tags
            )
        }
        "memory" -> {
            val action = args.string("action") ?: fail("action", "Required")
            if (action != "write" && action != "forget") fail("action", "Invalid enum value. Expected 'write' | 'forget', received '$action'")
            val fact = args.string("fact") ?: fail("fact", "Required")
            val tier = if ("tier" in args) args.string("tier") ?: fail("tier", "Expected a string") else "log"
            if (tier !in setOf("profile", "log", "note")) fail("tier", "Invalid enum value. Expected 'profile' | 'log' | 'note', received '$tier'")
            UpdateStateParams.Memory(action = action, fact = fact, tier = tier)
        }
        null -> fail("target", "Required")
        else -> fail("target", "Invalid enum value. Expected 'profile' | 'memory', received '$target'")
    }
}

@Serializable
data class CreateAgentParams(val name: String, val description: String, @SerialName("first_message") val firstMessage: String? = null)

fun parseCreateAgent(args: JsonObject): CreateAgentParams = CreateAgentParams(
    name = args.string("name") ?: fail("name", "Required"),
    description = args.string("description") ?: fail("description", "Required"),
    firstMessage = args.stringOrAbsent("first_message")
)

@Serializable
data class UpdateAgentParams(
    @SerialName("agent_id") val agentId: String,
    val name: String? = null,
    val description: String? = null,
    val tags: List<String>? = null
)

fun parseUpdateAgent(args: JsonObject): UpdateAgentParams = UpdateAgentParams(
    agentId = args.string("agent_id") ?: fail("agent_id", "Required"),
    name = args.stringOrAbsent("name"),
    description = args.stringOrAbsent("description"),
    tags = args.stringListOrNull("tags")?.let { normalizeAgentTags(it) }
)

@Serializable
data class SendToAgentParams(
    @SerialName("agent_id") val agentId: String,
    val message: String,
    val priority: Boolean? = null
)

fun parseSendToAgent(args: JsonObject): SendToAgentParams = SendToAgentParams(
    agentId = args.string("agent_id") ?: fail("agent_id", "Required"),
    message = args.string("message") ?: fail("message", "Required"),
    priority = args.boolOrAbsent("priority")
)

@Serializable
data class ReadAgentTranscriptParams(
    @SerialName("agent_id") val agentId: String,
    val limit: Int? = null
)

fun parseReadAgentTranscript(args: JsonObject): ReadAgentTranscriptParams {
    val limit = args.intOrAbsent("limit")
    if (limit != null && (limit <= 0 || limit > 200)) fail("limit", "Number must be greater than 0 and at most 200")
    return ReadAgentTranscriptParams(args.string("agent_id") ?: fail("agent_id", "Required"), limit)
}

@Serializable
data class CheckAgentParams(@SerialName("agent_id") val agentId: String)

fun parseCheckAgent(args: JsonObject): CheckAgentParams =
    CheckAgentParams(args.string("agent_id") ?: fail("agent_id", "Required"))

@Serializable
data class StopAgentParams(@SerialName("agent_id") val agentId: String)

fun parseStopAgent(args: JsonObject): StopAgentParams =
    StopAgentParams(args.string("agent_id") ?: fail("agent_id", "Required"))

@Serializable
data class CreateTaskParams(
    val title: String,
    val description: String = "",
    val acceptanceCriteria: List<String> = emptyList(),
    val assigneeIds: List<String> = emptyList()
)

fun parseCreateTask(args: JsonObject): CreateTaskParams {
    val title = args.string("title")?.trim() ?: fail("title", "Required")
    if (title.isEmpty()) fail("title", "String must contain at least 1 character(s)")
    return CreateTaskParams(
        title = title,
        description = args.stringOrAbsent("description") ?: "",
        acceptanceCriteria = args.stringListOrNull("acceptanceCriteria") ?: emptyList(),
        assigneeIds = args.stringListOrNull("assigneeIds") ?: emptyList()
    )
}

@Serializable
data class ClaimTaskParams(val taskId: String, val expectedRevision: Int)

fun parseClaimTask(args: JsonObject): ClaimTaskParams {
    val taskId = args.string("taskId")?.takeIf { it.isNotEmpty() } ?: fail("taskId", "Required")
    val revision = args.intOrAbsent("expectedRevision") ?: fail("expectedRevision", "Required")
    if (revision <= 0) fail("expectedRevision", "Number must be greater than 0")
    return ClaimTaskParams(taskId, revision)
}

@Serializable
data class ReadTaskParams(val taskId: String? = null)

fun parseReadTask(args: JsonObject): ReadTaskParams = ReadTaskParams(args.stringOrAbsent("taskId"))

@Serializable
data class PostToWorkParams(val message: String)

fun parsePostToWork(args: JsonObject): PostToWorkParams {
    val message = args.string("message")?.takeIf { it.isNotEmpty() } ?: fail("message", "Required")
    return PostToWorkParams(message)
}

@Serializable
data class HandoffDeliverable(
    val name: String,
    val uri: String,
    @SerialName("mime_type") val mimeType: String? = null
)

@Serializable
data class HandoffTaskParams(
    val summary: String,
    val status: String,
    @SerialName("blocker_reason") val blockerReason: String? = null,
    val deliverables: List<HandoffDeliverable> = emptyList()
)

fun parseHandoffTask(args: JsonObject): HandoffTaskParams {
    val summary = args.string("summary")?.takeIf { it.isNotEmpty() } ?: fail("summary", "Required")
    val status = args.string("status") ?: fail("status", "Required")
    if (status !in setOf("review", "blocked", "done")) fail("status", "Invalid enum value. Expected 'review' | 'blocked' | 'done', received '$status'")
    val blocker = args.stringOrAbsent("blocker_reason")
    if (blocker != null && blocker.isEmpty()) fail("blocker_reason", "String must contain at least 1 character(s)")
    return HandoffTaskParams(summary, status, blocker, parseDeliverables(args))
}

@Serializable
data class WorkCardAction(
    val status: String,
    @SerialName("blocker_reason") val blockerReason: String? = null,
    val expectedRevision: Int? = null,
    val deliverables: List<HandoffDeliverable> = emptyList()
)

@Serializable
data class WorkSendMessageParams(
    val type: String,
    val content: String,
    val cardAction: WorkCardAction? = null
)

fun parseWorkSendMessage(args: JsonObject): WorkSendMessageParams {
    rejectUnknown(args, setOf("type", "content", "cardAction"))
    if (args.string("type") != "text") fail("type", "Invalid literal value, expected \"text\"")
    val content = args.string("content")?.trim() ?: fail("content", "Required")
    if (content.isEmpty()) fail("content", "String must contain at least 1 character(s)")
    val card = args["cardAction"]?.let { element ->
        val obj = element as? JsonObject ?: fail("cardAction", "Expected an object")
        rejectUnknown(obj, setOf("status", "blocker_reason", "expectedRevision", "deliverables"), "cardAction")
        val status = obj.string("status") ?: fail("cardAction.status", "Required")
        if (status !in setOf("review", "blocked")) fail("cardAction.status", "Invalid enum value. Expected 'review' | 'blocked', received '$status'")
        val blocker = obj.stringOrAbsent("blocker_reason")?.trim()
        if (blocker != null && blocker.isEmpty()) fail("cardAction.blocker_reason", "String must contain at least 1 character(s)")
        val revision = obj.intOrAbsent("expectedRevision")
        if (revision != null && revision <= 0) fail("cardAction.expectedRevision", "Number must be greater than 0")
        WorkCardAction(status, blocker, revision, parseDeliverables(obj, "cardAction.deliverables"))
    }
    return WorkSendMessageParams("text", content, card)
}

@Serializable
data class ReadWorkTimelineParams(
    val beforeSeq: Int? = null,
    val afterSeq: Int? = null,
    val limit: Int = 30
)

fun parseReadWorkTimeline(args: JsonObject): ReadWorkTimelineParams {
    val before = args.intOrAbsent("beforeSeq")
    if (before != null && before <= 0) fail("beforeSeq", "Number must be greater than 0")
    val after = args.intOrAbsent("afterSeq")
    if (after != null && after < 0) fail("afterSeq", "Number must be greater than or equal to 0")
    val limit = if ("limit" in args) args.intOrAbsent("limit") ?: fail("limit", "Expected an integer") else 30
    if (limit <= 0 || limit > 100) fail("limit", "Number must be greater than 0 and at most 100")
    return ReadWorkTimelineParams(before, after, limit)
}

@Serializable
data class RunWorkCliParams(
    @SerialName("capability_id") val capabilityId: String,
    val args: List<String> = emptyList()
)

fun parseRunWorkCli(args: JsonObject): RunWorkCliParams {
    val id = args.string("capability_id")?.takeIf { it.isNotEmpty() } ?: fail("capability_id", "Required")
    return RunWorkCliParams(id, args.stringListOrNull("args") ?: emptyList())
}

@Serializable
data class DelegateWorkParams(
    @SerialName("agent_id") val agentId: String,
    val instruction: String,
    @SerialName("task_id") val taskId: String? = null
)

fun parseDelegateWork(args: JsonObject): DelegateWorkParams {
    val agentId = args.string("agent_id")?.takeIf { it.isNotEmpty() } ?: fail("agent_id", "Required")
    val instruction = args.string("instruction")?.takeIf { it.isNotEmpty() } ?: fail("instruction", "Required")
    val taskId = args.stringOrAbsent("task_id")
    if (taskId != null && taskId.isEmpty()) fail("task_id", "String must contain at least 1 character(s)")
    return DelegateWorkParams(agentId, instruction, taskId)
}

private fun parseDeliverables(args: JsonObject, path: String = "deliverables"): List<HandoffDeliverable> {
    val key = path.substringAfterLast('.')
    if (key !in args || args[key] is JsonNull) return emptyList()
    val raw = args[key] as? JsonArray ?: fail(path, "Expected an array")
    return raw.mapIndexed { index, element ->
        val obj = element as? JsonObject ?: fail("$path.$index", "Expected an object")
        val name = obj.string("name")?.takeIf { it.isNotEmpty() } ?: fail("$path.$index.name", "Required")
        val uri = obj.string("uri")?.takeIf { it.isNotEmpty() } ?: fail("$path.$index.uri", "Required")
        HandoffDeliverable(name, uri, obj.stringOrAbsent("mime_type"))
    }
}

private fun rejectUnknown(args: JsonObject, allowed: Set<String>, prefix: String = "") {
    val unknown = args.keys.filter { it !in allowed }
    if (unknown.isNotEmpty()) {
        val path = listOfNotNull(prefix.takeIf { it.isNotEmpty() }, unknown.first())
        fail(path.joinToString("."), "Unrecognized key")
    }
}

private fun JsonObject.string(key: String): String? {
    val raw = this[key] ?: return null
    val primitive = raw as? JsonPrimitive ?: fail(key, "Expected a string")
    if (primitive is JsonNull || !primitive.isString) fail(key, "Expected a string")
    return primitive.content
}

private fun JsonObject.stringOrAbsent(key: String): String? {
    if (key !in this || this[key] is JsonNull) return null
    return string(key)
}

private fun JsonObject.stringListOrNull(key: String): List<String>? {
    if (key !in this || this[key] is JsonNull) return null
    val raw = this[key] as? JsonArray ?: fail(key, "Expected an array")
    return raw.mapIndexed { index, element ->
        val primitive = element as? JsonPrimitive ?: fail("$key.$index", "Expected a string")
        if (!primitive.isString) fail("$key.$index", "Expected a string")
        primitive.content
    }
}

private fun JsonObject.boolOrAbsent(key: String): Boolean? {
    if (key !in this || this[key] is JsonNull) return null
    val primitive = this[key] as? JsonPrimitive ?: fail(key, "Expected a boolean")
    return primitive.booleanOrNull ?: fail(key, "Expected a boolean")
}

private fun JsonObject.intOrAbsent(key: String): Int? {
    if (key !in this || this[key] is JsonNull) return null
    val primitive = this[key] as? JsonPrimitive ?: fail(key, "Expected an integer")
    if (primitive.isString) fail(key, "Expected an integer")
    val asLong = primitive.longOrNull ?: primitive.content.toLongOrNull() ?: fail(key, "Expected an integer")
    if (asLong !in Int.MIN_VALUE..Int.MAX_VALUE) fail(key, "Expected an integer")
    if (primitive.intOrNull == null && primitive.content.contains('.')) fail(key, "Expected an integer")
    return asLong.toInt()
}

private fun fail(path: String, message: String): Nothing =
    throw ProtocolParseException(listOf(ProtocolIssue(path.split('.'), message)))

private val agentIdSchema = jsonObject(
    "type" to "string",
    "description" to "The agent's id, as listed in your teammate directory."
)

val DELEGATED_TOOL_DEFINITIONS: List<ToolDefinition> = listOf(
    ToolDefinition(
        name = DelegatedToolNames.createTask,
        description = "Create a ready card in this NunuBar. You become its permanent owner. Include acceptance criteria and optional workers; DelegateWork starts their independent card sessions.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("title"),
            "properties" to jsonObject(
                "title" to jsonObject("type" to "string"),
                "description" to jsonObject("type" to "string"),
                "acceptanceCriteria" to jsonObject("type" to "array", "items" to jsonObject("type" to "string")),
                "assigneeIds" to jsonObject("type" to "array", "items" to jsonObject("type" to "string"))
            )
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.claimTask,
        description = "Atomically join or start a ready card as a worker, without changing its creator-owner. Blocked cards require human confirmation. ReadTask supplies expectedRevision.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("taskId", "expectedRevision"),
            "properties" to jsonObject(
                "taskId" to jsonObject("type" to "string"),
                "expectedRevision" to jsonObject("type" to "integer")
            )
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.readTask,
        description = "Read a task's current state and revision, or list this NunuBar's tasks when taskId is omitted.",
        inputSchema = jsonObject(
            "type" to "object",
            "properties" to jsonObject("taskId" to jsonObject("type" to "string"))
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.sendMessage,
        description = "Say something to the user in their chat with you. This is your only voice: the user only ever sees the content of SendMessage calls, and plain text you write is an invisible scratchpad — so a reply counts only once it is inside SendMessage, including short casual ones like \"Got it\". Ending a turn where someone is waiting on you without SendMessage means they see silence. Post updates as you work, not just at the end: a real result, decision, or blocker is worth a message; routine mechanics and retries are not. Results count as delivered only inside SendMessage — an opening acknowledgement never discharges a result you owe (ack != delivery), so the last thing you do on a turn that produced one is SendMessage it. Use {\"type\":\"text\",\"content\":\"...\"} for normal messages; when a reply has two or three beats, send them as a short run of separate SendMessage calls, like quick texts, rather than one welded paragraph. Attach images to the text they belong with via images (they render inside the same bubble); use type:attachment only when the file IS the whole message. Use {\"type\":\"widget\",\"widget\":{...}} to ask a question with selectable options — sparingly: by default decide and proceed, reserving widgets for consequential or destructive go/no-go calls, true ambiguity you cannot resolve yourself, or something only the user knows. Every option must be a real, verified choice; a user's selection arrives as their next message. Sending a widget ends your turn — make it your last action.",
        inputSchema = sendMessageSchema(),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.updateState,
        description = "Change your own persistent state. target=profile rewrites your own name, tags or description; target=memory records or forgets a durable fact. Fields you do not pass are left alone.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("target", "action"),
            "properties" to jsonObject(
                "target" to jsonObject("type" to "string", "enum" to listOf("profile", "memory")),
                "action" to jsonObject("type" to "string", "enum" to listOf("set", "write", "forget")),
                "name" to jsonObject("type" to "string", "description" to "For target=profile."),
                "description" to jsonObject("type" to "string", "description" to "For target=profile."),
                "tags" to jsonObject("type" to "array", "items" to jsonObject("type" to "string"), "description" to "For target=profile: replaces all tags; pass [] to clear."),
                "fact" to jsonObject("type" to "string", "description" to "For target=memory: one self-contained fact."),
                "tier" to jsonObject(
                    "type" to "string",
                    "enum" to listOf("profile", "log", "note"),
                    "description" to "For target=memory: profile for standing facts, log for dated ones."
                )
            )
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.createAgent,
        description = "Create a new teammate agent with its own chat, persona, and memory. It appears in the user's sidebar immediately. You have no tool to delete an agent, so only create one when it is genuinely useful and long-lived — for a one-off task, just do the task yourself.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("name", "description"),
            "properties" to jsonObject(
                "name" to jsonObject("type" to "string", "description" to "Short, human, and distinct from existing teammates."),
                "description" to jsonObject("type" to "string", "description" to "What this teammate is for."),
                "first_message" to jsonObject("type" to "string", "description" to "Optional first instruction to wake it with.")
            )
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.updateAgent,
        description = "Rename another agent or rewrite its description. Fields you do not pass are left alone.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("agent_id"),
            "properties" to jsonObject(
                "agent_id" to agentIdSchema,
                "name" to jsonObject("type" to "string"),
                "description" to jsonObject("type" to "string"),
                "tags" to jsonObject("type" to "array", "items" to jsonObject("type" to "string"))
            )
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.sendToAgent,
        description = "Send a message to another agent. Delivery is asynchronous and fire-and-forget, like texting: it returns immediately, and a later reply from that teammate wakes you here — never wait or poll for one in this turn. Write the message self-contained (they cannot see your chat) and lead with the point. Waking a teammate is a real side effect: message an agent only when it serves the user's goal, never relay the user's private or unfiltered words verbatim (paraphrase the actionable point instead), and messaging several agents about the same effort is a fan-out you only make when the user explicitly asked for it. Use priority to interrupt what the recipient is currently doing — for STOP / supersede / time-critical instructions, not for ordinary replies.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("agent_id", "message"),
            "properties" to jsonObject(
                "agent_id" to agentIdSchema,
                "message" to jsonObject("type" to "string", "description" to "Self-contained: the other agent cannot see your chat."),
                "priority" to jsonObject("type" to "boolean", "description" to "Interrupt its current work instead of queueing. For STOP / supersede / time-critical instructions only.")
            )
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.readAgentTranscript,
        description = "Read the tail of another agent's chat, to see what it has been up to or what it answered. Read-only.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("agent_id"),
            "properties" to jsonObject(
                "agent_id" to agentIdSchema,
                "limit" to jsonObject("type" to "number", "description" to "How many entries, newest last.")
            )
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.checkAgent,
        description = "Check what another agent is doing right now, without messaging or waking it. Returns whether it is running or idle, which run it is in (your user's private chat or a Work), its recent tool activity, and the path to its transcript you can read for the full play-by-play. Read-only. Use it when a teammate you are working with seems stuck, slow, or you need its current state before deciding next steps; to actually reach it, use SendToAgent.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("agent_id"),
            "properties" to jsonObject("agent_id" to agentIdSchema),
            "description" to "Pass the agent's id from your teammate directory — not a name."
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.stopAgent,
        description = "Stop what another agent is currently doing. Anything queued for it is dropped too.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("agent_id"),
            "properties" to jsonObject("agent_id" to agentIdSchema)
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.postToWork,
        description = "Post a progress update to the current Work shared room.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("message"),
            "properties" to jsonObject("message" to jsonObject("type" to "string"))
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.handoffTask,
        description = "Hand the current Work task back for review, report it blocked, or—when you are the coordinator—mark a reviewed task done. This also posts the summary in the shared room.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("summary", "status"),
            "properties" to jsonObject(
                "summary" to jsonObject("type" to "string"),
                "status" to jsonObject("type" to "string", "enum" to listOf("review", "blocked", "done")),
                "blocker_reason" to jsonObject("type" to "string"),
                "deliverables" to jsonObject(
                    "type" to "array",
                    "items" to jsonObject(
                        "type" to "object",
                        "required" to listOf("name", "uri"),
                        "properties" to jsonObject(
                            "name" to jsonObject("type" to "string"),
                            "uri" to jsonObject("type" to "string"),
                            "mime_type" to jsonObject("type" to "string")
                        )
                    )
                )
            )
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.readWorkTimeline,
        description = "Read the latest entries from the current Work timeline.",
        inputSchema = jsonObject(
            "type" to "object",
            "properties" to jsonObject(
                "limit" to jsonObject("type" to "number"),
                "beforeSeq" to jsonObject("type" to "integer"),
                "afterSeq" to jsonObject("type" to "integer")
            )
        ),
        mutating = false
    ),
    ToolDefinition(
        name = DelegatedToolNames.runWorkCli,
        description = "Run a CLI capability explicitly installed in the current Work. No shell expansion is performed.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("capability_id"),
            "properties" to jsonObject(
                "capability_id" to jsonObject("type" to "string"),
                "args" to jsonObject("type" to "array", "items" to jsonObject("type" to "string"))
            )
        ),
        mutating = true
    ),
    ToolDefinition(
        name = DelegatedToolNames.delegateWork,
        description = "Dispatch a room member as a worker. Specify task_id (defaults to the current card); room-only discussion must use @ in SendMessage. Workers use independent card sessions: the creator stays owner and worker results return there. Blocked cards require human confirmation before further dispatch.",
        inputSchema = jsonObject(
            "type" to "object",
            "required" to listOf("agent_id", "instruction"),
            "properties" to jsonObject(
                "agent_id" to agentIdSchema,
                "instruction" to jsonObject("type" to "string"),
                "task_id" to jsonObject("type" to "string")
            )
        ),
        mutating = false
    )
)

private fun sendMessageSchema(): JsonObject = jsonObject(
    "type" to "object",
    "required" to listOf("type"),
    "properties" to jsonObject(
        "type" to jsonObject("type" to "string", "enum" to listOf("text", "attachment", "widget")),
        "content" to jsonObject("type" to "string", "description" to "Required when type=text: the message to show the user."),
        "images" to jsonObject(
            "type" to "array",
            "description" to "Optional, only with type=text: images that belong with this message; they render inside the same bubble below the text.",
            "items" to jsonObject(
                "type" to "object",
                "required" to listOf("path"),
                "properties" to jsonObject(
                    "path" to jsonObject("type" to "string", "description" to "Absolute local path to the image file."),
                    "alt" to jsonObject("type" to "string", "description" to "Short description shown on hover and as fullscreen caption.")
                )
            )
        ),
        "path" to jsonObject("type" to "string", "description" to "Required when type=attachment: absolute path to the file."),
        "caption" to jsonObject("type" to "string", "description" to "For type=attachment: one line about it."),
        "widget" to jsonObject(
            "type" to "object",
            "description" to "Required when type=widget: a question with selectable options. The chosen option's value is sent back to you as the user's reply.",
            "required" to listOf("prompt", "options"),
            "properties" to jsonObject(
                "prompt" to jsonObject("type" to "string", "description" to "The question, phrased as a natural conversational sentence — never a menu instruction."),
                "helpText" to jsonObject("type" to "string", "description" to "Optional short help shown under the question."),
                "options" to jsonObject(
                    "type" to "array",
                    "minItems" to 1,
                    "maxItems" to 6,
                    "items" to jsonObject(
                        "type" to "object",
                        "required" to listOf("label"),
                        "properties" to jsonObject(
                            "label" to jsonObject("type" to "string", "description" to "Short option label shown on the card."),
                            "value" to jsonObject("type" to "string", "description" to "Text sent back when picked; defaults to the label. Write it like a reply the user would actually send."),
                            "description" to jsonObject("type" to "string", "description" to "Optional one-line explanation under the label."),
                            "style" to jsonObject("type" to "string", "enum" to listOf("default", "primary", "danger"), "description" to "danger marks a destructive choice; primary marks the recommended one.")
                        )
                    )
                ),
                "allowCustom" to jsonObject("type" to "boolean", "description" to "Let the user type a free-text answer instead of picking an option.")
            )
        )
    )
)
