package com.nuum.agent

import com.nuum.contracts.AgentStore
import com.nuum.contracts.Clock
import com.nuum.contracts.KernelEvent
import com.nuum.contracts.KernelPort
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.NuumPaths
import com.nuum.contracts.PermissionVerdict
import com.nuum.contracts.PermissionDecision
import com.nuum.contracts.RunEndStatus
import com.nuum.contracts.SecretStore
import com.nuum.contracts.Secrets
import com.nuum.contracts.SummarizeRunParams
import com.nuum.contracts.SummarizeRunResult
import com.nuum.contracts.ToolBackend
import com.nuum.contracts.ToolCall
import com.nuum.contracts.ToolDefinition
import com.nuum.contracts.ToolExecutionResult
import com.nuum.contracts.ToolPermission
import com.nuum.contracts.ToolRoots
import com.nuum.contracts.TurnContextResult
import com.nuum.contracts.TurnStartParams
import com.nuum.contracts.TurnSupervisor
import com.nuum.contracts.TurnToolDecision
import com.nuum.contracts.TurnToolResult
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch

class ManualClock(var millis: Long = 1_700_000_000_000L) : Clock {
    override fun nowMillis(): Long = millis
}

class MemorySecrets(var current: Secrets = Secrets()) : SecretStore {
    override suspend fun read(): Secrets = current
    override suspend fun write(secrets: Secrets) {
        current = secrets
    }
}

class MemoryAgentStore : AgentStore {
    private val files = linkedMapOf<String, ByteArray>()
    private val dirs = mutableSetOf("")

    private fun normalize(path: String) = path.trim().trim('/').replace('\\', '/')

    private fun parents(path: String) {
        var current = ""
        for (part in path.split('/').dropLast(1)) {
            if (part.isEmpty()) continue
            current = if (current.isEmpty()) part else "$current/$part"
            dirs += current
        }
    }

    override suspend fun readText(relativePath: String): String? = files[normalize(relativePath)]?.toString(Charsets.UTF_8)

    override suspend fun writeTextAtomic(relativePath: String, text: String) {
        val path = normalize(relativePath)
        parents(path)
        files[path] = text.toByteArray(Charsets.UTF_8)
    }

    override suspend fun appendLine(relativePath: String, line: String) {
        val path = normalize(relativePath)
        parents(path)
        val existing = files[path]?.toString(Charsets.UTF_8).orEmpty()
        val body = if (existing.isEmpty() || existing.endsWith("\n")) existing else existing.substringBeforeLast('\n') + "\n"
        files[path] = (body + line.trimEnd('\n') + "\n").toByteArray(Charsets.UTF_8)
    }

    override suspend fun readBytes(relativePath: String): ByteArray? = files[normalize(relativePath)]

    override suspend fun writeBytesAtomic(relativePath: String, bytes: ByteArray) {
        val path = normalize(relativePath)
        parents(path)
        files[path] = bytes
    }

    override suspend fun readTail(relativePath: String, maxBytes: Int): String {
        val text = readText(relativePath).orEmpty()
        val bytes = text.toByteArray(Charsets.UTF_8)
        if (bytes.size <= maxBytes) return text
        return bytes.copyOfRange(bytes.size - maxBytes, bytes.size).toString(Charsets.UTF_8)
    }

    override suspend fun list(relativePath: String): List<String> {
        val prefix = normalize(relativePath)
        if (prefix.isNotEmpty() && prefix !in dirs && files.keys.none { it == prefix || it.startsWith("$prefix/") }) {
            return emptyList()
        }
        val base = if (prefix.isEmpty()) "" else "$prefix/"
        val children = linkedSetOf<String>()
        for (dir in dirs) {
            if (dir.startsWith(base) && dir != prefix) children += dir.removePrefix(base).substringBefore('/')
        }
        for (file in files.keys) {
            if (file.startsWith(base)) {
                val rest = file.removePrefix(base)
                children += rest.substringBefore('/')
            }
        }
        return children.filter { it.isNotEmpty() }.sorted()
    }

    override suspend fun delete(relativePath: String) {
        val path = normalize(relativePath)
        files.keys.filter { it == path || it.startsWith("$path/") }.toList().forEach { files.remove(it) }
        dirs.removeAll { it == path || it.startsWith("$path/") }
    }

    override suspend fun exists(relativePath: String): Boolean {
        val path = normalize(relativePath)
        return path in files || path in dirs || files.keys.any { it.startsWith("$path/") }
    }
}

class FakeKernel : KernelPort {
    val summarized = mutableListOf<SummarizeRunParams>()
    val started = mutableListOf<TurnStartParams>()
    val results = mutableListOf<TurnToolResult>()
    var hold: CompletableDeferred<Unit>? = null
    private val _events = MutableSharedFlow<KernelEvent>(replay = 8, extraBufferCapacity = 32)
    override val events: Flow<KernelEvent> = _events.asSharedFlow()

    override suspend fun start(params: TurnStartParams) {
        started += params
        hold?.await()
    }

    override suspend fun cancel(runId: String) = Unit
    override suspend fun approveTool(decision: TurnToolDecision) = Unit
    override suspend fun denyTool(decision: TurnToolDecision) = Unit
    override suspend fun provideContext(result: TurnContextResult) = Unit
    override suspend fun provideToolResult(result: TurnToolResult) {
        results += result
    }

    override suspend fun summarize(params: SummarizeRunParams): SummarizeRunResult {
        summarized += params
        return SummarizeRunResult("compacted")
    }

    override suspend fun cancelSummary(runId: String) = Unit

    fun emit(event: KernelEvent) {
        _events.tryEmit(event)
    }
}

class EmptyTools : ToolBackend {
    override fun definitions(): List<ToolDefinition> = listOf(
        ToolDefinition("read", "read", emptyMap(), false, LocalToolAction.READ_FILE)
    )

    override fun bind(runId: String, roots: ToolRoots, permission: ToolPermission, approvals: List<com.nuum.contracts.ToolApproval>, refused: List<com.nuum.contracts.ToolApproval>) = Unit
    override suspend fun authorize(runId: String, action: LocalToolAction, target: String) =
        PermissionVerdict(PermissionDecision.ALLOW, target)
    override fun grantOnce(runId: String, action: LocalToolAction, target: String) = Unit
    override fun refuse(runId: String, action: LocalToolAction, target: String) = Unit
    override fun setPermission(runId: String, permission: ToolPermission) = Unit
    override suspend fun execute(runId: String, call: ToolCall) = ToolExecutionResult(true, "")
    override fun release(runId: String) = Unit
}

class ScopeSupervisor : TurnSupervisor {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
    override fun launch(block: suspend () -> Unit) = scope.launch { block() }
}

fun openRuntime(
    scope: CoroutineScope,
    store: AgentStore = MemoryAgentStore(),
    kernel: KernelPort = FakeKernel(),
    secrets: SecretStore = MemorySecrets(Secrets(deepseekApiKey = "sk-test")),
    clock: Clock = ManualClock(),
    contextWindowTokens: Int = DEFAULT_CONTEXT_WINDOW,
    osLabel: String = "Android 16 (API 36)"
) = HostRuntime(
    store = store,
    kernel = kernel,
    secretStore = secrets,
    tools = EmptyTools(),
    clock = clock,
    supervisor = ScopeSupervisor(),
    nuumRoot = "",
    osLabel = osLabel,
    contextWindowTokens = contextWindowTokens
)

fun ended(runId: String) = KernelEvent.Ended(runId, RunEndStatus.IDLE)

fun transcriptPath(agentId: String) = NuumPaths.transcriptPath(agentId)
