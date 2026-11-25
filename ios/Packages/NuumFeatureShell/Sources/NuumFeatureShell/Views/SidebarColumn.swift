#if canImport(SwiftUI)
import SwiftUI

struct DropZone: Equatable {
    var target: DropTarget
    var frame: CGRect
}

struct DropZonesKey: PreferenceKey {
    static var defaultValue: [DropZone] = []
    static func reduce(value: inout [DropZone], nextValue: () -> [DropZone]) {
        value.append(contentsOf: nextValue())
    }
}

struct SidebarColumn: View {
    var session: ShellSession
    @Environment(\.sandTheme) private var theme
    @Environment(\.shellCopy) private var copy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zones: [DropZone] = []
    @AccessibilityFocusState private var focusedID: String?

    var body: some View {
        let snapshot = session.sidebarSnapshot()
        let rail = snapshot.collapsedRail
        VStack(spacing: 0) {
            if !rail {
                topBar
                if snapshot.showSearchField { searchField }
            }
            if snapshot.showPinBand { pinBand }
            list(snapshot)
            if let notice = snapshot.notice {
                Text(copy.text(notice))
                    .font(sandFont(SandMetric.fontXS))
                    .foregroundStyle(theme.color(.textDanger).color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SandMetric.spacing3)
                    .padding(.bottom, SandMetric.spacing2)
            }
            bottomBar(rail: rail)
        }
        .background(theme.color(.bgChrome).color)
        .coordinateSpace(.named("sidebar"))
        .onPreferenceChange(DropZonesKey.self) { zones = $0 }
        .overlay(alignment: .topLeading) { menuOverlay }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.text("Agents"))
    }

    private var topBar: some View {
        HStack(spacing: SandMetric.spacing2) {
            Spacer(minLength: 0)
            IconButton(systemName: "magnifyingglass", label: copy.text("Search")) {
                session.toggleSearch()
            }
            .accessibilityHint(copy.text("Search"))
            IconButton(systemName: "plus", label: copy.text("New")) {
                session.openNewMenu(x: session.sidebarWidth.width - 28, y: SandMetric.spacing14)
            }
            .accessibilityHint(copy.text("New agent"))
        }
        .padding(.horizontal, SandMetric.spacing2)
        .frame(height: SandMetric.spacing14)
    }

    private var searchField: some View {
        HStack(spacing: SandMetric.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(sandFont(16))
                .foregroundStyle(theme.color(.textTertiary).color)
            TextField(copy.text("Search"), text: Binding(
                get: { session.query },
                set: { session.setQuery($0) }
            ))
            .font(sandFont(SandMetric.fontBase))
            .foregroundStyle(theme.color(.textPrimary).color)
            .textFieldStyle(.plain)
            .accessibilityLabel(copy.text("Search"))
        }
        .padding(.horizontal, SandMetric.spacing3)
        .padding(.vertical, SandMetric.spacing2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.color(.borderSubtle).color).frame(height: 1)
        }
    }

    private var pinBand: some View {
        Text(copy.text(ShellPhrase.pinBand))
            .font(sandFont(SandMetric.fontXS))
            .foregroundStyle(theme.color(.textSecondary).color)
            .frame(maxWidth: .infinity, minHeight: SandMetric.spacing11)
            .background(theme.color(.fillSecondary).color)
            .clipShape(RoundedRectangle(cornerRadius: SandMetric.radiusLG))
            .padding(.horizontal, SandMetric.spacing3)
            .padding(.bottom, SandMetric.spacing2)
            .dropZone(.pinBand)
    }

    private func list(_ snapshot: SidebarSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if snapshot.placeholder == .loading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: SandMetric.radiusLG)
                            .fill(theme.color(.fillSecondary).color)
                            .frame(height: SandMetric.spacing14)
                            .padding(.horizontal, SandMetric.spacing3)
                            .padding(.vertical, 4)
                    }
                } else if let placeholder = snapshot.placeholder {
                    Text(copy.text(placeholder == .noAgents ? ShellPhrase.noAgents : ShellPhrase.noMatch))
                        .font(sandFont(SandMetric.fontXS))
                        .foregroundStyle(theme.color(.textTertiary).color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SandMetric.spacing3)
                }
                if !snapshot.pinned.isEmpty {
                    sectionLabel(copy.text(ShellPhrase.pinned))
                        .accessibilityLabel(copy.text(ShellPhrase.pinned))
                    ForEach(snapshot.pinned) { row in
                        agentRow(row, avatar: SandMetric.avatarPinned)
                            .dropZone(.pinnedRow(row.id))
                    }
                }
                ForEach(snapshot.sections) { section in
                    sectionHeader(section)
                    if section.showEmptyHint {
                        Text(copy.text(ShellPhrase.dragHere))
                            .font(sandFont(SandMetric.fontXS))
                            .foregroundStyle(theme.color(.textTertiary).color)
                            .padding(.horizontal, SandMetric.spacing3)
                            .padding(.vertical, SandMetric.spacing2)
                    }
                    ForEach(section.agents) { row in
                        agentRow(row, avatar: SandMetric.avatar)
                            .dropZone(.section(section.id))
                    }
                    Color.clear.frame(height: 1).dropZone(.section(section.id))
                }
                if snapshot.showUnassignedLabel {
                    sectionLabel("\(copy.text("Unassigned")) \(snapshot.unassigned.count)")
                        .accessibilityLabel(copy.text("Unassigned"))
                }
                if snapshot.collapsedRail {
                    ForEach(snapshot.railRows) { entry in
                        railEntry(entry)
                    }
                } else {
                    ForEach(snapshot.unassigned) { entry in
                        listEntry(entry)
                            .dropZone(.unassigned)
                    }
                    Color.clear.frame(height: 24).dropZone(.unassigned)
                }
            }
            .padding(.bottom, SandMetric.spacing3)
        }
        .accessibilityLabel(copy.text("Agent list"))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(sandFont(SandMetric.fontXS))
            .foregroundStyle(theme.color(.textTertiary).color)
            .padding(.horizontal, SandMetric.spacing3)
            .padding(.top, SandMetric.spacing2)
    }

    private func sectionHeader(_ section: SectionModel) -> some View {
        HStack(spacing: SandMetric.spacing2) {
            Image(systemName: "chevron.right")
                .font(sandFont(10, weight: .semibold))
                .rotationEffect(.degrees(section.collapsed ? 0 : 90))
                .frame(width: 10, height: 10)
            Text(section.name)
                .font(sandFont(SandMetric.fontXS, weight: .medium))
                .lineLimit(1)
            Text("\(section.count)")
                .font(sandFont(SandMetric.fontXS))
            Spacer(minLength: 0)
            Button {
                session.openSectionMenu(section.id, x: session.sidebarWidth.width - 24, y: 80)
            } label: {
                Text("···")
                    .font(sandFont(SandMetric.fontBase, weight: .semibold))
                    .frame(width: SandMetric.heightBase, height: SandMetric.heightBase)
                    .frame(width: SandMetric.spacing11, height: SandMetric.spacing11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copy.text("Actions for {name}", ["name": section.name]))
        }
        .foregroundStyle(theme.color(.textSecondary).color)
        .padding(.horizontal, SandMetric.spacing3)
        .contentShape(Rectangle())
        .dropZone(.section(section.id))
        .onTapGesture { Task { await session.toggleSection(section.id) } }
        .animation(reduceMotion ? nil : .easeOut(duration: SandMetric.durationFast), value: section.collapsed)
    }

    private func listEntry(_ entry: SidebarEntry) -> some View {
        switch entry {
        case .agent(let row):
            agentRow(row, avatar: SandMetric.avatar)
        case .work(let row):
            workRow(row, avatar: SandMetric.avatar)
        }
    }

    private func railEntry(_ entry: SidebarEntry) -> some View {
        switch entry {
        case .agent(let row):
            agentRow(row, avatar: SandMetric.avatarRail, names: false)
        case .work(let row):
            workRow(row, avatar: SandMetric.avatarRail, names: false)
        }
    }

    private func agentRow(_ row: AgentRowModel, avatar: Double, names: Bool = true) -> some View {
        HStack(spacing: SandMetric.spacing2) {
            NunuAvatarView(appearance: row.appearance, size: avatar, fullBody: false, running: row.running)
            if names {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(row.name)
                            .font(sandFont(SandMetric.fontBase, weight: .medium))
                            .foregroundStyle(theme.color(.textPrimary).color)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(copy.text(row.time))
                            .font(sandFont(SandMetric.fontXS))
                            .foregroundStyle(theme.color(.textTertiary).color)
                    }
                    Text(copy.text(row.preview))
                        .font(sandFont(SandMetric.fontXS))
                        .foregroundStyle(theme.color(.textSecondary).color)
                        .lineLimit(1)
                    if row.running {
                        Text(copy.text("Working"))
                            .font(sandFont(SandMetric.fontXS))
                            .foregroundStyle(theme.color(.textTertiary).color)
                    }
                }
            }
        }
        .padding(.horizontal, SandMetric.spacing3)
        .padding(.vertical, SandMetric.spacing2)
        .frame(minHeight: SandMetric.spacing14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(row.selected ? theme.color(.fillSelected).color : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { session.selectAgent(row.id) }
        .gesture(holdGesture(id: row.id))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.selected ? .isSelected : [])
        .accessibilityFocused($focusedID, equals: row.id)
        .accessibilityIdentifier("agent-\(row.id)")
    }

    private func workRow(_ row: WorkRowModel, avatar: Double, names: Bool = true) -> some View {
        HStack(spacing: SandMetric.spacing2) {
            WorkMark(initial: row.initial, members: row.members, size: avatar)
            if names {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(row.name)
                            .font(sandFont(SandMetric.fontBase, weight: .medium))
                            .foregroundStyle(theme.color(.textPrimary).color)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(copy.text(row.time))
                            .font(sandFont(SandMetric.fontXS))
                            .foregroundStyle(theme.color(.textTertiary).color)
                    }
                    Text(copy.text(row.preview))
                        .font(sandFont(SandMetric.fontXS))
                        .foregroundStyle(theme.color(.textSecondary).color)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, SandMetric.spacing3)
        .padding(.vertical, SandMetric.spacing2)
        .frame(minHeight: SandMetric.spacing14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(row.selected ? theme.color(.fillSelected).color : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { session.selectWork(row.id) }
        .dropZone(.work(row.id))
        .accessibilityAddTraits(row.selected ? .isSelected : [])
    }

    private func holdGesture(id: String) -> some Gesture {
        LongPressGesture(minimumDuration: SandMetric.holdToDrag)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("sidebar")))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                let moved = hypot(drag.translation.width, drag.translation.height) > 8
                if moved && session.dragAgentID != id {
                    session.beginDrag(id)
                }
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value else { return }
                let moved = hypot(drag.translation.width, drag.translation.height) > 8
                if moved || session.dragAgentID == id {
                    let target = zones.first { $0.frame.contains(drag.location) }?.target ?? .cancel
                    Task { await session.drop(id, on: target) }
                } else {
                    session.openAgentMenu(id, x: drag.location.x, y: drag.location.y)
                }
            }
    }

    private func bottomBar(rail: Bool) -> some View {
        HStack(spacing: SandMetric.spacing2) {
            if rail {
                IconButton(systemName: "plus", label: copy.text("New")) {
                    session.openNewMenu(x: 8, y: session.windowHeight - 80)
                }
                .accessibilityHint(copy.text("New agent"))
            }
            Spacer(minLength: 0)
            IconButton(systemName: "slider.horizontal.3", label: copy.text("Settings")) {
                session.openSettings()
            }
        }
        .padding(.horizontal, SandMetric.spacing2)
        .frame(height: SandMetric.spacing14)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.color(.borderSubtle).color).frame(height: 1)
        }
    }

    @ViewBuilder
    private var menuOverlay: some View {
        if session.menu != nil {
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .onTapGesture { session.closeMenu() }
                MenuPanel(
                    entries: session.currentMenuEntries(),
                    width: session.menu == .new ? newMenuWidth(sidebarWidth: session.sidebarWidth.width) : nil
                ) { kind in
                    Task { await session.perform(kind) }
                }
                .padding(.leading, min(max(0, session.menuAnchorX), max(0, session.sidebarWidth.width - 220)))
                .padding(.top, max(0, session.menuAnchorY))
            }
        }
    }
}

private extension View {
    func dropZone(_ target: DropTarget) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: DropZonesKey.self,
                    value: [DropZone(target: target, frame: geo.frame(in: .named("sidebar")))]
                )
            }
        }
    }
}
#endif
