package com.nuum.contracts

data class ProactivePolicy(
    val revision: Int,
    val isDefault: Boolean = false,
    val enabled: Boolean = false,
    val pausedUntil: Long? = null,
    val sourceIds: List<String> = emptyList(),
    val intervalMs: Long = 300_000
)

data class ProactiveConfigureParams(
    val expectedRevision: Int,
    val agentId: String? = null,
    val enabled: Boolean? = null,
    val pausedUntil: Long? = null,
    val resume: Boolean = false,
    val sourceIds: List<String>? = null,
    val intervalMs: Long? = null
)

data class ProactiveActivity(
    val id: String,
    val at: Long,
    val kind: String,
    val contextRefs: List<String> = emptyList()
)

data class ProactiveAgentSnapshot(
    val agentId: String,
    val name: String,
    val policy: ProactivePolicy,
    val state: String,
    val activity: List<ProactiveActivity>
)

/**
 * `actionsAvailable` stays false until a real action executor exists.
 * UI reads the snapshot; it does not hard-code the flag.
 */
data class ProactiveSnapshot(
    val defaultAgentId: String?,
    val agents: List<ProactiveAgentSnapshot>,
    val availableSourceIds: List<String>,
    val actionsAvailable: Boolean = false
)
