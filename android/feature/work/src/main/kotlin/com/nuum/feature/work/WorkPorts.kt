package com.nuum.feature.work

import com.nuum.contracts.AgentPort
import com.nuum.contracts.DesktopPort
import com.nuum.contracts.WorkPort

/**
 * Ports this screen is allowed to call.
 * Concrete core implementations stay outside this module; tests supply fakes.
 */
data class WorkPorts(
    val work: WorkPort,
    val agent: AgentPort,
    val desktop: DesktopPort,
)
