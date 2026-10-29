package com.nuum.kernel

import com.nuum.contracts.ChatMessage
import com.nuum.contracts.Clock
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.KernelEvent
import com.nuum.contracts.KernelPort
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.MessagePart
import com.nuum.contracts.MessageRole
import com.nuum.contracts.ModelImage
import com.nuum.contracts.ModelPort
import com.nuum.contracts.NormalizedChatRequest
import com.nuum.contracts.NormalizedChunk
import com.nuum.contracts.NuumException
import com.nuum.contracts.PermissionDecision
import com.nuum.contracts.ProviderId
import com.nuum.contracts.RunEndStatus
import com.nuum.contracts.Secrets
import com.nuum.contracts.SummarizeRunParams
import com.nuum.contracts.SummarizeRunResult
import com.nuum.contracts.ToolBackend
import com.nuum.contracts.ToolCall
import com.nuum.contracts.ToolDefinition
import com.nuum.contracts.ToolExecutor
import com.nuum.contracts.ToolPermission
import com.nuum.contracts.ToolResolution
import com.nuum.contracts.TurnContextResult
import com.nuum.contracts.TurnStartParams
import com.nuum.contracts.TurnToolDecision
import com.nuum.contracts.TurnToolResult
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.coroutineContext
import kotlin.math.floor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield

/**
 * In-process port of `packages/kernel/src/loop.ts` and `summarize.ts`.
 *
 * The kernel only knows [TurnStartParams.runId]. It never sees an agent id.
 * Tool IO goes through [ToolExecutor] — this class does not touch the filesystem.
 * [events] is hot and does not replay; collect it before [start].
 *
 * Local tool schemas come from [toolDefinitions], or from [ToolBackend.definitions]
 * when [tools] is a [ToolBackend]. Execution, permission state, and `release` stay
 * on [ToolExecutor].
 */
