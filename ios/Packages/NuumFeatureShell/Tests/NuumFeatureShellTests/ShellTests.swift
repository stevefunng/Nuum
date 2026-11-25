import Foundation
import Testing
import NuumContracts
@testable import NuumFeatureShell

@Test @MainActor func emptySidebarShowsTheEmptyCopy() async {
    let fake = FakeShellPorts()
    let session = makeSession(fake: fake)
    #expect(session.sidebarSnapshot().placeholder == .loading)
    await session.refresh()
    #expect(session.sidebarSnapshot().placeholder == .noAgents)
    #expect(session.copy.text("No agents yet") == "No Nunu yet")
    #expect(session.phase == .sidebar)
}

@Test @MainActor func pinMovesTheAgentIntoThePinnedSection() async {
    let fake = FakeShellPorts(agents: [shellAgent(id: "a", name: "Ada")])
    let session = makeSession(fake: fake)
    await session.refresh()
    session.openAgentMenu("a", x: 0, y: 0)
    await session.perform(.pin)
    #expect(fake.state.settings.sidebar?.pinnedAgentIds == ["a"])
    #expect(session.sidebarSnapshot().pinned.map(\.id) == ["a"])
    #expect(session.sidebarSnapshot().pinned.first?.name == "Ada")
}

@Test @MainActor func duplicateGroupNameShowsTheProtocolSentence() async {
    let fake = FakeShellPorts(
        agents: [shellAgent(id: "a", name: "Ada")],
        sidebar: SidebarOrganization(sections: [
            SidebarSection(id: "g1", name: "Design", agentIds: ["a"]),
            SidebarSection(id: "g2", name: "Research", agentIds: []),
        ])
    )
    let session = makeSession(fake: fake)
    await session.refresh()
    session.openRename(sectionID: "g2", name: "Research")
    await session.saveGroup(name: "Design")
    #expect(session.groupDialog?.error?.key == "Sidebar groups, memberships and pins must be unique")
    #expect(session.notice == nil)
    #expect(fake.state.sidebarSets == 0)
    #expect(fake.state.settings.sidebar?.sections.map(\.name) == ["Design", "Research"])
}

@Test @MainActor func createSubmitsTheChosenColorAndOneRolledAppearance() async {
    let roller = AnyAppearanceRoller(SystemRandomNumberGenerator())
    let fake = FakeShellPorts()
    let session = makeSession(fake: fake, roller: roller)
    await session.refresh()
    let rolls = roller.appearanceRolls
    session.openCreate(reducedMotion: false)
    #expect(roller.appearanceRolls == rolls + 1)
    #expect(roller.packageRolls == 1)
    let draft = session.createDraft
    let other = avatarPalette().map(\.id).first { $0 != draft?.color } ?? "honey"
    let started = session.unbox.startedAt
    session.selectCreateColor(other)
    #expect(roller.appearanceRolls == rolls + 1)
    #expect(session.createDraft?.shape == draft?.shape)
    #expect(session.createDraft?.material == draft?.material)
    #expect(session.unbox.startedAt == started)
    #expect(session.unbox.clockRegistrations == 1)
    await session.submitCreate(name: "  Milo  ")
    #expect(roller.appearanceRolls == rolls + 1)
    let params = fake.state.created
    #expect(params.count == 1)
    #expect(params[0].name == "Milo")
    #expect(params[0].description == "")
    #expect(params[0].avatarColor == other)
    #expect(params[0].avatarShape == draft?.shape)
    #expect(params[0].avatarMaterial == draft?.material)
    #expect(params[0].tags == nil)
    #expect(params[0].model == nil)
    #expect(params[0].workspace == nil)
    #expect(session.selectedAgentID == "created-1")
    #expect(session.createOpen == false)
}

@Test @MainActor func reducedMotionSkipsTheUnboxClock() async {
    let session = makeSession(fake: FakeShellPorts())
    session.openCreate(reducedMotion: true)
    let later = Date().addingTimeInterval(10)
    let playback = session.unbox.playback(at: later)
    #expect(session.unbox.clockRegistrations == 0)
    #expect(session.unbox.reducedMotion)
    #expect(playback.registersClock == false)
    #expect(playback.settled)
    #expect(playback.showsPackaging == false)
    #expect(playback.packagingOpacity == 0)
    #expect(playback.avatarScale == 1)
    #expect(session.unbox.armed)
}

