package com.nuum.agent

import com.nuum.contracts.HostEvent
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NuumException
import com.nuum.contracts.NuumPaths
import com.nuum.contracts.ProactiveConfigureParams as CConfigure
import com.nuum.contracts.ProactiveSnapshot as CSnapshot
import com.nuum.protocol.ProactiveActivity
import com.nuum.protocol.ProactiveActivityKind
import com.nuum.protocol.ProactiveAgentSnapshot
import com.nuum.protocol.ProactiveAgentState
import com.nuum.protocol.ProactivePolicy
import com.nuum.protocol.ProactiveSnapshot
import com.nuum.protocol.ProtocolJson
import com.nuum.protocol.ProtocolParseException
import com.nuum.protocol.validateProactiveConfigure
import com.nuum.protocol.validateProactivePolicy
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.builtins.ListSerializer

/**
 * Snapshot only. No sources are registered and there is no 1s tick.
 * [ProactiveSnapshot.actionsAvailable] is always false.
 */
internal suspend fun HostRuntime.proactiveSnapshot(): CSnapshot {
    ensureLoaded()
    val agentsWithPolicy = agents.values.filter { it.settings.proactive != null }
    val snapshots = agentsWithPolicy.map { record ->
        val policy = record.settings.proactive ?: ProactivePolicy(revision = 0)
        ProactiveAgentSnapshot(
            agentId = record.profile.id,
            name = record.profile.name,
            policy = policy,
            state = proactiveState(record.profile.id, policy),
            activity = readActivity(record.profile.id)
        )
    }
    val defaultId = agentsWithPolicy.firstOrNull { it.settings.proactive?.isDefault == true }?.profile?.id
    return ProactiveSnapshot(
        defaultAgentId = defaultId,
        agents = snapshots,
        availableSourceIds = emptyList(),
        actionsAvailable = false
    ).toContract()
}

internal suspend fun HostRuntime.configureProactive(params: CConfigure): CSnapshot {
    ensureLoaded()
    val protocolParams = com.nuum.protocol.ProactiveConfigureParams(
        agentId = params.agentId,
        expectedRevision = params.expectedRevision,
        enabled = params.enabled,
        pausedUntil = if (params.resume) null else params.pausedUntil,
        sourceIds = params.sourceIds,
        intervalMs = params.intervalMs
    )
    try {
        validateProactiveConfigure(protocolParams)
    } catch (error: ProtocolParseException) {
        throw NuumException(KernelErrorCode.INVALID, error.message ?: "Invalid proactive policy")
    }
    if (params.sourceIds.orEmpty().isNotEmpty()) {
        throw NuumException(KernelErrorCode.INVALID, "Unknown proactive source: ${params.sourceIds!!.first()}")
    }
    gate.withLock {
        var record = params.agentId?.let { agents[it] } ?: agents.values.firstOrNull { it.settings.proactive?.isDefault == true }
        if (record == null) {
            if (params.expectedRevision != 0) throw NuumException(KernelErrorCode.INVALID, "Proactive policy revision conflict")
            val created = createAgentLocked(com.nuum.contracts.AgentCreateParams(name = "Nunu", tags = listOf("proactive")))
            record = requireAgent(created.profile.id)
            record.settings = record.settings.copy(proactive = ProactivePolicy(revision = 0, isDefault = true))
        }
        val previous = record.settings.proactive ?: ProactivePolicy(revision = 0)
        if (previous.revision != params.expectedRevision) {
            throw NuumException(KernelErrorCode.INVALID, "Proactive policy revision conflict")
        }
        val requestedPause = params.pausedUntil
        val policy = previous.copy(
            revision = previous.revision + 1,
            isDefault = previous.isDefault || params.agentId == null,
            enabled = params.enabled ?: previous.enabled,
            pausedUntil = when {
                params.enabled == false -> null
                params.resume -> null
                requestedPause != null -> requestedPause
                else -> previous.pausedUntil
            },
            sourceIds = params.sourceIds ?: previous.sourceIds,
            intervalMs = params.intervalMs ?: previous.intervalMs
        )
        try {
            validateProactivePolicy(policy)
        } catch (error: ProtocolParseException) {
            throw NuumException(KernelErrorCode.INVALID, error.message ?: "Invalid proactive policy")
        }
        record.settings = record.settings.copy(proactive = policy)
        store.writeDoc(NuumPaths.agentSettingsPath(record.profile.id), com.nuum.protocol.AgentSettings.serializer(), record.settings)
        val pausedUntil = policy.pausedUntil
        val kind = when {
            !policy.enabled -> ProactiveActivityKind.DISABLED
            !previous.enabled -> ProactiveActivityKind.ENABLED
            pausedUntil != null && pausedUntil > clock.nowMillis() -> ProactiveActivityKind.PAUSED
            previous.pausedUntil != null -> ProactiveActivityKind.RESUMED
            else -> ProactiveActivityKind.CONFIGURED
        }
        recordActivity(record.profile.id, kind)
        emit(HostEvent.AgentUpdated(viewOf(record)))
    }
    val snapshot = proactiveSnapshot()
    emit(HostEvent.ProactiveUpdated(snapshot))
    return snapshot
}

internal suspend fun HostRuntime.checkProactive(agentId: String): CSnapshot {
    ensureLoaded()
    val record = agents[agentId] ?: throw NuumException(com.nuum.contracts.HostErrorCode.AGENT_NOT_FOUND, "Agent not found")
    val policy = record.settings.proactive ?: throw NuumException(KernelErrorCode.INVALID, "Proactive mode disabled")
    if (!policy.enabled) throw NuumException(KernelErrorCode.INVALID, "Proactive mode disabled")
    val pausedUntil = policy.pausedUntil
    if (pausedUntil != null && pausedUntil > clock.nowMillis()) {
        throw NuumException(KernelErrorCode.INVALID, "Proactive mode paused")
    }
    recordActivity(agentId, ProactiveActivityKind.WAITING_CONTEXT)
    val snapshot = proactiveSnapshot()
    emit(HostEvent.ProactiveUpdated(snapshot))
    return snapshot
}

private fun HostRuntime.proactiveState(agentId: String, policy: ProactivePolicy): ProactiveAgentState {
    if (!policy.enabled) return ProactiveAgentState.DISABLED
    val pausedUntil = policy.pausedUntil
    if (pausedUntil != null && pausedUntil > clock.nowMillis()) return ProactiveAgentState.PAUSED
    return ProactiveAgentState.WAITING_CONTEXT
}

private suspend fun HostRuntime.readActivity(agentId: String): List<ProactiveActivity> {
    val path = "${NuumPaths.agentDir(agentId)}/proactive-activity.json"
    val text = store.readText(path)?.trim().orEmpty()
    if (text.isEmpty()) return emptyList()
    return try {
        ProtocolJson.decodeFromString(ListSerializer(ProactiveActivity.serializer()), text)
    } catch (_: Exception) {
        emptyList()
    }
}

private suspend fun HostRuntime.recordActivity(agentId: String, kind: ProactiveActivityKind) {
    val prior = readActivity(agentId)
    val next = listOf(ProactiveActivity(ids(), clock.nowMillis(), kind, emptyList())) + prior
    val path = "${NuumPaths.agentDir(agentId)}/proactive-activity.json"
    val encoded = ProtocolJson.encodeToString(ListSerializer(ProactiveActivity.serializer()), next.take(50))
    store.writeTextAtomic(path, encoded + "\n")
}
