package com.nuum.feature.settings

import com.nuum.contracts.Clock
import com.nuum.contracts.HostEvent
import com.nuum.contracts.Language
import com.nuum.contracts.ModelRef
import com.nuum.contracts.NuumException
import com.nuum.contracts.ProactiveAgentSnapshot
import com.nuum.contracts.ProactiveConfigureParams
import com.nuum.contracts.ProactivePolicy
import com.nuum.contracts.ProactivePort
import com.nuum.contracts.ProactiveSnapshot
import com.nuum.contracts.ProviderId
import com.nuum.contracts.PublicSettings
import com.nuum.contracts.SecretStore
import com.nuum.contracts.SecretWriter
import com.nuum.contracts.Secrets
import com.nuum.contracts.SettingsPatch
import com.nuum.contracts.SettingsPort
import com.nuum.contracts.ThemePreference
import com.nuum.contracts.ToolPermission
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.suspendCancellableCoroutine

internal fun sampleSettings(
    permission: ToolPermission = ToolPermission.ASK,
    model: ModelRef = ModelRef(ProviderId.DEEPSEEK, DEEPSEEK_REASONER),
    theme: ThemePreference = ThemePreference.DARK,
    language: Language = Language.EN
) = PublicSettings(
    defaultToolPermission = permission,
    defaultModel = model,
    theme = theme,
    hasOpenaiKey = true,
    hasAnthropicKey = true,
    hasDeepseekKey = true,
    language = language
)

/** In-memory [SecretStore]. [read] counts so a settings session can prove it never loaded a key. */
internal class MemorySecretStore : SecretStore {
    private var current = Secrets()
    var readCount: Int = 0
        private set

    override suspend fun read(): Secrets {
        readCount += 1
        return current
    }

    override suspend fun write(secrets: Secrets) {
        current = secrets
    }

    fun peek(): Secrets = current

    /** Test-side load through the port. The settings UI must not call this. */
    fun load(): Secrets = kotlinx.coroutines.runBlocking { read() }
}

/**
 * Settings-facing writer. Empty or null deletes. Merges into [store] without calling
 * [SecretStore.read], which the UI is not allowed to do.
 */
internal class MemorySecretWriter(private val store: MemorySecretStore) : SecretWriter {
    val writes = mutableListOf<Pair<ProviderId, String?>>()
    var failure: Exception? = null

    override suspend fun write(provider: ProviderId, apiKey: String?) {
        writes += provider to apiKey
        failure?.let { throw it }
        val kept = apiKey?.takeUnless { it.isEmpty() }
        val current = store.peek()
        val next = when (provider) {
            ProviderId.OPENAI -> current.copy(openaiApiKey = kept)
            ProviderId.ANTHROPIC -> current.copy(anthropicApiKey = kept)
            ProviderId.DEEPSEEK -> current.copy(deepseekApiKey = kept)
        }
        store.write(next)
    }
}

internal class FakeSettingsPort(
    initial: PublicSettings = sampleSettings()
) : SettingsPort {
    var current: PublicSettings = initial
    val patches = mutableListOf<SettingsPatch>()
    var failLanguage: Boolean = false
    var themeFailure: String? = null
    var modelFailure: String? = null
    var holdLanguage: Boolean = false
    var getGate: CompletableDeferred<Unit>? = null
    private val eventsFlow = MutableSharedFlow<HostEvent>(extraBufferCapacity = 8)
    override val events: Flow<HostEvent> = eventsFlow

    override suspend fun get(): PublicSettings {
        getGate?.await()
        return current
    }

    override suspend fun set(patch: SettingsPatch): PublicSettings {
        patches += patch
        if (patch.language != null && holdLanguage) {
            suspendCancellableCoroutine<Unit> { }
        }
        if (patch.language != null && failLanguage) throw NuumException(1, "language failed")
        themeFailure?.let { message ->
            if (patch.theme != null) throw NuumException(1, message)
        }
        modelFailure?.let { message ->
            if (patch.defaultModel != null) throw NuumException(1, message)
        }
        current = current.copy(
            defaultToolPermission = patch.defaultToolPermission ?: current.defaultToolPermission,
            defaultModel = patch.defaultModel ?: current.defaultModel,
            theme = patch.theme ?: current.theme,
            language = patch.language ?: current.language,
            sidebar = patch.sidebar ?: current.sidebar
        )
        eventsFlow.tryEmit(HostEvent.SettingsUpdated(current))
        return current
    }
}

internal class FakeClock(var now: Long = 1_000_000L) : Clock {
    override fun nowMillis(): Long = now
}

internal class FakeProactivePort(initial: ProactiveSnapshot) : ProactivePort {
    var snapshot: ProactiveSnapshot = initial
    val configures = mutableListOf<ProactiveConfigureParams>()
    val checks = mutableListOf<String>()
    var failConfigure: Boolean = false
    var failCheck: Boolean = false
    private val eventsFlow = MutableSharedFlow<HostEvent>(extraBufferCapacity = 8)
    override val events: Flow<HostEvent> = eventsFlow

    override suspend fun get(): ProactiveSnapshot = snapshot

    override suspend fun configure(params: ProactiveConfigureParams): ProactiveSnapshot {
        configures += params
        if (failConfigure) throw NuumException(1, "Proactive policy revision conflict")
        snapshot = applyConfigure(snapshot, params)
        eventsFlow.tryEmit(HostEvent.ProactiveUpdated(snapshot))
        return snapshot
    }

    override suspend fun check(agentId: String): ProactiveSnapshot {
        checks += agentId
        if (failCheck) throw NuumException(1, "check failed")
        return snapshot
    }
}

internal fun applyConfigure(snapshot: ProactiveSnapshot, params: ProactiveConfigureParams): ProactiveSnapshot {
    val agents = snapshot.agents.map { agent ->
        if (params.agentId != null && agent.agentId != params.agentId) return@map agent
        val enabled = params.enabled ?: agent.policy.enabled
        val pausedUntil = when {
            params.resume || params.enabled == false -> null
            params.pausedUntil != null -> params.pausedUntil
            else -> agent.policy.pausedUntil
        }
        val state = when {
            !enabled -> "disabled"
            pausedUntil != null -> "paused"
            else -> "waiting-context"
        }
        agent.copy(
            policy = agent.policy.copy(
                enabled = enabled,
                pausedUntil = pausedUntil,
                revision = agent.policy.revision + 1
            ),
            state = state
        )
    }
    return snapshot.copy(agents = agents)
}

internal fun proactiveAgent(
    enabled: Boolean = false,
    state: String = "disabled",
    pausedUntil: Long? = null,
    revision: Int = 4,
    name: String = "Mika",
    activity: List<com.nuum.contracts.ProactiveActivity> = emptyList()
) = ProactiveAgentSnapshot(
    agentId = "agent-1",
    name = name,
    policy = ProactivePolicy(
        revision = revision,
        isDefault = true,
        enabled = enabled,
        pausedUntil = pausedUntil
    ),
    state = state,
    activity = activity
)

internal fun proactiveSnapshot(
    agent: ProactiveAgentSnapshot? = proactiveAgent(),
    actionsAvailable: Boolean = false,
    sources: List<String> = emptyList(),
    defaultAgentId: String? = agent?.agentId
) = ProactiveSnapshot(
    defaultAgentId = defaultAgentId,
    agents = listOfNotNull(agent),
    availableSourceIds = sources,
    actionsAvailable = actionsAvailable
)