@Test func duplicateTrimmedGroupNameUsesTheProtocolSentence() throws {
    let draft = SidebarDraft(sections: [
        SidebarSectionDraft(id: "g1", name: "Design", agentIds: [], isCollapsed: false),
        SidebarSectionDraft(id: "g2", name: "  Design  ", agentIds: [], isCollapsed: false),
    ])
    var caught: SidebarSaveError?
    do {
        _ = try prepareSidebarSave(draft)
    } catch let error as SidebarSaveError {
        caught = error
    }
    #expect(caught == .sentence("Sidebar groups, memberships and pins must be unique"))
}

@Test func sidebarPinAssignAndReorder() {
    let empty = SidebarOrganization()
    let pinned = toggleSidebarPin(empty, id: "a")
    #expect(pinned.pinnedAgentIds == ["a"])
    #expect(toggleSidebarPin(pinned, id: "a").pinnedAgentIds.isEmpty)
    let grouped = assignSidebarAgent(
        SidebarOrganization(sections: [SidebarSection(id: "design", name: "Design", agentIds: [])]),
        id: "a",
        sectionID: "design"
    )
    #expect(grouped.sections[0].agentIds == ["a"])
    #expect(grouped.pinnedAgentIds.isEmpty)
    let reordered = reorderSidebarPin(SidebarOrganization(pinnedAgentIds: ["a", "b", "c"]), id: "c", beforeID: "a")
    #expect(reordered.pinnedAgentIds == ["c", "a", "b"])
}

@Test func sidebarLayoutUsesTheRailWhenTheWindowCapIsBelowTheMinimum() {
    let narrow = resolvedSidebarWidth(savedExpanded: 300, isCollapsed: false, windowWidth: 400)
    #expect(narrow.width == 88)
    #expect(narrow.collapsed)
    #expect(narrow.retainedExpanded == 300)
    let wide = resolvedSidebarWidth(savedExpanded: 300, isCollapsed: false, windowWidth: 1200)
    #expect(wide.width == 300)
    #expect(wide.collapsed == false)
    let collapsed = settleSidebarLayout(liveWidth: 180, previousExpanded: 280, windowWidth: 1200)
    #expect(collapsed.isCollapsed)
    #expect(collapsed.expandedWidth == 280)
    let expanded = settleSidebarLayout(liveWidth: 250, previousExpanded: 280, windowWidth: 1200)
    #expect(expanded.isCollapsed == false)
    #expect(expanded.expandedWidth == 250)
    let phone = displaySidebarWidth(
        compact: true,
        windowWidth: 390,
        layout: SidebarLayoutState(expandedWidth: 236, isCollapsed: true),
        liveWidth: nil
    )
    #expect(phone.width == 390)
    #expect(phone.collapsed == false)
}

@Test func columnsFollowTheSizeClass() {
    #expect(shellColumns(compact: true, showsContent: false) == .sidebar)
    #expect(shellColumns(compact: true, showsContent: true) == .content)
    #expect(shellColumns(compact: false, showsContent: false) == .split)
    #expect(shellColumns(compact: false, showsContent: true) == .split)
}

@Test func unboxEaseEndsOnTheSettledPose() {
    #expect(easeOutStrong(0) == 0)
    #expect(easeOutStrong(1) == 1)
    #expect(easeOutStrong(0.5) > 0.5)
    let start = sampleUnbox(reducedMotion: false, elapsedMillis: 0, package: .softTray)
    #expect(start.registersClock)
    #expect(start.showsPackaging)
    #expect(start.avatarScale == 0.92)
    let end = sampleUnbox(reducedMotion: false, elapsedMillis: 1500, package: .roundBox)
    #expect(end.settled)
    #expect(end.packagingOpacity == 0)
    #expect(end.avatarScale == 1)
    #expect(end.showsPackaging == false)
    let reduced = sampleUnbox(reducedMotion: true, elapsedMillis: 0, package: .paperFold)
    #expect(reduced.registersClock == false)
    #expect(reduced.showsPackaging == false)
}

