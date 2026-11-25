import Foundation

struct SidebarLayoutState: Equatable, Sendable {
    var expandedWidth: Double
    var isCollapsed: Bool

    init(expandedWidth: Double = SandMetric.sidebarDefault, isCollapsed: Bool = false) {
        self.expandedWidth = expandedWidth
        self.isCollapsed = isCollapsed
    }
}

struct SidebarWidth: Equatable, Sendable {
    var width: Double
    var collapsed: Bool
    var retainedExpanded: Double
}

func storedExpandedWidth(_ width: Double) -> Double {
    min(max(width, SandMetric.sidebarMin), SandMetric.sidebarMax)
}

/// Regular width. When `min(400, 42% of the window)` is already under 220, the rail is 88 and the saved expanded width stays.
func resolvedSidebarWidth(savedExpanded: Double, isCollapsed: Bool, windowWidth: Double) -> SidebarWidth {
    let retained = storedExpandedWidth(savedExpanded)
    let cap = min(SandMetric.sidebarMax, windowWidth * SandMetric.sidebarFraction)
    if cap < SandMetric.sidebarMin {
        return SidebarWidth(width: SandMetric.sidebarCollapsed, collapsed: true, retainedExpanded: retained)
    }
    let expanded = min(max(retained, SandMetric.sidebarMin), cap)
    if isCollapsed {
        return SidebarWidth(width: SandMetric.sidebarCollapsed, collapsed: true, retainedExpanded: expanded)
    }
    return SidebarWidth(width: expanded, collapsed: false, retainedExpanded: expanded)
}

func settleSidebarLayout(liveWidth: Double, previousExpanded: Double, windowWidth: Double) -> SidebarLayoutState {
    let retained = storedExpandedWidth(previousExpanded)
    let cap = min(SandMetric.sidebarMax, windowWidth * SandMetric.sidebarFraction)
    if liveWidth < SandMetric.sidebarCollapseBelow || cap < SandMetric.sidebarMin {
        return SidebarLayoutState(expandedWidth: retained, isCollapsed: true)
    }
    let expanded = min(max(liveWidth, SandMetric.sidebarMin), cap)
    return SidebarLayoutState(expandedWidth: expanded, isCollapsed: false)
}

func displaySidebarWidth(
    compact: Bool,
    windowWidth: Double,
    layout: SidebarLayoutState,
    liveWidth: Double?
) -> SidebarWidth {
    if compact {
        return SidebarWidth(width: windowWidth, collapsed: false, retainedExpanded: layout.expandedWidth)
    }
    if let liveWidth {
        let cap = min(SandMetric.sidebarMax, max(windowWidth * SandMetric.sidebarFraction, SandMetric.sidebarCollapsed))
        let width = min(max(liveWidth, SandMetric.sidebarCollapsed), max(cap, SandMetric.sidebarCollapsed))
        return SidebarWidth(width: width, collapsed: width < SandMetric.sidebarCollapseBelow, retainedExpanded: layout.expandedWidth)
    }
    return resolvedSidebarWidth(savedExpanded: layout.expandedWidth, isCollapsed: layout.isCollapsed, windowWidth: windowWidth)
}

enum ShellColumnPhase: Equatable, Sendable {
    case sidebar
    case content
    case split
}

func shellColumns(compact: Bool, showsContent: Bool) -> ShellColumnPhase {
    if !compact { return .split }
    return showsContent ? .content : .sidebar
}
