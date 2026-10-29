package com.nuum.graph

import com.nuum.contracts.TurnSupervisor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * PoC turn lifetime. The scope outlives any one screen. A later build can
 * replace this with a foreground-service supervisor without touching Host.
 */
class InProcessTurnSupervisor(
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
) : TurnSupervisor {
    override fun launch(block: suspend () -> Unit): Job = scope.launch { block() }
}