@Test func themeFollowsTheSettingAndEightDigitAlpha() {
    #expect(SandTheme.resolve(preference: nil, systemIsDark: false).scheme == .dark)
    #expect(SandTheme.resolve(preference: .system, systemIsDark: false).scheme == .light)
    #expect(SandTheme.resolve(preference: .light, systemIsDark: true).scheme == .light)
    #expect(SandTheme.dark.color(.bgChrome) == SandColor(css: "#111111"))
    #expect(SandTheme.light.color(.bgChrome) == SandColor(css: "#f7f7f7"))
    #expect(abs(SandTheme.light.color(.textSecondary).alpha - (Double(0x99) / 255)) < 0.0001)
}

@Test func avatarPathsCloseAndGlassPigmentLightens() {
    for shape in ["blob", "circle", "droplet", "cloud", "tablet"] {
        let verbs = parseSVGPath(NunuPaths.data(for: shape))
        #expect(verbs.contains(.close))
        #expect(verbs.contains { if case .curve = $0 { return true } else { return false } })
    }
    #expect(glassPigment(valueHex: "#f3e8d4") == SandColor(red: 1, green: 1, blue: 1, alpha: 1))
    let tinted = glassPigment(valueHex: "#000000")
    #expect(tinted.red > 0.5)
}

@Test func agentMenuMatchesTheMacOrder() {
    let plain = agentMenuEntries(pinned: false, hasGroups: false).map(\.kind)
    #expect(plain == [.pin, .moveToNewGroup, .editProfile, .copyID])
    #expect(agentMenuEntries(pinned: true, hasGroups: true)[0].kind == .unpin)
    #expect(agentMenuEntries(pinned: false, hasGroups: true)[1].kind == .moveToGroup)
    #expect(agentMenuEntries(pinned: false, hasGroups: false)[2].separatorBefore)
    let submenu = groupSubmenuEntries([("design", "Design")]).map(\.kind)
    #expect(submenu == [.back, .group("design"), .unassigned, .newGroup])
    #expect(sectionMenuEntries(index: 0, count: 2, saving: false)[1].enabled == false)
    #expect(sectionMenuEntries(index: 1, count: 2, saving: true).last?.enabled == false)
    #expect(newMenuEntries().map(\.kind) == [.createNunu, .createWork])
}

@Test @MainActor func hiddenAgentsStayOutAndSearchRejectsEmptyGroups() async {
    let fake = FakeShellPorts(
        agents: [
            shellAgent(id: "a", name: "Ada", description: "design"),
            shellAgent(id: "b", name: "Bea", hidden: true),
        ],
        sidebar: SidebarOrganization(sections: [
            SidebarSection(id: "g", name: "Design", agentIds: [], isCollapsed: true),
        ])
    )
    let session = makeSession(fake: fake)
    await session.refresh()
    let snapshot = session.sidebarSnapshot()
    let names = snapshot.unassigned.compactMap { entry -> String? in
        if case .agent(let row) = entry { return row.name }
        return nil
    }
    #expect(names == ["Ada"])
    #expect(snapshot.sections.count == 1)
    #expect(snapshot.sections[0].collapsed)
    session.setQuery("missing")
    #expect(session.sidebarSnapshot().placeholder == .noMatch)
    #expect(session.sidebarSnapshot().sections.isEmpty)
}

@Test @MainActor func backClearsSelectionWithoutDeletingTheAgent() async {
    let fake = FakeShellPorts(agents: [shellAgent(id: "a", name: "Ada")])
    let session = makeSession(fake: fake)
    await session.refresh()
    session.selectAgent("a")
    #expect(session.phase == .content)
    session.back()
    #expect(session.selectedAgentID == nil)
    #expect(session.phase == .sidebar)
    #expect(session.agents.count == 1)
    session.setCompact(false)
    session.selectAgent("a")
    #expect(session.phase == .split)
    session.setCompact(true)
    #expect(session.phase == .content)
}

