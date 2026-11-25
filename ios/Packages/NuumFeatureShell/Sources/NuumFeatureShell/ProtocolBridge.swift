import Foundation
import NuumProtocol

struct SidebarSectionDraft: Equatable, Sendable {
    var id: String
    var name: String
    var agentIds: [String]
    var isCollapsed: Bool
}

struct SidebarDraft: Equatable, Sendable {
    var pinnedAgentIds: [String]
    var sections: [SidebarSectionDraft]

    init(pinnedAgentIds: [String] = [], sections: [SidebarSectionDraft] = []) {
        self.pinnedAgentIds = pinnedAgentIds
        self.sections = sections
    }
}

struct RolledAppearance: Equatable, Sendable {
    var color: String
    var shape: String
    var material: String
}

struct ResolvedPigment: Equatable, Sendable {
    var id: String
    var value: String
    var dark: String
    var chat: String
}

enum SidebarSaveError: Error, Equatable {
    case sentence(String)
}

func prepareSidebarSave(_ draft: SidebarDraft) throws -> SidebarDraft {
    let proto = SidebarOrganization(
        pinnedAgentIds: draft.pinnedAgentIds,
        sections: draft.sections.map {
            SidebarSection(id: $0.id, name: $0.name, agentIds: $0.agentIds, isCollapsed: $0.isCollapsed)
        }
    )
    let validated: SidebarOrganization
    do {
        validated = try validateSidebar(proto)
    } catch let error as ProtocolParseException {
        throw SidebarSaveError.sentence(protocolIssueText(error))
    }
    let names = validated.sections.map(\.name)
    if Set(names).count != names.count {
        throw SidebarSaveError.sentence(sidebarUniquenessMessage)
    }
    return SidebarDraft(
        pinnedAgentIds: validated.pinnedAgentIds,
        sections: validated.sections.map {
            SidebarSectionDraft(
                id: $0.id,
                name: $0.name,
                agentIds: $0.agentIds,
                isCollapsed: $0.isCollapsed ?? false
            )
        }
    )
}

func normalizedIdentityTags(_ raw: [String]) throws -> [String] {
    do {
        return try normalizeAgentTags(raw)
    } catch let error as ProtocolParseException {
        throw SidebarSaveError.sentence(protocolIssueText(error))
    }
}

func protocolIssueText(_ error: ProtocolParseException) -> String {
    let text = error.issues.map(\.message).joined(separator: "\n")
    if text.isEmpty { return error.message }
    return text
}

func rollAppearance<R: RandomNumberGenerator>(using random: inout R) -> RolledAppearance {
    let roll = rollAgentAvatar(using: &random)
    return RolledAppearance(color: roll.color, shape: roll.shape, material: roll.material)
}

func avatarPalette() -> [ResolvedPigment] {
    agentAvatarColors.map {
        ResolvedPigment(id: $0.id, value: $0.value, dark: $0.dark, chat: $0.chat)
    }
}

func resolvedPigment(agentId: String, requested: String?) -> ResolvedPigment {
    let color = resolveAgentAvatarColor(agentId: agentId, requested: requested)
    return ResolvedPigment(id: color.id, value: color.value, dark: color.dark, chat: color.chat)
}

func resolvedShape(agentId: String, requested: String?) -> String {
    resolveAgentAvatarShape(agentId: agentId, requested: requested)
}

func resolvedMaterial(requested: String?) -> String {
    resolveAgentAvatarMaterial(requested: requested)
}

func colorLabelKey(_ id: String) -> String {
    switch id {
    case "cream": "Cream"
    case "green": "Sage"
    case "orange": "Peach"
    case "violet": "Lilac"
    case "blue": "Mist blue"
    case "magenta": "Rose"
    case "honey": "Honey"
    case "black": "black"
    default: id
    }
}
