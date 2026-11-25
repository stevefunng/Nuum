import NuumContracts
import NuumFeatureConversation
import NuumFeatureSettings
import NuumFeatureShell
import NuumFeatureWork
import SwiftUI

/// Composed window. The shell owns the columns; this view fills the content slot.
struct RootView: View {
    @State private var picker: DocumentPickerModel?
    @State private var graph: AppGraph?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let graph, let picker {
                PickerHost(graph: graph, picker: picker)
            } else if unavailable {
                Text("Couldn't open the local store.")
            }
        }
        .task { await boot() }
    }

    private func boot() async {
        guard graph == nil, !unavailable else { return }
        let picker = self.picker ?? DocumentPickerModel()
        self.picker = picker
        picker.attach()
        do {
            let built = try AppGraph(picker: picker)
            await built.start()
            graph = built
        } catch {
            unavailable = true
        }
    }
}

private struct PickerHost: View {
    let graph: AppGraph
    @ObservedObject var picker: DocumentPickerModel

    var body: some View {
        NuumShell(ports: graph.shellPorts) { selection in
            ShellContent(graph: graph, selection: selection)
        }
        .nuumDocumentPickers(picker)
    }
}

private struct ShellContent: View {
    let graph: AppGraph
    let selection: ShellSelection
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showProactive = false
    @State private var language = Language.zhCN
    @State private var theme = ThemePreference.dark

    var body: some View {
        slot
            .onChange(of: selection.showSettings) { _, showing in
                if !showing { showProactive = false }
            }
            .task { await observeSettings() }
    }

    @ViewBuilder
    private var slot: some View {
        let compact = sizeClass != .regular
        let widthClass: SettingsWidthClass = compact ? .compact : .regular
        if selection.createWork {
            WorkCreationScreen(
                ports: graph.workPorts,
                canCancel: selection.agentID != nil || selection.workID != nil,
                language: language,
                theme: theme,
                onCancel: hop(selection.dismissOverlay),
                onCreated: hopProfile { _ in selection.dismissOverlay() }
            )
        } else if selection.showSettings && showProactive {
            ProactiveScreen(
                settings: graph.settingsPort,
                proactive: graph.proactivePort,
                clock: graph.clock,
                onBack: hop { showProactive = false },
                onOpenAgent: hopID { id in
                    showProactive = false
                    selection.dismissOverlay()
                    selection.openProfile(id)
                },
                onOpenShell: hop {
                    showProactive = false
                    selection.dismissOverlay()
                }
            )
        } else if selection.showSettings {
            SettingsScreen(
                settings: graph.settingsPort,
                secrets: graph.secretWriter,
                widthClass: widthClass,
                onClose: hop(selection.dismissOverlay),
                onOpenProactive: hop { showProactive = true }
            )
        } else if let workID = selection.workID {
            // ShellSelection does not expose ShellSession.back. The shell's own compact
            // top bar returns to the agent list. This chevron dismisses overlays.
            WorkScreen(
                workId: workID,
                ports: graph.workPorts,
                language: language,
                theme: theme,
                onBack: hop(selection.dismissOverlay)
            )
            .id(workID)
        } else if let agentID = selection.agentID {
            ConversationScreen(
                agentId: agentID,
                ports: graph.conversationPorts,
                language: language,
                theme: theme,
                onOpenProfile: hopID { selection.openProfile($0) },
                onBack: hop(selection.dismissOverlay)
            )
            .id(agentID)
        } else {
            Color.clear
        }
    }

    /// Language and theme only. Key presence flags are not copied into any field.
    private func observeSettings() async {
        let port = graph.settingsPort
        let stream = port.events
        if let settings = try? await port.get() {
            language = settings.language
            theme = settings.theme
        }
        for await event in stream {
            guard case .settingsUpdated(let settings) = event else { continue }
            language = settings.language
            theme = settings.theme
        }
    }
}

/// View callbacks are nonisolated. Hop so the shell's main-actor closures still run there.
private func hop(_ action: @escaping @MainActor () -> Void) -> () -> Void {
    let box = MainHop(action)
    return { box.run() }
}

private func hopID(_ action: @escaping @MainActor (String) -> Void) -> (String) -> Void {
    let box = MainHopValue(action)
    return { box.run($0) }
}

private func hopProfile(_ action: @escaping @MainActor (WorkProfile) -> Void) -> (WorkProfile) -> Void {
    let box = MainHopValue(action)
    return { box.run($0) }
}

private final class MainHop: @unchecked Sendable {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func run() {
        Task { @MainActor in self.action() }
    }
}

private final class MainHopValue<Value: Sendable>: @unchecked Sendable {
    private let action: @MainActor (Value) -> Void

    init(_ action: @escaping @MainActor (Value) -> Void) {
        self.action = action
    }

    func run(_ value: Value) {
        Task { @MainActor in self.action(value) }
    }
}