@Test @MainActor func identitySaveSkipsAvatarAndExecutionUsesTheAgentPort() async {
    let fake = FakeShellPorts(agents: [shellAgent(id: "a", name: "Ada")])
    let session = makeSession(fake: fake)
    await session.refresh()
    await session.saveIdentity(id: "a", name: "  ", tagsRaw: "", description: "x")
    #expect(session.identityError?.key == "Name cannot be empty.")
    #expect(fake.state.updates.isEmpty)
    await session.saveIdentity(id: "a", name: "Ada Lovelace", tagsRaw: "Research, Research, sources", description: "Reads")
    let update = fake.state.updates.last
    #expect(update?.name == "Ada Lovelace")
    #expect(update?.tags == ["Research", "sources"])
    #expect(update?.description == "Reads")
    #expect(update?.avatarColor == nil)
    #expect(update?.avatarShape == nil)
    #expect(update?.avatarMaterial == nil)
    #expect(session.showsTemplates("a") == false)
    await session.setCommands(agentID: "a", commands: .never)
    #expect(fake.state.updates.last?.execution?.commands == .never)
    #expect(fake.state.sidebarSets == 0)
    session.greet("a")
    #expect(session.greetCounts["a"] == 1)
    #expect(fake.state.sends == 0)
}

@Test @MainActor func copyFailureShowsUnderTheList() async {
    let clipboard = RecordingClipboard()
    clipboard.ok = false
    let session = makeSession(fake: FakeShellPorts(agents: [shellAgent(id: "a", name: "Ada")]), clipboard: clipboard)
    await session.refresh()
    session.copyAgentID("a")
    #expect(session.notice?.key == "Could not copy Agent ID.")
    #expect(clipboard.copied == "a")
}

@Test @MainActor func droppingOnAWorkAttachesTheMember() async {
    let fake = FakeShellPorts(agents: [shellAgent(id: "a", name: "Ada")])
    let session = makeSession(fake: fake)
    await session.refresh()
    await session.drop("a", on: .work("room-1"))
    #expect(fake.state.attaches.count == 1)
    #expect(fake.state.attaches[0].workId == "room-1")
    #expect(fake.state.attaches[0].agentId == "a")
    #expect(fake.state.sidebarSets == 0)
    await session.drop("a", on: .cancel)
    #expect(fake.state.sidebarSets == 0)
}

@Test @MainActor func preferencesRoundTripInTheUISuite() {
    let suite = "nuum-ui-test-\(UUID().uuidString)"
    let store = ShellPreferenceStore(suiteName: suite)
    #expect(ShellPreferenceStore.standardSuite == "nuum-ui")
    store.writeLayout(SidebarLayoutState(expandedWidth: 280, isCollapsed: true))
    let read = ShellPreferenceStore(suiteName: suite).readLayout()
    #expect(read.expandedWidth == 280)
    #expect(read.isCollapsed)
    #expect(store.hasEditedIdentity("a") == false)
    store.markIdentityEdited("a")
    #expect(ShellPreferenceStore(suiteName: suite).hasEditedIdentity("a"))
}

@Test func shellSourcesDoNotTouchTheAppDataDirectoryOrForeignPackages() throws {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let sources = tests.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/NuumFeatureShell")
    let forbidden = [
        "Application Support",
        "FileManager",
        "secrets.bin",
        "WidgetKit",
        "URLSession",
        "import NuumStorage",
        "import NuumAgent",
        "import NuumKernel",
        "import NuumModel",
        "import NuumSecurity",
        "Firebase",
        "Datadog",
        "Sentry",
    ]
    let files = try FileManager.default.subpathsOfDirectory(atPath: sources.path)
    #expect(!files.isEmpty)
    for name in files where name.hasSuffix(".swift") {
        let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
        for needle in forbidden {
            #expect(!text.contains(needle), "\(name) contains \(needle)")
        }
    }
}

@Test func relativeTimeBucketsMatchTheSidebarKeys() {
    let now: Int64 = 10_000_000
    #expect(relativeTime(nowMillis: now, atMillis: now - 10_000).key == "now")
    #expect(relativeTime(nowMillis: now, atMillis: now - 120_000).key == "{count}m")
    #expect(relativeTime(nowMillis: now, atMillis: now - 3_600_000).key == "{count}h")
    #expect(relativeTime(nowMillis: now, atMillis: now - 86_400_000).key == "{count}d")
    #expect(newMenuWidth(sidebarWidth: 236) == 212)
    #expect(applying(identityTemplates[0], copy: ShellCopy(language: .en)).name == "Researcher")
    #expect(applying(identityTemplates[0], copy: ShellCopy(language: .en)).tags == "Research, sources")
}