class Kernel(
    private val model: ModelPort,
    private val tools: ToolExecutor,
    private val scope: CoroutineScope,
    private val clock: Clock = Clock { System.currentTimeMillis() },
    private val newId: () -> String = { UUID.randomUUID().toString() },
    private val toolDefinitions: (() -> List<ToolDefinition>)? = null
) : KernelPort {
    private val runs = ConcurrentHashMap<String, ActiveTurn>()
    private val summaries = ConcurrentHashMap<String, Job>()
    private val eventsFlow = MutableSharedFlow<KernelEvent>(
        extraBufferCapacity = 1024,
        onBufferOverflow = BufferOverflow.SUSPEND
    )

    override val events: Flow<KernelEvent> = eventsFlow.asSharedFlow()

    override suspend fun start(params: TurnStartParams) {
        val turn = ActiveTurn()
        val previous = runs.putIfAbsent(params.runId, turn)
        if (previous != null) {
            throw NuumException(KernelErrorCode.TURN_BUSY, "Run ${params.runId} is already running")
        }
        turn.job = scope.launch { runTurn(params, turn) }
    }

    override suspend fun cancel(runId: String) {
        runs[runId]?.job?.cancel()
    }

    override suspend fun approveTool(decision: TurnToolDecision) {
        decide(decision.runId, decision.toolCallId, decision.resolution)
    }

    override suspend fun denyTool(decision: TurnToolDecision) {
        decide(decision.runId, decision.toolCallId, ToolResolution.DENY)
    }

    override suspend fun provideContext(result: TurnContextResult) {
        val waiter = requireRun(result.runId).contexts.remove(result.requestId) ?: return
        if (waiter.isActive) waiter.complete(result)
    }

    override suspend fun provideToolResult(result: TurnToolResult) {
        val waiter = requireRun(result.runId).delegations.remove(result.toolCallId) ?: return
        if (waiter.isActive) {
            waiter.complete(DelegatedResult(result.ok, result.output, result.endTurn))
        }
    }

    override suspend fun summarize(params: SummarizeRunParams): SummarizeRunResult {
        val apiKey = apiKeyFor(params.secrets, params.model.provider)
        val job = coroutineContext.job
        if (summaries.putIfAbsent(params.runId, job) != null) {
            throw NuumException(KernelErrorCode.INVALID, "Summary already running")
        }
        try {
            return runSummarize(params, apiKey)
        } finally {
            summaries.remove(params.runId, job)
        }
    }

    override suspend fun cancelSummary(runId: String) {
        summaries[runId]?.cancel()
    }

    private suspend fun runTurn(params: TurnStartParams, turn: ActiveTurn) {
        var bound = false
        try {
            val apiKey = apiKeyFor(params.secrets, params.model.provider)
            tools.bind(
                params.runId,
                params.roots,
                params.toolPermission,
                params.approvals,
                params.refused
            )
            bound = true
            drive(params, turn, apiKey)
        } catch (cancelled: CancellationException) {
            // 取消是正常收束，不是错误，所以不发 turn.error。
            withContext(NonCancellable) {
                publish(KernelEvent.Ended(params.runId, RunEndStatus.CANCELLED))
            }
        } catch (error: NuumException) {
            publish(KernelEvent.Error(params.runId, error.code, error.message))
            publish(KernelEvent.Ended(params.runId, RunEndStatus.ERROR))
        } catch (error: Exception) {
            publish(KernelEvent.Error(params.runId, KernelErrorCode.INTERNAL, error.message ?: error.toString()))
            publish(KernelEvent.Ended(params.runId, RunEndStatus.ERROR))
        } finally {
            if (bound) tools.release(params.runId)
            runs.remove(params.runId, turn)
        }
    }

    private suspend fun drive(params: TurnStartParams, turn: ActiveTurn, apiKey: String) {
        val catalog = definitions()
        val enabled = params.localToolNames.toSet()
        val visible = catalog.filter { it.name in enabled } + params.delegatedTools
        val delegated = params.delegatedTools.map { it.name }.toSet()
        val messages = params.messages.toMutableList()
        val voiceTools = params.voiceToolNames.toSet()
        val voice = params.voiceToolNames.firstOrNull() ?: "SendMessage"
        var toolCallsSinceVoice = 0
        var voiceSentThisTurn = false
        val reminded = mutableSetOf<ReminderKind>()

        for (round in 0 until MAX_ROUNDS) {
            coroutineContext.ensureActive()
            val window = params.contextWindow
            if (window != null) {
                val requestId = newId()
                val next = awaitHost(turn.contexts, requestId) {
                    publish(KernelEvent.Context(params.runId, requestId, estimateModelTokens(messages, visible)))
                }
                val failure = next.error
                if (failure != null) throw IllegalStateException(failure)
                val replacement = next.messages
                if (replacement != null) {
                    val local = messages.filter { message ->
                        message.id.startsWith(TOOL_IMAGES_PREFIX) || message.id.startsWith(REMINDER_PREFIX)
                    }
                    val kept = local.filter { item -> replacement.none { it.id == item.id } }
                    messages.clear()
                    messages.addAll(replacement)
                    messages.addAll(kept)
                }
                if (estimateModelTokens(messages, visible) > window * 0.9) {
                    throw IllegalStateException(CONTEXT_EXHAUSTED)
                }
                coroutineContext.ensureActive()
            }

            val messageId = newId()
            var text = ""
            var thinking = ""
            val toolCalls = mutableListOf<ToolCall>()
            val request = NormalizedChatRequest(
                model = params.model,
                messages = messages.toList(),
                tools = visible,
                apiKey = apiKey,
                maxOutputTokens = window?.let(::outputCap)
            )
            try {
                model.streamChat(request).collect { chunk ->
                    when (chunk) {
                        is NormalizedChunk.Thinking -> {
                            thinking += chunk.text
                            publish(KernelEvent.Delta(params.runId, messageId, chunk.text, MessagePart.THINKING))
                        }
                        is NormalizedChunk.Text -> {
                            text += chunk.text
                            publish(KernelEvent.Delta(params.runId, messageId, chunk.text, MessagePart.TEXT))
                        }
                        is NormalizedChunk.ToolCallChunk -> {
                            toolCalls += ToolCall(chunk.id, chunk.name, chunk.arguments)
                        }
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                coroutineContext.ensureActive()
                throw error
            }

            messages += ChatMessage(
                id = messageId,
                role = MessageRole.ASSISTANT,
                content = text,
                seq = messages.size,
                createdAt = clock.nowMillis(),
                thinking = thinking.ifEmpty { null },
                toolCalls = toolCalls.takeIf { it.isNotEmpty() }
            )
            if (toolCalls.isEmpty()) {
                publish(KernelEvent.Ended(params.runId, RunEndStatus.IDLE))
                return
            }

            val toolImages = mutableListOf<ModelImage>()
            for (call in toolCalls) {
                val result = resolveToolCall(params, turn, call, delegated, catalog)
                messages += ChatMessage(
                    id = newId(),
                    role = MessageRole.TOOL,
                    content = result.output,
                    seq = messages.size,
                    createdAt = clock.nowMillis(),
                    toolCallId = call.id,
                    name = call.name
                )
                toolImages += result.images
                publish(
                    KernelEvent.ToolCompleted(
                        runId = params.runId,
                        toolCallId = call.id,
                        toolName = call.name,
                        ok = result.ok,
                        output = result.output
                    )
                )
                if (result.ok && result.endTurn) {
                    publish(KernelEvent.Ended(params.runId, RunEndStatus.IDLE))
                    return
                }
                if (call.name in voiceTools) {
                    toolCallsSinceVoice = 0
                    voiceSentThisTurn = true
                    reminded.clear()
                } else {
                    toolCallsSinceVoice += 1
                }
            }
            if (toolImages.isNotEmpty()) {
                messages += ChatMessage(
                    id = TOOL_IMAGES_PREFIX + newId(),
                    role = MessageRole.USER,
                    content = TOOL_IMAGES_TEXT,
                    seq = messages.size,
                    createdAt = clock.nowMillis(),
                    images = toolImages.toList()
                )
            }
            val reminder = reminderToInject(voiceSentThisTurn, toolCallsSinceVoice, reminded)
            if (reminder != null) {
                reminded += reminder
                messages += ChatMessage(
                    id = "$REMINDER_PREFIX${reminder.wire}-${newId()}",
                    role = MessageRole.USER,
                    content = reminderText(reminder, voice),
                    seq = messages.size,
                    createdAt = clock.nowMillis()
                )
            }
        }

        // 轮次用尽时不能装作正常收束：把原因作为最后一段文本告诉用户。
        publish(
            KernelEvent.Delta(
                runId = params.runId,
                messageId = newId(),
                delta = ROUND_LIMIT_NOTICE,
                part = MessagePart.TEXT
            )
        )
        publish(KernelEvent.Ended(params.runId, RunEndStatus.IDLE))
    }

    private suspend fun resolveToolCall(
        params: TurnStartParams,
        turn: ActiveTurn,
        call: ToolCall,
        delegated: Set<String>,
        catalog: List<ToolDefinition>
    ): ResolvedTool {
        if (call.name in delegated) {
            val provided = awaitHost(turn.delegations, call.id) {
                publish(
                    KernelEvent.ToolDelegate(
                        runId = params.runId,
                        toolCallId = call.id,
                        toolName = call.name,
                        arguments = call.arguments
                    )
                )
            }
            return ResolvedTool(provided.ok, provided.output, endTurn = provided.endTurn)
        }
        val definition = catalog.firstOrNull { it.name == call.name }
            ?: throw NuumException(KernelErrorCode.TOOL, "Unknown tool: ${call.name}")
        val declared = definition.action
            ?: throw NuumException(
                KernelErrorCode.TOOL,
                "Local tool ${call.name} does not declare a permission action"
            )
        val (action, target) = permissionRequest(call.name, declared, call.arguments, params.roots.terminals)
        val verdict = tools.authorize(params.runId, action, target)
        if (verdict.decision == PermissionDecision.DENY) {
            val reason = verdict.reason ?: "Permission denied for ${action.wire} ${verdict.target}"
            return ResolvedTool(ok = false, output = reason)
        }
        if (verdict.decision == PermissionDecision.ASK) {
            val resolution = awaitHost(turn.decisions, call.id) {
                publish(
                    KernelEvent.ToolPending(
                        runId = params.runId,
                        toolCallId = call.id,
                        toolName = call.name,
                        arguments = call.arguments,
                        mutating = action != LocalToolAction.READ_FILE && definition.mutating,
                        action = action,
                        target = verdict.target
                    )
                )
            }
            if (resolution == ToolResolution.DENY || resolution == ToolResolution.NEVER) {
                tools.refuse(params.runId, action, verdict.target)
                if (resolution == ToolResolution.NEVER) {
                    tools.setPermission(params.runId, ToolPermission.NEVER)
                }
                return ResolvedTool(ok = false, output = "User denied this tool call.")
            }
            // always 与 once 都只放行这一次。把 run 权限改成 always 不是 loop 的事。
            tools.grantOnce(params.runId, action, verdict.target)
        }
        publish(
            KernelEvent.ToolStarted(
                runId = params.runId,
                toolCallId = call.id,
                toolName = call.name,
                arguments = call.arguments
            )
        )
        return try {
            val executed = tools.execute(params.runId, call)
            ResolvedTool(executed.ok, executed.output, executed.images, executed.endTurn)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            coroutineContext.ensureActive()
            ResolvedTool(ok = false, output = error.message ?: error.toString())
        }
    }

    /**
     * 一次无工具的单发模型调用。不发事件、不落盘、不进 runs。
     * thinking 不进结果：调用方要的是摘要本身。
     */
    private suspend fun runSummarize(params: SummarizeRunParams, apiKey: String): SummarizeRunResult {
        val messages = buildList {
            add(
                ChatMessage(
                    id = "system",
                    role = MessageRole.SYSTEM,
                    content = params.systemPrompt,
                    seq = 0,
                    createdAt = 0
                )
            )
            addAll(params.messages)
        }
        val request = NormalizedChatRequest(
            model = params.model,
            messages = messages,
            tools = emptyList(),
            apiKey = apiKey,
            maxOutputTokens = params.maxOutputTokens ?: 2048
        )
        val text = StringBuilder()
        withTimeout(params.timeoutMs ?: 60_000L) {
            model.streamChat(request).collect { chunk ->
                if (chunk is NormalizedChunk.Text) text.append(chunk.text)
            }
        }
        return SummarizeRunResult(text.toString().trim())
    }

    private fun definitions(): List<ToolDefinition> {
        toolDefinitions?.let { return it() }
        return (tools as? ToolBackend)?.definitions().orEmpty()
    }

    private fun decide(runId: String, toolCallId: String, resolution: ToolResolution) {
        val waiter = requireRun(runId).decisions.remove(toolCallId) ?: return
        if (waiter.isActive) waiter.complete(resolution)
    }

    private fun requireRun(runId: String): ActiveTurn =
        runs[runId] ?: throw NuumException(KernelErrorCode.INVALID, "No running turn for $runId")

    /**
     * 进程内 Host 可以在收集事件的同一轮里回结果。先登记等待者再发事件，
     * 避免同步收集把 provide / decide 丢在登记之前。
     */
    private suspend fun <T> awaitHost(
        waiters: ConcurrentHashMap<String, CompletableDeferred<T>>,
        id: String,
        announce: suspend () -> Unit
    ): T {
        val deferred = CompletableDeferred<T>()
        waiters[id] = deferred
        try {
            announce()
            return deferred.await()
        } finally {
            waiters.remove(id, deferred)
        }
    }

    private suspend fun publish(event: KernelEvent) {
        while (!eventsFlow.tryEmit(event)) {
            yield()
        }
    }

    private class ActiveTurn {
        @Volatile var job: Job? = null
        val decisions = ConcurrentHashMap<String, CompletableDeferred<ToolResolution>>()
        val delegations = ConcurrentHashMap<String, CompletableDeferred<DelegatedResult>>()
        val contexts = ConcurrentHashMap<String, CompletableDeferred<TurnContextResult>>()
    }

    private data class DelegatedResult(val ok: Boolean, val output: String, val endTurn: Boolean)

    private data class ResolvedTool(
        val ok: Boolean,
        val output: String,
        val images: List<ModelImage> = emptyList(),
        val endTurn: Boolean = false
    )
}

private const val MAX_ROUNDS = 16
private const val ROUND_LIMIT_NOTICE = "Stopped after $MAX_ROUNDS tool rounds without a final answer."
private const val CONTEXT_EXHAUSTED = "Context capacity exhausted; execution paused without replaying tools."
private const val TOOL_IMAGES_PREFIX = "tool-images-"
private const val TOOL_IMAGES_TEXT = "Images returned by the preceding local read tool calls."
private const val REMINDER_PREFIX = "reminder-"

/** ack（从未发声）在静默调用数超过 1 时；silence 超过 6；result 在发过声后又埋头（超过 0）。 */
private const val ACK_TOOL_THRESHOLD = 1
private const val SILENCE_TOOL_THRESHOLD = 6
private const val RESULT_TOOL_THRESHOLD = 0

private enum class ReminderKind(val wire: String) {
    ACK("ack"),
    SILENCE("silence"),
    RESULT("result")
}

/** ack（从未发声）→ result（发过声又埋头）→ silence（长静默），每轮至多一条。 */
private fun reminderToInject(
    voiceSentThisTurn: Boolean,
    toolCallsSinceVoice: Int,
    reminded: Set<ReminderKind>
): ReminderKind? {
    if (!voiceSentThisTurn && toolCallsSinceVoice > ACK_TOOL_THRESHOLD && ReminderKind.ACK !in reminded) {
        return ReminderKind.ACK
    }
    if (voiceSentThisTurn && toolCallsSinceVoice > RESULT_TOOL_THRESHOLD && ReminderKind.RESULT !in reminded) {
        return ReminderKind.RESULT
    }
    if (toolCallsSinceVoice > SILENCE_TOOL_THRESHOLD && ReminderKind.SILENCE !in reminded) {
        return ReminderKind.SILENCE
    }
    return null
}

private fun reminderText(kind: ReminderKind, voice: String): String = when (kind) {
    ReminderKind.ACK ->
        "<system_reminder>You opened this turn by calling tools without first acknowledging the user, " +
            "so they are watching silence and may think the app froze. Call $voice right now — a real tool " +
            "call, not text you write — with a one-line acknowledgement before any further tool call, then continue the work.</system_reminder>"
    ReminderKind.SILENCE ->
        "<system_reminder>You have made several tool calls without a message, so the user is currently " +
            "watching silence. Call $voice now with a brief, specific update on what you are doing or what " +
            "you just found, then continue.</system_reminder>"
    ReminderKind.RESULT ->
        "<system_reminder>The user cannot see tool output or your thinking — only $voice reaches them. " +
            "If you have produced a result or finished what they asked, send it with $voice before continuing " +
            "or ending the turn; if you are still mid-task, keep working and send it once you have it.</system_reminder>"
}

private fun outputCap(contextWindow: Int): Int =
    maxOf(1, minOf(4096, floor(contextWindow * 0.1).toInt()))

private fun apiKeyFor(secrets: Secrets, provider: ProviderId): String {
    val key = when (provider) {
        ProviderId.OPENAI -> secrets.openaiApiKey
        ProviderId.ANTHROPIC -> secrets.anthropicApiKey
        ProviderId.DEEPSEEK -> secrets.deepseekApiKey
    }
    if (key.isNullOrEmpty()) {
        throw NuumException(KernelErrorCode.INVALID, "API key missing for ${provider.wire}")
    }
    return key
}

/**
 * `shell` + `shell_id` 改判为读本 agent 的 terminal 文件。其余按参数里的路径或命令。
 * 真正的允许 / 询问 / 拒绝在 [ToolExecutor.authorize]。
 */
private fun permissionRequest(
    toolName: String,
    action: LocalToolAction,
    input: Map<String, Any?>,
    terminalsRoot: String
): Pair<LocalToolAction, String> {
    val shellId = input["shell_id"]
    if (toolName == "shell" && shellId is String) {
        return LocalToolAction.READ_FILE to joinPath(terminalsRoot, "$shellId.txt")
    }
    if (action == LocalToolAction.RUN_COMMAND) {
        val command = input["command"]
        return action to if (command is String) command else ""
    }
    for (key in listOf("path", "target_directory", "working_directory")) {
        val value = input[key]
        if (value is String && value.isNotEmpty()) return action to value
    }
    return action to "."
}

private fun joinPath(root: String, child: String): String {
    if (root.isEmpty() || root == ".") return child
    return root.trimEnd('/') + "/" + child
}
