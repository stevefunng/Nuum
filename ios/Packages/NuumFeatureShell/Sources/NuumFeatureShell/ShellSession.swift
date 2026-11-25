import Foundation
import Observation
import NuumContracts

@MainActor
@Observable
final class ShellSession {
    let ports: ShellPorts
    let preferences: ShellPreferenceStore
    let clipboard: any AgentIDClipboard
    let roller: AnyAppearanceRoller
    var makeID: @MainActor () -> String
    var now: @MainActor () -> Int64

    var settings: PublicSettings
    var settingsReady = false
    var agents: [AgentView] = []
    var works: [WorkListItem] = []
    var previews: [String: String] = [:]
    var loaded = false

    var selectedAgentID: String?
    var selectedWorkID: String?
    var showSettings = false
    var createWork = false
    var createOpen = false
    var createDraft: CreateDraft?
    var creating = false
    var createError: CopyLine?
    var profileID: String?
    var identityOpen = false
    var identitySaving = false
    var identityError: CopyLine?
    var workspaceRevoked: Set<String> = []
    var executionSaving = false
    var executionError: CopyLine?
    var greetCounts: [String: Int] = [:]

    var query = ""
    var searchOpen = false
    var busy = false
    var notice: CopyLine?
    var menu: ShellMenu?
    var menuAnchorX = 0.0
    var menuAnchorY = 0.0
    var groupDialog: GroupDialogState?
    var layout: SidebarLayoutState
    var resizing = false
    var liveWidth: Double?
    var dragAgentID: String?
    var compact = true
    var windowWidth = 393.0
    var windowHeight = 852.0
    var systemIsDark = true
    var reduceMotion = false
    var unbox = UnboxModel()

    private var layoutBeforeResize: SidebarLayoutState

    init(
        ports: ShellPorts,
        preferences: ShellPreferenceStore,
        clipboard: any AgentIDClipboard = AcceptingClipboard(),
        roller: AnyAppearanceRoller = AnyAppearanceRoller(SystemRandomNumberGenerator()),
        makeID: @escaping @MainActor () -> String = { UUID().uuidString },
        now: @escaping @MainActor () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.ports = ports
        self.preferences = preferences
        self.clipboard = clipboard
        self.roller = roller
        self.makeID = makeID
        self.now = now
        settings = PublicSettings(
            defaultToolPermission: defaultSettings.defaultToolPermission,
            defaultModel: defaultSettings.defaultModel,
            theme: defaultSettings.theme,
            hasOpenaiKey: false,
            hasAnthropicKey: false,
            hasDeepseekKey: false,
            language: defaultSettings.language,
            sidebar: nil
        )
        let stored = preferences.readLayout()
        layout = stored
        layoutBeforeResize = stored
    }

    var organization: SidebarOrganization {
        settings.sidebar ?? SidebarOrganization()
    }

    var copy: ShellCopy {
        ShellCopy(language: settingsReady ? settings.language : .zhCN)
    }

    var theme: SandTheme {
        SandTheme.resolve(preference: settingsReady ? settings.theme : nil, systemIsDark: systemIsDark)
    }

    var showsContentColumn: Bool {
        if !compact { return true }
        return createOpen || profileID != nil || showSettings || createWork || selectedAgentID != nil || selectedWorkID != nil
    }

    var showsConversationSlot: Bool {
        if compact && createOpen { return false }
        if compact {
            return selectedAgentID != nil || selectedWorkID != nil || showSettings || createWork || profileID != nil
        }
        return true
    }

    var phase: ShellColumnPhase {
        shellColumns(compact: compact, showsContent: showsContentColumn)
    }

    var sidebarWidth: SidebarWidth {
        displaySidebarWidth(compact: compact, windowWidth: windowWidth, layout: layout, liveWidth: resizing ? liveWidth : nil)
    }

    var selection: ShellSelection {
        ShellSelection(
            agentID: selectedAgentID,
            workID: selectedWorkID,
            showSettings: showSettings,
            createWork: createWork,
            dismissOverlay: { [weak self] in self?.dismissOverlay() },
            openProfile: { [weak self] id in self?.openProfile(id) }
        )
    }

    func setCompact(_ compact: Bool) {
        self.compact = compact
    }

    func syncChrome(compact: Bool, width: Double, height: Double, systemIsDark: Bool, reduceMotion: Bool) {
        self.compact = compact
        if width > 0 { windowWidth = width }
        if height > 0 { windowHeight = height }
        self.systemIsDark = systemIsDark
        self.reduceMotion = reduceMotion
    }

