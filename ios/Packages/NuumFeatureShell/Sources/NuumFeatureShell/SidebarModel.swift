import NuumContracts

enum SidebarPlaceholder: Equatable, Sendable {
    case loading
    case noAgents
    case noMatch
}

struct AgentRowModel: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var preview: CopyLine
    var time: CopyLine
    var running: Bool
    var selected: Bool
    var pinned: Bool
    var appearance: NunuAppearance
}

struct WorkRowModel: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var preview: CopyLine
    var time: CopyLine
    var selected: Bool
    var initial: String
    var members: [NunuAppearance]
}

enum SidebarEntry: Equatable, Identifiable, Sendable {
    case agent(AgentRowModel)
    case work(WorkRowModel)

    var id: String {
        switch self {
        case .agent(let row): "agent-\(row.id)"
        case .work(let row): "work-\(row.id)"
        }
    }
}

struct SectionModel: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var count: Int
    var collapsed: Bool
    var agents: [AgentRowModel]
    var showEmptyHint: Bool
}

struct SidebarSnapshot: Equatable, Sendable {
    var placeholder: SidebarPlaceholder?
    var pinned: [AgentRowModel]
    var sections: [SectionModel]
    var showUnassignedLabel: Bool
    var unassigned: [SidebarEntry]
    var railRows: [SidebarEntry]
    var collapsedRail: Bool
    var showSearchField: Bool
    var showPinBand: Bool
    var notice: CopyLine?
}

enum MenuKind: Equatable, Sendable {
    case pin
    case unpin
    case moveToGroup
    case moveToNewGroup
    case editProfile
    case copyID
    case back
    case group(String)
    case unassigned
    case newGroup
    case rename
    case moveUp
    case moveDown
    case ungroup
    case createNunu
    case createWork
}

struct MenuEntry: Equatable, Identifiable, Sendable {
    var kind: MenuKind
    var title: CopyLine
    var enabled: Bool
    var separatorBefore: Bool

    var id: String {
        switch kind {
        case .group(let id): "group-\(id)"
        default: String(describing: kind)
        }
    }
}

func agentMenuEntries(pinned: Bool, hasGroups: Bool) -> [MenuEntry] {
    [
        MenuEntry(kind: pinned ? .unpin : .pin, title: CopyLine(key: pinned ? "Unpin" : "Pin"), enabled: true, separatorBefore: false),
        MenuEntry(
            kind: hasGroups ? .moveToGroup : .moveToNewGroup,
            title: CopyLine(key: hasGroups ? "Move to group" : "Move to new group"),
            enabled: true,
            separatorBefore: false
        ),
        MenuEntry(kind: .editProfile, title: CopyLine(key: "Edit profile"), enabled: true, separatorBefore: true),
        MenuEntry(kind: .copyID, title: CopyLine(key: "Copy Agent ID"), enabled: true, separatorBefore: false),
    ]
}

func groupSubmenuEntries(_ groups: [(id: String, name: String)]) -> [MenuEntry] {
    var entries = [MenuEntry(kind: .back, title: CopyLine(key: "Back"), enabled: true, separatorBefore: false)]
    entries += groups.map {
        MenuEntry(kind: .group($0.id), title: CopyLine(key: $0.name), enabled: true, separatorBefore: false)
    }
    entries.append(MenuEntry(kind: .unassigned, title: CopyLine(key: "Unassigned"), enabled: true, separatorBefore: false))
    entries.append(MenuEntry(kind: .newGroup, title: CopyLine(key: "New group…"), enabled: true, separatorBefore: true))
    return entries
}

func sectionMenuEntries(index: Int, count: Int, saving: Bool) -> [MenuEntry] {
    [
        MenuEntry(kind: .rename, title: CopyLine(key: "Rename group…"), enabled: !saving, separatorBefore: false),
        MenuEntry(kind: .moveUp, title: CopyLine(key: "Move up"), enabled: index > 0, separatorBefore: false),
        MenuEntry(kind: .moveDown, title: CopyLine(key: "Move down"), enabled: index < count - 1, separatorBefore: false),
        MenuEntry(kind: .ungroup, title: CopyLine(key: "Ungroup agents"), enabled: !saving, separatorBefore: true),
    ]
}

func newMenuEntries() -> [MenuEntry] {
    [
        MenuEntry(kind: .createNunu, title: CopyLine(key: "Create new Nunu"), enabled: true, separatorBefore: false),
        MenuEntry(kind: .createWork, title: CopyLine(key: "Create NunuBar"), enabled: true, separatorBefore: false),
    ]
}

struct ProjectedSidebar {
    var pinned: [AgentView]
    var sections: [(section: SidebarSection, agents: [AgentView])]
    var unassignedAgents: [AgentView]
}

func projectSidebar(agents: [AgentView], organization: SidebarOrganization) -> ProjectedSidebar {
    let byID = Dictionary(uniqueKeysWithValues: agents.map { ($0.profile.id, $0) })
    let pinnedIDs = Set(organization.pinnedAgentIds)
    let grouped = Set(organization.sections.flatMap(\.agentIds))
    let pinned = organization.pinnedAgentIds.compactMap { byID[$0] }
    let sections = organization.sections.map { section in
        let members = section.agentIds.compactMap { byID[$0] }.filter { !pinnedIDs.contains($0.profile.id) }
        return (section, members)
    }
    let unassigned = agents.filter { !pinnedIDs.contains($0.profile.id) && !grouped.contains($0.profile.id) }
    return ProjectedSidebar(pinned: pinned, sections: sections, unassignedAgents: unassigned)
}

func mergedRows(agents: [AgentView], works: [WorkListItem]) -> [(agent: AgentView?, work: WorkListItem?, at: Int64)] {
    var rows: [(AgentView?, WorkListItem?, Int64)] = []
    for agent in agents { rows.append((agent, nil, agent.runtime.lastActivityAt)) }
    for work in works { rows.append((nil, work, work.lastActivityAt)) }
    return rows.sorted { lhs, rhs in
        if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
        let left = lhs.0?.profile.id ?? lhs.1?.profile.id ?? ""
        let right = rhs.0?.profile.id ?? rhs.1?.profile.id ?? ""
        return left < right
    }
}

func workMembers(workID: String, agents: [AgentView]) -> [AgentView] {
    agents.filter { agent in
        agent.roomMemberships[workID]?.binding != nil
            || agent.settings.workMembership?.binding?.workId == workID
    }
    .sorted { lhs, rhs in
        let left = lhs.settings.workMembership?.binding?.joinedAt ?? lhs.roomMemberships[workID]?.binding?.joinedAt ?? 0
        let right = rhs.settings.workMembership?.binding?.joinedAt ?? rhs.roomMemberships[workID]?.binding?.joinedAt ?? 0
        if left != right { return left < right }
        return lhs.profile.id < rhs.profile.id
    }
}

func workInitial(_ name: String) -> String {
    guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "?" }
    return String(first).uppercased()
}
