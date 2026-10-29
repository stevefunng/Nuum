package com.nuum.feature.shell.sidebar

import com.nuum.contracts.AgentView
import com.nuum.contracts.SidebarOrganization
import com.nuum.contracts.SidebarSection
import com.nuum.contracts.WorkListItem
import com.nuum.protocol.ProtocolIssue
import com.nuum.protocol.ProtocolParseException
import com.nuum.protocol.SIDEBAR_UNIQUENESS_MESSAGE
import com.nuum.protocol.validateSidebar

internal const val UNASSIGNED_SECTION = "__unassigned__"
internal const val PINNED_SECTION = "__pinned__"
internal const val SIDEBAR_SAVE_FAILED = "Could not save sidebar changes. Please try again."
internal const val COPY_FAILED = "Could not copy Agent ID."

internal const val SIDEBAR_DEFAULT_WIDTH = 236
internal const val SIDEBAR_MIN_EXPANDED = 220
internal const val SIDEBAR_MAX_EXPANDED = 400
internal const val SIDEBAR_COLLAPSED = 88
internal const val SIDEBAR_COLLAPSE_BELOW = 208

internal data class SidebarLayoutState(
    val expandedWidth: Int = SIDEBAR_DEFAULT_WIDTH,
    val isCollapsed: Boolean = false
)

internal data class ProjectedSection(
    val id: String,
    val name: String,
    val isCollapsed: Boolean,
    val agents: List<AgentView>
)

internal data class SidebarProjection(
    val pinned: List<AgentView>,
    val sections: List<ProjectedSection>,
    val unassigned: List<AgentView>
)

internal sealed interface SidebarRow {
    data class Agent(val agent: AgentView) : SidebarRow
    data class Work(val work: WorkListItem) : SidebarRow
}

internal fun toggleSidebarPin(state: SidebarOrganization, id: String): SidebarOrganization {
    val pins = if (id in state.pinnedAgentIds) {
        state.pinnedAgentIds.filterNot { it == id }
    } else {
        state.pinnedAgentIds + id
    }
    return state.copy(pinnedAgentIds = pins)
}

internal fun assignSidebarAgent(state: SidebarOrganization, id: String, sectionId: String): SidebarOrganization {
    if (sectionId == PINNED_SECTION) {
        return if (id in state.pinnedAgentIds) state else toggleSidebarPin(state, id)
    }
    if (sectionId != UNASSIGNED_SECTION && state.sections.none { it.id == sectionId }) return state
    return state.copy(
        pinnedAgentIds = state.pinnedAgentIds.filterNot { it == id },
        sections = state.sections.map { section ->
            val kept = section.agentIds.filterNot { it == id }
            section.copy(agentIds = if (section.id == sectionId) kept + id else kept)
        }
    )
}

internal fun reorderSidebarPin(state: SidebarOrganization, id: String, beforeId: String): SidebarOrganization {
    if (id == beforeId) return state
    val remaining = state.pinnedAgentIds.filterNot { it == id }.toMutableList()
    val index = remaining.indexOf(beforeId)
    remaining.add(if (index < 0) remaining.size else index, id)
    return state.copy(pinnedAgentIds = remaining)
}

internal fun removeSidebarSection(state: SidebarOrganization, id: String): SidebarOrganization =
    state.copy(sections = state.sections.filterNot { it.id == id })

internal fun moveSidebarSection(state: SidebarOrganization, index: Int, offset: Int): SidebarOrganization {
    val target = index + offset
    if (index !in state.sections.indices || target !in state.sections.indices) return state
    val sections = state.sections.toMutableList()
    val item = sections.removeAt(index)
    sections.add(target, item)
    return state.copy(sections = sections)
}

internal fun projectSidebarAgents(agents: List<AgentView>, state: SidebarOrganization): SidebarProjection {
    val byId = agents.associateBy { it.profile.id }
    val pinnedIds = state.pinnedAgentIds.toSet()
    val pinned = state.pinnedAgentIds.mapNotNull { byId[it] }
    val grouped = state.sections.flatMap { it.agentIds }.toSet()
    return SidebarProjection(
        pinned = pinned,
        sections = state.sections.map { section ->
            ProjectedSection(
                id = section.id,
                name = section.name,
                isCollapsed = section.isCollapsed,
                agents = agents.filter { agent ->
                    agent.profile.id !in pinnedIds && agent.profile.id in section.agentIds
                }
            )
        },
        unassigned = agents.filter { it.profile.id !in pinnedIds && it.profile.id !in grouped }
    )
}

internal fun visibleAgents(agents: List<AgentView>, query: String): List<AgentView> {
    val listed = agents.filterNot { it.settings.hiddenFromSidebar }
    val needle = query.trim().lowercase()
    if (needle.isEmpty()) return listed
    return listed.filter { agent ->
        agent.profile.name.lowercase().contains(needle) ||
            agent.profile.description.lowercase().contains(needle) ||
            agent.profile.tags.any { it.lowercase().contains(needle) }
    }
}