    func refresh() async {
        defer { loaded = true }
        do {
            settings = try await ports.settings.get()
            settingsReady = true
            agents = try await ports.agents.list()
            works = try await ports.work.list()
            previews = await loadPreviews(agents)
        } catch {
            notice = hostLine(message(error), fallback: ShellPhrase.sidebarSaveFailed)
        }
    }

    func observe() async {
        let settingsEvents = ports.settings.events
        let agentEvents = ports.agents.events
        let workEvents = ports.work.events
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.pump(settingsEvents) }
            group.addTask { await self.pump(agentEvents) }
            group.addTask { await self.pump(workEvents) }
            await group.waitForAll()
        }
    }

    private func pump(_ events: AsyncStream<HostEvent>) async {
        for await event in events {
            if Task.isCancelled { break }
            await apply(event)
        }
    }

    func apply(_ event: HostEvent) async {
        switch event {
        case .settingsUpdated(let settings):
            self.settings = settings
            settingsReady = true
        case .agentUpdated(let agent):
            replace(agent)
        case .workUpdated, .workEventAppended, .workCatalogUpdated:
            await refreshWorks()
        default:
            break
        }
    }

    func back() {
        if case .new = menu {
            menu = nil
            return
        }
        if menu != nil {
            closeMenu()
            return
        }
        if groupDialog != nil {
            if !busy { closeGroupDialog() }
            return
        }
        if identityOpen {
            if !identitySaving { closeIdentity() }
            return
        }
        if createOpen {
            if !creating { closeCreate() }
            return
        }
        if profileID != nil {
            closeProfile()
            return
        }
        if showSettings || createWork {
            dismissOverlay()
            return
        }
        if resizing {
            cancelResize()
            return
        }
        if dragAgentID != nil {
            cancelDrag()
            return
        }
        selectedAgentID = nil
        selectedWorkID = nil
    }

    func dismissOverlay() {
        showSettings = false
        createWork = false
    }

    func openSettings() {
        showSettings = true
        createWork = false
        menu = nil
    }

    func openCreateWork() {
        createWork = true
        showSettings = false
        menu = nil
    }

    func openCreate(reducedMotion: Bool) {
        let roll = roller.rollAppearance()
        let package = roller.rollPackage()
        createDraft = CreateDraft(name: "", color: roll.color, shape: roll.shape, material: roll.material, package: package)
        createError = nil
        creating = false
        var model = UnboxModel()
        model.begin(reducedMotion: reducedMotion, package: package)
        unbox = model
        createOpen = true
        menu = nil
    }

    func selectCreateColor(_ colorID: String) {
        guard var draft = createDraft, !creating else { return }
        draft.color = colorID
        createDraft = draft
    }

    func submitCreate(name: String) async {
        guard var draft = createDraft, !creating else { return }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SandMetric.nameMax))
        guard !trimmed.isEmpty else { return }
        draft.name = trimmed
        createDraft = draft
        creating = true
        createError = nil
        do {
            let created = try await ports.agents.create(AgentCreateParams(
                name: trimmed,
                description: "",
                avatarColor: draft.color,
                avatarShape: draft.shape,
                avatarMaterial: draft.material
            ))
            replace(created)
            selectAgent(created.profile.id)
            closeCreate()
        } catch {
            createError = hostLine(message(error), fallback: ShellPhrase.identitySaveFailed)
            creating = false
        }
    }

    func closeCreate() {
        createOpen = false
        createError = nil
        creating = false
    }

    func selectAgent(_ id: String) {
        if profileID != id {
            profileID = nil
            identityOpen = false
        }
        selectedAgentID = id
        selectedWorkID = nil
        showSettings = false
        createWork = false
    }

    func selectWork(_ id: String) {
        profileID = nil
        identityOpen = false
        selectedWorkID = id
        selectedAgentID = nil
        showSettings = false
        createWork = false
    }

    func openProfile(_ id: String) {
        selectAgent(id)
        profileID = id
        identityOpen = false
        identityError = nil
        executionError = nil
        closeMenu()
    }

    func closeProfile() {
        profileID = nil
        identityOpen = false
        identityError = nil
    }

    func openIdentity() {
        identityError = nil
        identityOpen = true
    }

    func closeIdentity() {
        identityOpen = false
        identityError = nil
    }

    func showsTemplates(_ agentID: String) -> Bool {
        !preferences.hasEditedIdentity(agentID)
    }

    func saveIdentity(id: String, name: String, tagsRaw: String, description: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            identityError = CopyLine(key: ShellPhrase.nameEmpty)
            return
        }
        identitySaving = true
        identityError = nil
        do {
            let tags = try normalizedIdentityTags(splitTags(tagsRaw))
            let updated = try await ports.agents.update(AgentUpdateParams(
                id: id,
                name: trimmed,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: tags
            ))
            replace(updated)
            preferences.markIdentityEdited(id)
            closeIdentity()
        } catch let error as SidebarSaveError {
            identityError = sentenceLine(error)
        } catch {
            identityError = hostLine(message(error), fallback: ShellPhrase.identitySaveFailed)
        }
        identitySaving = false
    }

    func setCommands(agentID: String, commands: CommandPermission) async {
        guard let agent = agents.first(where: { $0.profile.id == agentID }) else { return }
        let current = agent.settings.execution
        let next = ExecutionPreferences(
            workspaceId: current?.workspaceId ?? agentID,
            commands: commands,
            commandGrants: current?.commandGrants ?? [],
            networkGrants: current?.networkGrants ?? []
        )
        await saveExecution(agentID: agentID, execution: next)
    }

    func revokeCommand(agentID: String, grant: CommandGrant) async {
        guard let current = agents.first(where: { $0.profile.id == agentID })?.settings.execution else { return }
        var next = current
        next.commandGrants = current.commandGrants.filter { $0 != grant }
        await saveExecution(agentID: agentID, execution: next)
    }

    func revokeNetwork(agentID: String, grant: NetworkGrant) async {
        guard let current = agents.first(where: { $0.profile.id == agentID })?.settings.execution else { return }
        var next = current
        next.networkGrants = current.networkGrants.filter { $0 != grant }
        await saveExecution(agentID: agentID, execution: next)
    }

    func openFolder(agentID: String) async {
        guard let agent = agents.first(where: { $0.profile.id == agentID }) else { return }
        executionSaving = true
        executionError = nil
        let revoked = workspaceRevoked.contains(agentID)
        let root = agent.settings.workspace?.projectRoot
        do {
            if revoked || root == nil || root?.isEmpty == true {
                if let picked = try await ports.desktop.pickDirectory() {
                    let updated = try await ports.agents.update(AgentUpdateParams(
                        id: agentID,
                        workspace: WorkspaceSettings(projectRoot: picked, toolPermission: agent.settings.workspace?.toolPermission)
                    ))
                    workspaceRevoked.remove(agentID)
                    replace(updated)
                }
            } else if let root {
                do {
                    try await ports.desktop.openAttachment(path: root)
                } catch let error as NuumError {
                    workspaceRevoked.insert(agentID)
                    executionError = hostLine(error.message, fallback: ShellPhrase.identitySaveFailed)
                }
            }
        } catch {
            executionError = hostLine(message(error), fallback: ShellPhrase.identitySaveFailed)
        }
        executionSaving = false
    }

    func greet(_ id: String) {
        greetCounts[id, default: 0] += 1
    }

    func toggleSearch() {
        searchOpen.toggle()
        if !searchOpen && query.isEmpty { return }
    }

    func setQuery(_ text: String) {
        query = text
        if !text.isEmpty { searchOpen = true }
    }

    func openNewMenu(x: Double, y: Double) {
        menu = .new
        menuAnchorX = x
        menuAnchorY = y
    }

    func openAgentMenu(_ id: String, x: Double, y: Double) {
        menu = .agent(id: id, groups: false)
        menuAnchorX = x
        menuAnchorY = y
    }

    func openSectionMenu(_ id: String, x: Double, y: Double) {
        menu = .section(id: id)
        menuAnchorX = x
        menuAnchorY = y
    }

    func closeMenu() {
        menu = nil
    }

    func showGroupSubmenu() {
        guard case .agent(let id, _) = menu else { return }
        menu = .agent(id: id, groups: true)
    }

    func currentMenuEntries() -> [MenuEntry] {
        switch menu {
        case .new:
            return newMenuEntries()
        case .agent(let id, let groups):
            if groups {
                return groupSubmenuEntries(organization.sections.map { ($0.id, $0.name) })
            }
            return agentMenuEntries(pinned: organization.pinnedAgentIds.contains(id), hasGroups: !organization.sections.isEmpty)
        case .section(let id):
            guard let index = organization.sections.firstIndex(where: { $0.id == id }) else { return [] }
            return sectionMenuEntries(index: index, count: organization.sections.count, saving: busy)
        case nil:
            return []
        }
    }

    func perform(_ kind: MenuKind) async {
        switch menu {
        case .new:
            switch kind {
            case .createNunu:
                openCreate(reducedMotion: reduceMotion)
            case .createWork:
                openCreateWork()
            default:
                break
            }
        case .agent(let id, let groups):
            if groups {
                switch kind {
                case .back:
                    menu = .agent(id: id, groups: false)
                case .group(let sectionID):
                    await commit(assignSidebarAgent(organization, id: id, sectionID: sectionID), fromDialog: false)
                case .unassigned:
                    await commit(assignSidebarAgent(organization, id: id, sectionID: unassignedSection), fromDialog: false)
                case .newGroup:
                    openNewGroup(agentID: id)
                default:
                    break
                }
                return
            }
            switch kind {
            case .pin, .unpin:
                await commit(toggleSidebarPin(organization, id: id), fromDialog: false)
            case .moveToNewGroup:
                openNewGroup(agentID: id)
            case .moveToGroup:
                showGroupSubmenu()
            case .editProfile:
                openProfile(id)
            case .copyID:
                copyAgentID(id)
            default:
                break
            }
        case .section(let id):
            switch kind {
            case .rename:
                if let section = organization.sections.first(where: { $0.id == id }) {
                    openRename(sectionID: id, name: section.name)
                }
            case .moveUp:
                if let index = organization.sections.firstIndex(where: { $0.id == id }) {
                    await commit(moveSidebarSection(organization, index: index, offset: -1), fromDialog: false)
                }
            case .moveDown:
                if let index = organization.sections.firstIndex(where: { $0.id == id }) {
                    await commit(moveSidebarSection(organization, index: index, offset: 1), fromDialog: false)
                }
            case .ungroup:
                await commit(removeSidebarSection(organization, id: id), fromDialog: false)
            default:
                break
            }
        case nil:
            break
        }
    }

    func copyAgentID(_ id: String) {
        if clipboard.copy(id) {
            notice = nil
        } else {
            notice = CopyLine(key: ShellPhrase.copyFailed)
        }
        closeMenu()
    }

    func openNewGroup(agentID: String?) {
        closeMenu()
        notice = nil
        groupDialog = GroupDialogState(sectionID: nil, agentID: agentID, titleKey: "New group", initialName: "", error: nil)
    }

    func openRename(sectionID: String, name: String) {
        closeMenu()
        notice = nil
        groupDialog = GroupDialogState(sectionID: sectionID, agentID: nil, titleKey: "Rename group", initialName: name, error: nil)
    }

    func closeGroupDialog() {
        groupDialog = nil
    }

    func saveGroup(name: String) async {
        guard let dialog = groupDialog, !busy else { return }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SandMetric.nameMax))
        if trimmed.isEmpty { return }
        let next = withGroup(organization, sectionID: dialog.sectionID, agentID: dialog.agentID, name: trimmed, newID: makeID())
        await commit(next, fromDialog: true)
    }

    func toggleSection(_ id: String) async {
        var next = organization
        next.sections = next.sections.map { section in
            guard section.id == id else { return section }
            var copy = section
            copy.isCollapsed.toggle()
            return copy
        }
        await commit(next, fromDialog: false)
    }

    func beginResize() {
        layoutBeforeResize = layout
        resizing = true
        liveWidth = sidebarWidth.width
    }

    func updateResize(_ width: Double) {
        guard resizing else { return }
        liveWidth = width
    }

    func endResize() {
        guard let liveWidth else { return }
        layout = settleSidebarLayout(liveWidth: liveWidth, previousExpanded: layoutBeforeResize.expandedWidth, windowWidth: windowWidth)
        preferences.writeLayout(layout)
        resizing = false
        self.liveWidth = nil
    }

    func cancelResize() {
        layout = layoutBeforeResize
        resizing = false
        liveWidth = nil
    }

    func beginDrag(_ id: String) {
        dragAgentID = id
    }

    func cancelDrag() {
        dragAgentID = nil
    }

    func drop(_ agentID: String, on target: DropTarget) async {
        switch target {
        case .cancel:
            cancelDrag()
        case .work(let workID):
            cancelDrag()
            await moveAgentToWork(agentID: agentID, workID: workID)
        case .pinnedRow(let beforeID):
            await commit(reorderSidebarPin(organization, id: agentID, beforeID: beforeID), fromDialog: false)
            cancelDrag()
        case .pinBand:
            await commit(assignSidebarAgent(organization, id: agentID, sectionID: pinnedSection), fromDialog: false)
            cancelDrag()
        case .section(let sectionID):
            await commit(assignSidebarAgent(organization, id: agentID, sectionID: sectionID), fromDialog: false)
            cancelDrag()
        case .unassigned:
            await commit(assignSidebarAgent(organization, id: agentID, sectionID: unassignedSection), fromDialog: false)
            cancelDrag()
        }
    }

    func sidebarSnapshot() -> SidebarSnapshot {
        let rail = sidebarWidth.collapsed && !compact
        let querying = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let listed = visibleAgents(agents, query: query)
        let listedWorks = visibleWorks(works, query: query)
        let projected = projectSidebar(agents: listed, organization: organization)
        let pinnedRows = projected.pinned.map { agentRow($0, pinned: true) }
        let sections: [SectionModel] = projected.sections.compactMap { item in
            let collapsed = querying ? false : item.section.isCollapsed
            if querying && item.agents.isEmpty { return nil }
            let rows = collapsed ? [] : item.agents.map { agentRow($0, pinned: false) }
            return SectionModel(
                id: item.section.id,
                name: item.section.name,
                count: item.agents.count,
                collapsed: collapsed,
                agents: rows,
                showEmptyHint: !querying && !collapsed && item.agents.isEmpty
            )
        }
        let unassigned = mergedRows(agents: projected.unassignedAgents, works: listedWorks).map(entry)
        let hasGroups = !organization.sections.isEmpty
        let visibleCount = pinnedRows.count + sections.reduce(0) { $0 + $1.agents.count } + unassigned.count
        let placeholder: SidebarPlaceholder?
        if !loaded {
            placeholder = .loading
        } else if querying && visibleCount == 0 {
            placeholder = .noMatch
        } else if !querying && listed.isEmpty && listedWorks.isEmpty && organization.sections.isEmpty && organization.pinnedAgentIds.isEmpty {
            placeholder = .noAgents
        } else {
            placeholder = nil
        }
        var railRows: [SidebarEntry] = []
        if rail {
            railRows = pinnedRows.map { .agent($0) }
            for section in projected.sections {
                railRows += section.agents.map { .agent(agentRow($0, pinned: false)) }
            }
            railRows += unassigned
        }
        return SidebarSnapshot(
            placeholder: placeholder,
            pinned: rail ? [] : pinnedRows,
            sections: rail ? [] : sections,
            showUnassignedLabel: hasGroups && !unassigned.isEmpty && !rail,
            unassigned: rail ? [] : unassigned,
            railRows: railRows,
            collapsedRail: rail,
            showSearchField: (searchOpen || querying) && !rail,
            showPinBand: dragAgentID != nil && !rail,
            notice: notice
        )
    }

    private func entry(_ row: (AgentView?, WorkListItem?, Int64)) -> SidebarEntry {
        if let agent = row.0 { return .agent(agentRow(agent, pinned: false)) }
        return .work(workRow(row.1!))
    }

    private func agentRow(_ agent: AgentView, pinned: Bool) -> AgentRowModel {
        let preview = previews[agent.profile.id].map { CopyLine(key: $0) }
            ?? (agent.profile.description.isEmpty ? CopyLine(key: ShellPhrase.newAgent) : CopyLine(key: agent.profile.description))
        let time = relativeTime(nowMillis: now(), atMillis: agent.runtime.lastActivityAt)
        return AgentRowModel(
            id: agent.profile.id,
            name: agent.profile.name,
            preview: preview,
            time: CopyLine(key: time.key, values: time.count.map { ["count": String($0)] } ?? [:]),
            running: agent.runtime.status == .running,
            selected: selectedAgentID == agent.profile.id,
            pinned: pinned,
            appearance: NunuAppearance.resolve(
                agentID: agent.profile.id,
                color: agent.profile.avatarColor,
                shape: agent.profile.avatarShape,
                material: agent.profile.avatarMaterial
            )
        )
    }

    private func workRow(_ work: WorkListItem) -> WorkRowModel {
        let previewSource = work.preview.flatMap { $0.isEmpty ? nil : $0 } ?? work.profile.description
        let preview = previewSource.isEmpty ? CopyLine(key: ShellPhrase.newWork) : CopyLine(key: previewSource)
        let time = relativeTime(nowMillis: now(), atMillis: work.lastActivityAt)
        let members = workMembers(workID: work.profile.id, agents: agents).prefix(4).map {
            NunuAppearance.resolve(agentID: $0.profile.id, color: $0.profile.avatarColor, shape: $0.profile.avatarShape, material: $0.profile.avatarMaterial)
        }
        return WorkRowModel(
            id: work.profile.id,
            name: work.profile.name,
            preview: preview,
            time: CopyLine(key: time.key, values: time.count.map { ["count": String($0)] } ?? [:]),
            selected: selectedWorkID == work.profile.id,
            initial: workInitial(work.profile.name),
            members: Array(members)
        )
    }

    private func commit(_ next: SidebarOrganization, fromDialog: Bool) async {
        if busy { return }
        if next == organization {
            if fromDialog { closeGroupDialog() } else { closeMenu() }
            return
        }
        let prepared: SidebarOrganization
        do {
            prepared = try prepareSidebarSave(next.draft).organization
        } catch let error as SidebarSaveError {
            present(error, fromDialog: fromDialog)
            return
        } catch {
            present(.sentence(ShellPhrase.sidebarSaveFailed), fromDialog: fromDialog)
            return
        }
        busy = true
        if fromDialog {
            groupDialog?.error = nil
        } else {
            notice = nil
        }
        do {
            settings = try await ports.settings.set(SettingsPatch(sidebar: prepared))
            settingsReady = true
            if fromDialog { closeGroupDialog() } else { closeMenu() }
        } catch let error as SidebarSaveError {
            present(error, fromDialog: fromDialog)
        } catch {
            let line = hostLine(message(error), fallback: ShellPhrase.sidebarSaveFailed)
            if fromDialog {
                groupDialog?.error = line
            } else {
                notice = line
            }
        }
        busy = false
    }

    private func present(_ error: SidebarSaveError, fromDialog: Bool) {
        let line = sentenceLine(error)
        if fromDialog {
            groupDialog?.error = line
        } else {
            notice = line
        }
    }

    private func sentenceLine(_ error: SidebarSaveError) -> CopyLine {
        switch error {
        case .sentence(let sentence):
            return CopyLine(key: sentence)
        }
    }

    private func saveExecution(agentID: String, execution: ExecutionPreferences) async {
        executionSaving = true
        executionError = nil
        do {
            let updated = try await ports.agents.update(AgentUpdateParams(id: agentID, execution: execution))
            replace(updated)
        } catch {
            executionError = hostLine(message(error), fallback: ShellPhrase.identitySaveFailed)
        }
        executionSaving = false
    }

    private func moveAgentToWork(agentID: String, workID: String) async {
        guard let agent = agents.first(where: { $0.profile.id == agentID }) else { return }
        do {
            let membership = agent.settings.workMembership
            if let binding = membership?.binding, binding.workId != workID {
                try await ports.work.moveMember(WorkMemberMoveParams(
                    fromWorkId: binding.workId,
                    toWorkId: workID,
                    agentId: agentID,
                    expectedRevision: membership?.revision ?? 0
                ))
            } else if membership?.binding?.workId != workID {
                try await ports.work.attachMember(WorkMemberAttachParams(
                    workId: workID,
                    agentId: agentID,
                    expectedRevision: membership?.revision ?? 0
                ))
            }
            agents = try await ports.agents.list()
        } catch {
            notice = hostLine(message(error), fallback: ShellPhrase.sidebarSaveFailed)
        }
    }

    private func replace(_ view: AgentView) {
        if let index = agents.firstIndex(where: { $0.profile.id == view.profile.id }) {
            agents[index] = view
        } else {
            agents.append(view)
        }
    }

    private func refreshWorks() async {
        if let listed = try? await ports.work.list() {
            works = listed
        }
    }

    private func loadPreviews(_ listed: [AgentView]) async -> [String: String] {
        var out: [String: String] = [:]
        for agent in listed {
            guard let page = try? await ports.agents.transcript(TranscriptQuery(id: agent.profile.id, limit: 40)) else { continue }
            if let text = page.entries.compactMap(sidebarPreview).last {
                out[agent.profile.id] = text
            }
        }
        return out
    }

    private func hostLine(_ message: String?, fallback: String) -> CopyLine {
        if let message, !message.isEmpty { return CopyLine(key: message) }
        return CopyLine(key: fallback)
    }

    private func message(_ error: any Error) -> String? {
        if let nuum = error as? NuumError { return nuum.message }
        return nil
    }
}
