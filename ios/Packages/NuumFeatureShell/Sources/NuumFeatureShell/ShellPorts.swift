import NuumContracts

public struct ShellPorts: Sendable {
    public var agents: any AgentPort
    public var settings: any SettingsPort
    public var desktop: any DesktopPort
    public var work: any WorkPort

    public init(agents: any AgentPort, settings: any SettingsPort, desktop: any DesktopPort, work: any WorkPort) {
        self.agents = agents
        self.settings = settings
        self.desktop = desktop
        self.work = work
    }
}

public struct ShellSelection {
    public var agentID: String?
    public var workID: String?
    public var showSettings: Bool
    public var createWork: Bool
    public var dismissOverlay: @MainActor () -> Void
    public var openProfile: @MainActor (String) -> Void

    public init(
        agentID: String?,
        workID: String?,
        showSettings: Bool,
        createWork: Bool,
        dismissOverlay: @escaping @MainActor () -> Void,
        openProfile: @escaping @MainActor (String) -> Void
    ) {
        self.agentID = agentID
        self.workID = workID
        self.showSettings = showSettings
        self.createWork = createWork
        self.dismissOverlay = dismissOverlay
        self.openProfile = openProfile
    }
}

protocol AgentIDClipboard: Sendable {
    func copy(_ text: String) -> Bool
}

struct AcceptingClipboard: AgentIDClipboard {
    func copy(_ text: String) -> Bool { true }
}

enum ShellMenu: Equatable {
    case new
    case agent(id: String, groups: Bool)
    case section(id: String)
}

struct GroupDialogState: Equatable {
    var sectionID: String?
    var agentID: String?
    var titleKey: String
    var initialName: String
    var error: CopyLine?
}

struct CreateDraft: Equatable {
    var name: String
    var color: String
    var shape: String
    var material: String
    var package: UnboxingPackage
}

enum DropTarget: Equatable, Sendable {
    case pinnedRow(String)
    case pinBand
    case section(String)
    case unassigned
    case work(String)
    case cancel
}
