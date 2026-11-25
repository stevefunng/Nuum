import NuumContracts

extension SidebarOrganization {
    var draft: SidebarDraft {
        SidebarDraft(
            pinnedAgentIds: pinnedAgentIds,
            sections: sections.map {
                SidebarSectionDraft(id: $0.id, name: $0.name, agentIds: $0.agentIds, isCollapsed: $0.isCollapsed)
            }
        )
    }
}

extension SidebarDraft {
    var organization: SidebarOrganization {
        SidebarOrganization(
            pinnedAgentIds: pinnedAgentIds,
            sections: sections.map {
                SidebarSection(id: $0.id, name: $0.name, agentIds: $0.agentIds, isCollapsed: $0.isCollapsed)
            }
        )
    }
}
