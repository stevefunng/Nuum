import Foundation
import NuumContracts

/// Settled sidebar width. Drag thresholds stay in the UI.
/// Only the values Mac stores under `nuum.ui.sidebar.v2` are written here.
public struct SidebarLayout: Sendable, Equatable {
    public var expandedWidth: Int
    public var isCollapsed: Bool

    public init(expandedWidth: Int, isCollapsed: Bool) {
        self.expandedWidth = expandedWidth
        self.isCollapsed = isCollapsed
    }
}

public enum SidebarLayoutLimits {
    public static let defaultExpandedWidth = 236
    public static let minExpandedWidth = 220
    public static let maxExpandedWidth = 400
}

/// Mac `localStorage` key `nuum-identity-edited`: agent ids whose identity was saved.
public enum UiPreferenceKeys {
    public static let identityEdited = "nuum-identity-edited"
    public static let expandedWidth = "expandedWidth"
    public static let isCollapsed = "isCollapsed"
}

enum UIPreferenceStore {
    static func readSidebarLayout(suite: String) -> SidebarLayout {
        let defaults = open(suite)
        let raw: Int?
        if defaults.object(forKey: UiPreferenceKeys.expandedWidth) == nil {
            raw = nil
        } else {
            raw = defaults.integer(forKey: UiPreferenceKeys.expandedWidth)
        }
        return SidebarLayout(
            expandedWidth: normalizeSidebarWidth(raw),
            isCollapsed: defaults.bool(forKey: UiPreferenceKeys.isCollapsed)
        )
    }

    static func writeSidebarLayout(suite: String, layout: SidebarLayout) {
        let defaults = open(suite)
        defaults.set(normalizeSidebarWidth(layout.expandedWidth), forKey: UiPreferenceKeys.expandedWidth)
        defaults.set(layout.isCollapsed, forKey: UiPreferenceKeys.isCollapsed)
    }

    static func hasEditedIdentity(suite: String, agentId: String) throws -> Bool {
        try requireAgentID(agentId)
        return edited(open(suite)).contains(agentId)
    }

    static func markIdentityEdited(suite: String, agentId: String) throws {
        try requireAgentID(agentId)
        let defaults = open(suite)
        var ids = edited(defaults)
        ids.insert(agentId)
        defaults.set(ids.sorted(), forKey: UiPreferenceKeys.identityEdited)
    }

    static func storedKeys(suite: String) -> Set<String> {
        Set(open(suite).dictionaryRepresentation().keys)
    }

    private static func open(_ suite: String) -> UserDefaults {
        UserDefaults(suiteName: suite) ?? UserDefaults.standard
    }

    private static func edited(_ defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: UiPreferenceKeys.identityEdited) ?? [])
    }

    private static func requireAgentID(_ agentId: String) throws {
        if agentId.isEmpty {
            throw invalid("Agent id is empty")
        }
    }
}

func normalizeSidebarWidth(_ raw: Int?) -> Int {
    let value = if let raw, raw > 0 { raw } else { SidebarLayoutLimits.defaultExpandedWidth }
    return min(max(value, SidebarLayoutLimits.minExpandedWidth), SidebarLayoutLimits.maxExpandedWidth)
}
