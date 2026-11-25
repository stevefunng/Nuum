import Foundation
import NuumContracts

let unassignedSection = "__unassigned__"
let pinnedSection = "__pinned__"

func toggleSidebarPin(_ state: SidebarOrganization, id: String) -> SidebarOrganization {
    var next = state
    if state.pinnedAgentIds.contains(id) {
        next.pinnedAgentIds = state.pinnedAgentIds.filter { $0 != id }
    } else {
        next.pinnedAgentIds = state.pinnedAgentIds + [id]
    }
    return next
}

func assignSidebarAgent(_ state: SidebarOrganization, id: String, sectionID: String) -> SidebarOrganization {
    if sectionID == pinnedSection {
        if state.pinnedAgentIds.contains(id) { return state }
        return toggleSidebarPin(state, id: id)
    }
    if sectionID != unassignedSection && !state.sections.contains(where: { $0.id == sectionID }) {
        return state
    }
    var next = state
    next.pinnedAgentIds = state.pinnedAgentIds.filter { $0 != id }
    next.sections = state.sections.map { section in
        var copy = section
        let kept = section.agentIds.filter { $0 != id }
        copy.agentIds = section.id == sectionID ? kept + [id] : kept
        return copy
    }
    return next
}

func reorderSidebarPin(_ state: SidebarOrganization, id: String, beforeID: String) -> SidebarOrganization {
    if id == beforeID { return state }
    var remaining = state.pinnedAgentIds.filter { $0 != id }
    let index = remaining.firstIndex(of: beforeID) ?? remaining.endIndex
    remaining.insert(id, at: index)
    var next = state
    next.pinnedAgentIds = remaining
    return next
}

func removeSidebarSection(_ state: SidebarOrganization, id: String) -> SidebarOrganization {
    var next = state
    next.sections = state.sections.filter { $0.id != id }
    return next
}

func moveSidebarSection(_ state: SidebarOrganization, index: Int, offset: Int) -> SidebarOrganization {
    let target = index + offset
    guard state.sections.indices.contains(index), state.sections.indices.contains(target) else { return state }
    var sections = state.sections
    let item = sections.remove(at: index)
    sections.insert(item, at: target)
    var next = state
    next.sections = sections
    return next
}

func withGroup(
    _ state: SidebarOrganization,
    sectionID: String?,
    agentID: String?,
    name: String,
    newID: String
) -> SidebarOrganization {
    var sections = state.sections
    let target: String
    if let sectionID {
        target = sectionID
        sections = sections.map { section in
            guard section.id == sectionID else { return section }
            var copy = section
            copy.name = name
            return copy
        }
    } else {
        target = newID
        sections.append(SidebarSection(id: newID, name: name, agentIds: [], isCollapsed: false))
    }
    var next = state
    next.sections = sections
    if let agentID {
        return assignSidebarAgent(next, id: agentID, sectionID: target)
    }
    return next
}

func visibleAgents(_ agents: [AgentView], query: String) -> [AgentView] {
    let listed = agents.filter { !$0.settings.hiddenFromSidebar }
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if needle.isEmpty { return listed }
    return listed.filter { agent in
        agent.profile.name.lowercased().contains(needle)
            || agent.profile.description.lowercased().contains(needle)
            || agent.profile.tags.contains { $0.lowercased().contains(needle) }
    }
}

func visibleWorks(_ works: [WorkListItem], query: String) -> [WorkListItem] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if needle.isEmpty { return works }
    return works.filter { work in
        work.profile.name.lowercased().contains(needle)
            || work.profile.description.lowercased().contains(needle)
            || (work.preview ?? "").lowercased().contains(needle)
    }
}

func relativeTime(nowMillis: Int64, atMillis: Int64) -> (key: String, count: Int?) {
    let seconds = max(0, (nowMillis - atMillis) / 1000)
    if seconds < 60 { return ("now", nil) }
    let minutes = Int((seconds + 30) / 60)
    if minutes < 60 { return ("{count}m", minutes) }
    let hours = (minutes + 30) / 60
    if hours < 24 { return ("{count}h", hours) }
    return ("{count}d", (hours + 12) / 24)
}

func splitTags(_ raw: String) -> [String] {
    raw.split { $0 == "," || $0 == "，" || $0 == "、" || $0 == "\n" }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func createdOnDate(_ millis: Int64) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let date = Date(timeIntervalSince1970: Double(millis) / 1000)
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    let year = parts.year ?? 1970
    let month = parts.month ?? 1
    let day = parts.day ?? 1
    return String(format: "%04d/%02d/%02d", year, month, day)
}

func newMenuWidth(sidebarWidth: Double) -> Double {
    min(max(sidebarWidth - SandMetric.newMenuInset, SandMetric.newMenuMin), SandMetric.newMenuMax)
}

func profilePaneWidth(contentWidth: Double) -> Double {
    min(max(contentWidth * SandMetric.profileFraction, SandMetric.profileMin), SandMetric.profileMax)
}

func unboxRegionHeight(windowHeight: Double) -> Double {
    windowHeight < SandMetric.unboxShortBelow ? SandMetric.unboxShort : SandMetric.unboxTall
}

struct IdentityTemplate: Equatable, Sendable {
    var nameKey: String
    var descriptionKey: String
    var tagsKey: String
    var colorID: String
    var shape: String
}

let identityTemplates: [IdentityTemplate] = [
    IdentityTemplate(
        nameKey: "Researcher",
        descriptionKey: "Track a topic, read sources, and bring back concise findings.",
        tagsKey: "Research, sources",
        colorID: "blue",
        shape: "droplet"
    ),
    IdentityTemplate(
        nameKey: "Project partner",
        descriptionKey: "Stay with one project, remember decisions, and help move it forward.",
        tagsKey: "Projects, follow-ups",
        colorID: "green",
        shape: "blob"
    ),
    IdentityTemplate(
        nameKey: "Daily operator",
        descriptionKey: "Handle recurring local tasks and keep an eye on follow-ups.",
        tagsKey: "Daily tasks, reminders",
        colorID: "orange",
        shape: "tablet"
    ),
]

struct IdentityDraft: Equatable, Sendable {
    var name: String
    var tags: String
    var description: String
}

func applying(_ template: IdentityTemplate, copy: ShellCopy) -> IdentityDraft {
    IdentityDraft(
        name: copy.text(template.nameKey),
        tags: copy.text(template.tagsKey),
        description: copy.text(template.descriptionKey)
    )
}
