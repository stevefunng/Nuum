package com.nuum.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.nuum.contracts.Clock
import com.nuum.contracts.HostEvent
import com.nuum.contracts.Language
import com.nuum.contracts.ProactiveAgentSnapshot
import com.nuum.contracts.ProactiveConfigureParams
import com.nuum.contracts.ProactivePort
import com.nuum.contracts.ProactiveSnapshot
import com.nuum.contracts.SettingsPort
import com.nuum.contracts.ThemePreference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

internal const val PAUSE_30_MINUTES_MS = 1_800_000L
internal const val PAUSE_1_HOUR_MS = 3_600_000L

internal data class ProactiveUiState(
    val snapshot: ProactiveSnapshot? = null,
    val loading: Boolean = true,
    val busy: Boolean = false,
    val failed: Boolean = false,
    val language: Language? = null,
    val theme: ThemePreference? = null
)

/**
 * Reads [ProactiveSnapshot.actionsAvailable] for the actions row. The screen
 * does not offer a switch that would disagree with the snapshot.
 */
internal class ProactiveViewModel(
    private val settings: SettingsPort,
    private val proactive: ProactivePort,
    private val clock: Clock,
    scope: CoroutineScope? = null
) : ViewModel() {
    private val work = scope ?: viewModelScope
    private val _state = MutableStateFlow(ProactiveUiState())
    val state: StateFlow<ProactiveUiState> = _state.asStateFlow()
    private var pending: PendingCall? = null
    private var suppressEvents = false

    init {
        work.launch {
            settings.events.collect { event ->
                if (event is HostEvent.SettingsUpdated) {
                    _state.update {
                        it.copy(language = event.settings.language, theme = event.settings.theme)
                    }
                }
            }
        }
        work.launch {
            proactive.events.collect { event ->
                if (suppressEvents) return@collect
                if (event is HostEvent.ProactiveUpdated) {
                    val snapshot = event.snapshot
                    if (snapshot != null) {
                        _state.update { it.copy(snapshot = snapshot, loading = false) }
                    } else {
                        refresh()
                    }
                }
            }
        }
        refresh()
        refreshSettings()
    }

    fun refresh() {
        work.launch {
            try {
                val snapshot = proactive.get()
                _state.update { it.copy(snapshot = snapshot, loading = false, failed = false) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                _state.update { it.copy(loading = false, failed = true) }
            }
        }
    }

    fun onToggle() {
        val agent = companion() ?: return
        if (_state.value.busy) return
        send(
            ProactiveConfigureParams(
                expectedRevision = agent.policy.revision,
                agentId = agent.agentId,
                enabled = !agent.policy.enabled,
                pausedUntil = null,
                resume = true
            )
        )
    }

    fun onResume() {
        val agent = companion() ?: return
        if (_state.value.busy) return
        send(
            ProactiveConfigureParams(
                expectedRevision = agent.policy.revision,
                agentId = agent.agentId,
                pausedUntil = null,
                resume = true
            )
        )
    }

    fun onPause(durationMs: Long) {
        val agent = companion() ?: return
        if (_state.value.busy || !agent.policy.enabled) return
        send(
            ProactiveConfigureParams(
                expectedRevision = agent.policy.revision,
                agentId = agent.agentId,
                pausedUntil = clock.nowMillis() + durationMs
            )
        )
    }

    fun onCheck() {
        val agent = companion() ?: return
        val state = _state.value
        if (state.busy || state.snapshot == null) return
        if (!agent.policy.enabled || agent.state == "paused" || agent.state == "checking") return
        val call = PendingCall.Check(agent.agentId)
        pending = call
        work.launch {
            suppressEvents = true
            _state.update { it.copy(busy = true, failed = false) }
            try {
                val snapshot = proactive.check(agent.agentId)
                _state.update { it.copy(snapshot = snapshot, loading = false, busy = false, failed = false) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                _state.update { it.copy(busy = false, failed = true) }
            } finally {
                suppressEvents = false
            }
        }
    }

    fun onRetry() {
        when (val call = pending) {
            is PendingCall.Configure -> send(call.params)
            is PendingCall.Check -> {
                pending = call
                work.launch {
                    suppressEvents = true
                    _state.update { it.copy(busy = true, failed = false) }
                    try {
                        val snapshot = proactive.check(call.agentId)
                        _state.update {
                            it.copy(snapshot = snapshot, loading = false, busy = false, failed = false)
                        }
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (_: Exception) {
                        _state.update { it.copy(busy = false, failed = true) }
                    } finally {
                        suppressEvents = false
                    }
                }
            }
            null -> {
                refresh()
                refreshSettings()
            }
        }
    }

    private fun send(params: ProactiveConfigureParams) {
        pending = PendingCall.Configure(params)
        work.launch {
            suppressEvents = true
            _state.update { it.copy(busy = true, failed = false) }
            try {
                val snapshot = proactive.configure(params)
                _state.update { it.copy(snapshot = snapshot, loading = false, busy = false, failed = false) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                _state.update { it.copy(busy = false, failed = true) }
            } finally {
                suppressEvents = false
            }
        }
    }

    private fun refreshSettings() {
        work.launch {
            try {
                val settings = settings.get()
                _state.update { it.copy(language = settings.language, theme = settings.theme) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // Proactive still renders; language stays on the system default.
            }
        }
    }

    private fun companion(): ProactiveAgentSnapshot? {
        val snapshot = _state.value.snapshot ?: return null
        return snapshot.agents.firstOrNull { it.agentId == snapshot.defaultAgentId }
    }

    private sealed interface PendingCall {
        data class Configure(val params: ProactiveConfigureParams) : PendingCall
        data class Check(val agentId: String) : PendingCall
    }

    companion object {
        fun factory(
            settings: SettingsPort,
            proactive: ProactivePort,
            clock: Clock
        ): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                ProactiveViewModel(settings, proactive, clock) as T
        }
    }
}

internal enum class ConnectionLabel { Available, NotConnected }

/** Agent-actions copy is a function of the snapshot flag, not a fixed switch. */
internal fun agentActionsLabel(actionsAvailable: Boolean): ConnectionLabel =
    if (actionsAvailable) ConnectionLabel.Available else ConnectionLabel.NotConnected

internal fun contextSourcesLabel(availableSourceIds: List<String>): ConnectionLabel =
    if (availableSourceIds.isNotEmpty()) ConnectionLabel.Available else ConnectionLabel.NotConnected

internal fun proactiveCompanion(snapshot: ProactiveSnapshot?): ProactiveAgentSnapshot? =
    snapshot?.agents?.firstOrNull { it.agentId == snapshot.defaultAgentId }