internal fun visibleWorks(works: List<WorkListItem>, query: String): List<WorkListItem> {
    val needle = query.trim().lowercase()
    if (needle.isEmpty()) return works
    return works.filter { work ->
        work.profile.name.lowercase().contains(needle) ||
            work.profile.description.lowercase().contains(needle) ||
            (work.preview ?: "").lowercase().contains(needle)
    }
}

internal fun mergedRows(unassigned: List<AgentView>, works: List<WorkListItem>): List<SidebarRow> {
    val rows = buildList<SidebarRow> {
        unassigned.forEach { add(SidebarRow.Agent(it)) }
        works.forEach { add(SidebarRow.Work(it)) }
    }
    return rows.sortedByDescending { row ->
        when (row) {
            is SidebarRow.Agent -> row.agent.runtime.lastActivityAt
            is SidebarRow.Work -> row.work.lastActivityAt
        }
    }
}

internal fun displaySidebarWidth(layout: SidebarLayoutState, liveWidth: Int?, dragging: Boolean): Int {
    if (dragging && liveWidth != null) return liveWidth.coerceIn(SIDEBAR_COLLAPSED, SIDEBAR_MAX_EXPANDED)
    return if (layout.isCollapsed) SIDEBAR_COLLAPSED else layout.expandedWidth
}

internal fun settleSidebarLayout(liveWidth: Int, previousExpanded: Int, windowDp: Int): SidebarLayoutState {
    if (liveWidth < SIDEBAR_COLLAPSE_BELOW) {
        return SidebarLayoutState(clampExpanded(previousExpanded, windowDp), isCollapsed = true)
    }
    return SidebarLayoutState(clampExpanded(liveWidth, windowDp), isCollapsed = false)
}

internal fun clampExpanded(width: Int, windowDp: Int): Int {
    val windowCap = (windowDp * 0.42f).toInt().coerceAtLeast(SIDEBAR_MIN_EXPANDED)
    val max = minOf(SIDEBAR_MAX_EXPANDED, windowCap)
    return width.coerceIn(SIDEBAR_MIN_EXPANDED, max)
}

internal fun SidebarOrganization.toProtocol(): com.nuum.protocol.SidebarOrganization =
    com.nuum.protocol.SidebarOrganization(
        pinnedAgentIds = pinnedAgentIds,
        sections = sections.map { section ->
            com.nuum.protocol.SidebarSection(
                id = section.id,
                name = section.name,
                agentIds = section.agentIds,
                isCollapsed = section.isCollapsed
            )
        }
    )

internal fun com.nuum.protocol.SidebarOrganization.toContracts(): SidebarOrganization =
    SidebarOrganization(
        pinnedAgentIds = pinnedAgentIds,
        sections = sections.map { section ->
            SidebarSection(
                id = section.id,
                name = section.name,
                agentIds = section.agentIds,
                isCollapsed = section.isCollapsed == true
            )
        }
    )

/**
 * Trims names through [validateSidebar]. Duplicate trimmed names use the same
 * protocol sentence as id, membership, and pin collisions. `validateSidebar`
 * itself only checks those three sets; the screen spec still shows that host
 * sentence when a group name is rejected.
 */
internal fun prepareSidebarSave(value: SidebarOrganization): SidebarOrganization {
    val validated = validateSidebar(value.toProtocol()).toContracts()
    val names = validated.sections.map { it.name }
    if (names.size != names.toSet().size) {
        throw ProtocolParseException(listOf(ProtocolIssue(emptyList(), SIDEBAR_UNIQUENESS_MESSAGE)))
    }
    return validated
}

internal fun protocolSentence(error: ProtocolParseException): String =
    error.issues.joinToString("\n") { it.message }.ifBlank { error.message ?: SIDEBAR_SAVE_FAILED }

internal fun withGroup(
    state: SidebarOrganization,
    sectionId: String?,
    agentId: String?,
    name: String,
    newId: String
): SidebarOrganization {
    val sections = if (sectionId == null) {
        state.sections + SidebarSection(id = newId, name = name, agentIds = emptyList(), isCollapsed = false)
    } else {
        state.sections.map { if (it.id == sectionId) it.copy(name = name) else it }
    }
    val next = state.copy(sections = sections)
    val target = sectionId ?: newId
    return if (agentId != null) assignSidebarAgent(next, agentId, target) else next
}

internal fun relativeTimeKey(nowMillis: Long, atMillis: Long): Pair<String, Int?> {
    val seconds = ((nowMillis - atMillis) / 1000L).coerceAtLeast(0L)
    if (seconds < 60) return "now" to null
    val minutes = ((seconds + 30) / 60).toInt()
    if (minutes < 60) return "{count}m" to minutes
    val hours = ((minutes + 30) / 60)
    if (hours < 24) return "{count}h" to hours
    return "{count}d" to ((hours + 12) / 24)
}
