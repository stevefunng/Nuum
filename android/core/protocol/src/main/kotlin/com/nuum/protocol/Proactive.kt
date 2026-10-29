package com.nuum.protocol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

const val PROACTIVE_INTERVAL_MIN_MS = 60_000L
const val PROACTIVE_INTERVAL_MAX_MS = 3_600_000L
const val PROACTIVE_INTERVAL_DEFAULT_MS = 300_000L
const val PROACTIVE_MAX_SOURCES = 20
const val DUPLICATE_CONTEXT_SOURCE = "Duplicate context source"

@Serializable
data class ProactivePolicy(
    val revision: Int,
    val isDefault: Boolean = false,
    val enabled: Boolean = false,
    val pausedUntil: Long? = null,
    val sourceIds: List<String> = emptyList(),
    val intervalMs: Long = PROACTIVE_INTERVAL_DEFAULT_MS
)

@Serializable
data class ProactiveConfigureParams(
    val agentId: String? = null,
    val expectedRevision: Int,
    val enabled: Boolean? = null,
    val pausedUntil: Long? = null,
    val sourceIds: List<String>? = null,
    val intervalMs: Long? = null
)

@Serializable
enum class ProactiveActivityKind {
    @SerialName("enabled") ENABLED,
    @SerialName("disabled") DISABLED,
    @SerialName("paused") PAUSED,
    @SerialName("resumed") RESUMED,
    @SerialName("configured") CONFIGURED,
    @SerialName("waiting-context") WAITING_CONTEXT,
    @SerialName("context-ready") CONTEXT_READY,
    @SerialName("no-change") NO_CHANGE,
    @SerialName("error") ERROR
}

@Serializable
data class ProactiveActivity(
    val id: String,
    val at: Long,
    val kind: ProactiveActivityKind,
    val contextRefs: List<String> = emptyList()
)

@Serializable
enum class ProactiveAgentState {
    @SerialName("disabled") DISABLED,
    @SerialName("paused") PAUSED,
    @SerialName("waiting-context") WAITING_CONTEXT,
    @SerialName("ready") READY,
    @SerialName("checking") CHECKING,
    @SerialName("error") ERROR
}

@Serializable
data class ProactiveAgentSnapshot(
    val agentId: String,
    val name: String,
    val policy: ProactivePolicy,
    val state: ProactiveAgentState,
    val activity: List<ProactiveActivity>
)

/**
 * `actionsAvailable` is the literal `false`. The snapshot cannot represent a
 * future in which actions run; that stays false until an executor exists.
 */
@Serializable
data class ProactiveSnapshot(
    val defaultAgentId: String?,
    val agents: List<ProactiveAgentSnapshot>,
    val availableSourceIds: List<String>,
    val actionsAvailable: Boolean
) {
    init {
        require(!actionsAvailable) { "actionsAvailable must be false" }
    }
}

fun validateProactivePolicy(policy: ProactivePolicy) {
    val issues = mutableListOf<ProtocolIssue>()
    if (policy.revision < 0) issues += ProtocolIssue(listOf("revision"), "Number must be greater than or equal to 0")
    validateSourceIds(policy.sourceIds, issues)
    validateInterval(policy.intervalMs, issues)
    policy.pausedUntil?.let { paused ->
        if (paused < 0) issues += ProtocolIssue(listOf("pausedUntil"), "Number must be greater than or equal to 0")
    }
    if (issues.isNotEmpty()) throw ProtocolParseException(issues)
}

fun validateProactiveConfigure(params: ProactiveConfigureParams) {
    val issues = mutableListOf<ProtocolIssue>()
    if (params.expectedRevision < 0) {
        issues += ProtocolIssue(listOf("expectedRevision"), "Number must be greater than or equal to 0")
    }
    params.agentId?.let { id ->
        if (id.isEmpty()) issues += ProtocolIssue(listOf("agentId"), "String must contain at least 1 character(s)")
    }
    params.sourceIds?.let { validateSourceIds(it, issues) }
    params.intervalMs?.let { validateInterval(it, issues) }
    params.pausedUntil?.let { paused ->
        if (paused < 0) issues += ProtocolIssue(listOf("pausedUntil"), "Number must be greater than or equal to 0")
    }
    if (issues.isNotEmpty()) throw ProtocolParseException(issues)
}

private fun validateSourceIds(ids: List<String>, issues: MutableList<ProtocolIssue>) {
    if (ids.size > PROACTIVE_MAX_SOURCES) {
        issues += ProtocolIssue(listOf("sourceIds"), "Array must contain at most 20 element(s)")
    }
    ids.forEachIndexed { index, id ->
        if (id.isEmpty()) issues += ProtocolIssue(listOf("sourceIds", index.toString()), "String must contain at least 1 character(s)")
    }
    if (ids.toSet().size != ids.size) issues += ProtocolIssue(listOf("sourceIds"), DUPLICATE_CONTEXT_SOURCE)
}

private fun validateInterval(intervalMs: Long, issues: MutableList<ProtocolIssue>) {
    if (intervalMs < PROACTIVE_INTERVAL_MIN_MS || intervalMs > PROACTIVE_INTERVAL_MAX_MS) {
        issues += ProtocolIssue(listOf("intervalMs"), "Number must be greater than or equal to 60000")
    }
}
