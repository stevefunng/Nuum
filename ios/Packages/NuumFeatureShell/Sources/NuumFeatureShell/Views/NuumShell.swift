#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct NuumShell<Content: View>: View {
    @State private var session: ShellSession
    private let content: (ShellSelection) -> Content
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(ports: ShellPorts, @ViewBuilder content: @escaping (ShellSelection) -> Content) {
        _session = State(initialValue: ShellSession(
            ports: ports,
            preferences: ShellPreferenceStore(),
            clipboard: SystemClipboard()
        ))
        self.content = content
    }

    public var body: some View {
        let token = ChromeToken(
            compact: sizeClass != .regular,
            dark: colorScheme == .dark,
            reduce: reduceMotion
        )
        GeometryReader { proxy in
            let compact = token.compact
            shell(compact: compact, size: proxy.size)
                .onAppear {
                    session.syncChrome(
                        compact: compact,
                        width: proxy.size.width,
                        height: proxy.size.height,
                        systemIsDark: token.dark,
                        reduceMotion: token.reduce
                    )
                }
                .onChange(of: token) { _, next in
                    session.syncChrome(
                        compact: next.compact,
                        width: proxy.size.width,
                        height: proxy.size.height,
                        systemIsDark: next.dark,
                        reduceMotion: next.reduce
                    )
                }
                .onChange(of: proxy.size) { _, size in
                    session.syncChrome(
                        compact: compact,
                        width: size.width,
                        height: size.height,
                        systemIsDark: token.dark,
                        reduceMotion: token.reduce
                    )
                }
        }
        .environment(\.sandTheme, session.theme)
        .environment(\.shellCopy, session.copy)
        .task {
            await session.refresh()
            await session.observe()
        }
    }

    @ViewBuilder
    private func shell(compact: Bool, size: CGSize) -> some View {
        let width = session.sidebarWidth
        HStack(spacing: 0) {
            if !compact || session.phase == .sidebar {
                sidebarStack
                    .frame(width: compact ? size.width : width.width)
            }
            if !compact || session.phase != .sidebar {
                contentStack(compact: compact, sidebarWidth: compact ? 0 : width.width, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(session.theme.color(.bgChrome).color.ignoresSafeArea())
        .animation(reduceMotion ? nil : .timingCurve(0.165, 0.84, 0.44, 1, duration: SandMetric.durationSlower), value: session.phase)
        .overlay { createOverlay(compact: compact, size: size) }
        .overlay { groupDialog }
    }

    private var sidebarStack: some View {
        SidebarColumn(session: session)
            .overlay(alignment: .trailing) {
                if session.phase == .split {
                    resizeHandle
                }
            }
    }

    private var resizeHandle: some View {
        SidebarResizeHandle(session: session)
    }

    private func contentStack(compact: Bool, sidebarWidth: Double, size: CGSize) -> some View {
        let selection = session.selection
        return ZStack(alignment: .topLeading) {
            session.theme.color(.bgEditor).color
            if session.showSettings {
                settingsFrame(compact: compact, size: size) {
                    content(selection)
                }
            } else if session.showsConversationSlot {
                VStack(spacing: 0) {
                    if showsTopBar(selection) {
                        ShellTopBar(
                            title: topTitle(selection),
                            titleLabel: topLabel(selection),
                            showBack: compact,
                            onBack: { session.back() },
                            onTitle: selection.agentID == nil ? nil : { session.openProfile(selection.agentID ?? "") }
                        )
                    }
                    content(selection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let profileID = session.profileID {
                profileLayer(id: profileID, compact: compact, contentWidth: size.width - sidebarWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func showsTopBar(_ selection: ShellSelection) -> Bool {
        if session.showSettings || session.createWork || session.createOpen { return false }
        return selection.agentID != nil || selection.workID != nil
    }

    private func topTitle(_ selection: ShellSelection) -> String {
        if let id = selection.agentID, let agent = session.agents.first(where: { $0.profile.id == id }) {
            return agent.profile.name
        }
        if let id = selection.workID, let work = session.works.first(where: { $0.profile.id == id }) {
            return work.profile.name
        }
        return ""
    }

    private func topLabel(_ selection: ShellSelection) -> String {
        if let id = selection.agentID, let agent = session.agents.first(where: { $0.profile.id == id }) {
            return session.copy.text("Open {name} profile", ["name": agent.profile.name])
        }
        return topTitle(selection)
    }

    private func profileLayer(id: String, compact: Bool, contentWidth: Double) -> some View {
        HStack(spacing: 0) {
            if !compact { Spacer(minLength: 0) }
            ProfileColumn(session: session, agentID: id)
                .frame(width: compact ? nil : min(profilePaneWidth(contentWidth: contentWidth), contentWidth))
                .frame(maxWidth: compact ? .infinity : nil, maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    if !compact {
                        Rectangle().fill(session.theme.color(.borderSubtle).color).frame(width: 1)
                    }
                }
        }
        .transition(reduceMotion ? .identity : .move(edge: .trailing))
    }

    @ViewBuilder
    private func settingsFrame(compact: Bool, size: CGSize, @ViewBuilder inner: () -> some View) -> some View {
        if compact {
            VStack(spacing: 0) {
                ShellTopBar(title: "", titleLabel: "", showBack: true, onBack: { session.back() }, onTitle: nil)
                inner()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(session.theme.color(.bgEditor).color)
        } else if size.width < SandMetric.settingsWideBelow {
            ZStack {
                session.theme.color(.scrim).color.ignoresSafeArea().onTapGesture { session.dismissOverlay() }
                inner()
                    .frame(width: size.width - 32, height: size.height - 32)
                    .background(session.theme.color(.bgElevated).color)
                    .clipShape(RoundedRectangle(cornerRadius: SandMetric.radius3XL))
            }
        } else {
            ZStack {
                session.theme.color(.scrim).color.ignoresSafeArea().onTapGesture { session.dismissOverlay() }
                inner()
                    .frame(width: min(SandMetric.settingsDialog, size.width - 32))
                    .frame(maxHeight: size.height * 0.9)
                    .background(session.theme.color(.bgElevated).color)
                    .clipShape(RoundedRectangle(cornerRadius: SandMetric.radius3XL))
            }
        }
    }

    @ViewBuilder
    private func createOverlay(compact: Bool, size: CGSize) -> some View {
        if session.createOpen {
            if compact {
                CreateNunuPage(session: session, card: false)
                    .frame(width: size.width, height: size.height)
                    .background(session.theme.color(.bgEditor).color)
            } else {
                ZStack {
                    session.theme.color(.scrim).color.ignoresSafeArea()
                        .onTapGesture { if !session.creating { session.closeCreate() } }
                    CreateNunuPage(session: session, card: true)
                        .frame(width: min(SandMetric.createDialog, size.width - 32))
                        .frame(maxHeight: size.height - 32)
                }
            }
        }
    }
}

private struct GroupNameDialog: View {
    var session: ShellSession
    @Environment(\.sandTheme) private var theme
    @Environment(\.shellCopy) private var copy
    @State private var name = ""

    var body: some View {
        let dialog = session.groupDialog
        ZStack {
            theme.color(.scrim).color.ignoresSafeArea()
                .onTapGesture { if !session.busy { session.closeGroupDialog() } }
            VStack(alignment: .leading, spacing: SandMetric.spacing3) {
                HStack {
                    Text(copy.text(dialog?.titleKey ?? "New group"))
                        .font(sandFont(SandMetric.fontBase, weight: .semibold))
                        .foregroundStyle(theme.color(.textPrimary).color)
                    Spacer()
                    IconButton(systemName: "xmark", label: copy.text("Close group dialog"), enabled: !session.busy) {
                        session.closeGroupDialog()
                    }
                }
                TextField(copy.text("Group name"), text: $name)
                    .font(sandFont(SandMetric.fontBase))
                    .foregroundStyle(theme.color(.textPrimary).color)
                    .padding(SandMetric.spacing2)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(theme.color(.borderSubtle).color).frame(height: 1)
                    }
                    .disabled(session.busy)
                    .onChange(of: name) { _, value in
                        if value.count > SandMetric.nameMax { name = String(value.prefix(SandMetric.nameMax)) }
                    }
                    .accessibilityLabel(copy.text("Group name"))
                    .accessibilityIdentifier("group-name-field")
                if let error = dialog?.error {
                    Text(copy.text(error))
                        .font(sandFont(SandMetric.fontSM))
                        .foregroundStyle(theme.color(.textDanger).color)
                }
                HStack {
                    Spacer()
                    PillButton(title: copy.text("Cancel"), primary: false, enabled: !session.busy) {
                        session.closeGroupDialog()
                    }
                    PillButton(
                        title: copy.text(session.busy ? "Saving…" : "Save"),
                        primary: true,
                        enabled: !session.busy && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        Task { await session.saveGroup(name: name) }
                    }
                }
            }
            .padding(SandMetric.spacing4)
            .frame(maxWidth: 360)
            .background(theme.color(.bgElevated).color)
            .clipShape(RoundedRectangle(cornerRadius: SandMetric.radiusXL))
            .overlay(
                RoundedRectangle(cornerRadius: SandMetric.radiusXL)
                    .stroke(theme.color(.borderSubtle).color, lineWidth: 1)
            )
            .shadow(color: theme.color(.shadowPopover).color, radius: 16, y: 8)
        }
        .onAppear { name = dialog?.initialName ?? "" }
    }
}

extension NuumShell {
    @ViewBuilder fileprivate var groupDialog: some View {
        if session.groupDialog != nil {
            GroupNameDialog(session: session)
        }
    }
}

private struct ChromeToken: Equatable {
    var compact: Bool
    var dark: Bool
    var reduce: Bool
}

private struct SidebarResizeHandle: View {
    var session: ShellSession
    @State private var origin: Double?

    var body: some View {
        Rectangle()
            .fill(session.theme.color(.borderDefault).color)
            .frame(width: 1)
            .frame(width: SandMetric.spacing11)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if origin == nil {
                            origin = session.sidebarWidth.width
                            session.beginResize()
                        }
                        session.updateResize(max(SandMetric.sidebarCollapsed, (origin ?? 0) + value.translation.width))
                    }
                    .onEnded { _ in
                        session.endResize()
                        origin = nil
                    }
            )
            .accessibilityLabel(session.copy.text("Resize sidebar"))
    }
}

private struct SystemClipboard: AgentIDClipboard {
    func copy(_ text: String) -> Bool {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        return true
        #else
        return false
        #endif
    }
}
#endif
