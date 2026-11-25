import Foundation

/// UI preferences in the `nuum-ui` suite. Sidebar width and edited identities only.
/// This store does not touch the app data directory.
@MainActor
final class ShellPreferenceStore {
    static let standardSuite = "nuum-ui"
    static let expandedWidthKey = "expandedWidth"
    static let collapsedKey = "isCollapsed"
    static let identityEditedKey = "nuum-identity-edited"

    let suiteName: String
    private let defaults: UserDefaults?
    private var memoryLayout: SidebarLayoutState?
    private var memoryEdited: Set<String> = []

    init(suiteName: String = ShellPreferenceStore.standardSuite) {
        self.suiteName = suiteName
        defaults = UserDefaults(suiteName: suiteName)
    }

    func readLayout() -> SidebarLayoutState {
        guard let defaults else { return memoryLayout ?? SidebarLayoutState() }
        let raw: Double?
        if defaults.object(forKey: Self.expandedWidthKey) == nil {
            raw = nil
        } else {
            raw = defaults.double(forKey: Self.expandedWidthKey)
        }
        let expanded = raw.map(storedExpandedWidth) ?? SandMetric.sidebarDefault
        return SidebarLayoutState(expandedWidth: expanded, isCollapsed: defaults.bool(forKey: Self.collapsedKey))
    }

    func writeLayout(_ layout: SidebarLayoutState) {
        let expanded = storedExpandedWidth(layout.expandedWidth)
        let settled = SidebarLayoutState(expandedWidth: expanded, isCollapsed: layout.isCollapsed)
        guard let defaults else {
            memoryLayout = settled
            return
        }
        defaults.set(Int(expanded.rounded()), forKey: Self.expandedWidthKey)
        defaults.set(layout.isCollapsed, forKey: Self.collapsedKey)
    }

    func hasEditedIdentity(_ agentID: String) -> Bool {
        edited().contains(agentID)
    }

    func markIdentityEdited(_ agentID: String) {
        guard !agentID.isEmpty else { return }
        var ids = edited()
        ids.insert(agentID)
        if let defaults {
            defaults.set(ids.sorted(), forKey: Self.identityEditedKey)
        } else {
            memoryEdited = ids
        }
    }

    private func edited() -> Set<String> {
        guard let defaults else { return memoryEdited }
        return Set(defaults.stringArray(forKey: Self.identityEditedKey) ?? [])
    }
}
