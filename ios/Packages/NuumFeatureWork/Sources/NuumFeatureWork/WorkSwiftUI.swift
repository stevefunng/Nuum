#if canImport(SwiftUI)
import NuumContracts
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

extension Color {
    init(_ sand: SandColor) {
        self.init(.sRGB, red: sand.red, green: sand.green, blue: sand.blue, opacity: sand.alpha)
    }
}

func pt(_ value: Double) -> CGFloat { CGFloat(value) }

enum WorkClipboard {
    static func copy(_ text: String) -> Bool {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        return true
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
        #else
        _ = text
        return false
        #endif
    }
}

@MainActor
final class WorkScreenModel: ObservableObject {
    @Published private(set) var state = WorkUiState()
    private let store: WorkStore
    private let ports: WorkPorts
    private var started = false

    init(workId: String, ports: WorkPorts) {
        self.ports = ports
        self.store = WorkStore(workId: workId, ports: ports)
    }

    func activate() async {
        guard !started else { return }
        started = true
        defer { started = false }
        await store.reload()
        state = await store.state
        let workEvents = ports.work.events
        let agentEvents = ports.agent.events
        async let workWatch: Void = watch(workEvents)
        async let agentWatch: Void = watch(agentEvents)
        _ = await (workWatch, agentWatch)
    }

    func setAcceptsModelRequests(_ value: Bool) async {
        await store.setAcceptsModelRequests(value)
        state = await store.state
    }

    func upgrade() async { await store.upgrade(); await publish() }
    func post(_ body: String) async { await store.post(body: body); await publish() }
    func continueDiscussion(eventId: String, inputAfterSeq: Int?) async {
        await store.continueDiscussion(eventId: eventId, inputAfterSeq: inputAfterSeq)
        await publish()
    }
    func stopDiscussion() async { await store.stopDiscussion(); await publish() }
    func detach(agentId: String, revision: Int) async { await store.detach(agentId: agentId, revision: revision); await publish() }
    func attach(agentId: String) async { await store.attach(agentId: agentId); await publish() }
    func removeCatalog(entryId: String) async { await store.removeCatalog(entryId: entryId); await publish() }

    func transition(task: WorkTask, to: WorkTaskState) async -> WorkNotice? {
        do {
            try await store.transition(task: task, to: to)
            await publish()
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            return workNotice(from: error)
        }
    }

    func dispatch(agentId: String, taskId: String, instruction: String) async -> WorkNotice? {
        do {
            try await store.dispatch(agentId: agentId, taskId: taskId, instruction: instruction)
            await publish()
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            return workNotice(from: error)
        }
    }

    func loadTrace(taskId: String, sessionId: String?, beforeSeq: Int?) async throws -> TranscriptPage {
        try await store.loadTrace(taskId: taskId, sessionId: sessionId, beforeSeq: beforeSeq)
    }

    func addCatalog(_ entry: WorkCatalogInput) async -> WorkNotice? {
        do {
            try await store.addCatalog(entry)
            await publish()
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            return workNotice(from: error)
        }
    }

    func decide(_ approval: PendingApproval, _ resolution: ToolResolution) async {
        await store.decide(approval: approval, resolution: resolution)
        await publish()
    }

    func pickDirectory() async -> DirectoryPick { await store.pickDirectory() }

    func create(name: String, kind: WorkKind) async throws -> WorkProfile? {
        try await store.create(name: name, kind: kind)
    }

    private func publish() async { state = await store.state }

    private func watch(_ events: AsyncStream<HostEvent>) async {
        for await event in events {
            await store.apply(event)
            state = await store.state
        }
    }
}

struct WorkChrome {
    var language: Language
    var palette: WorkPalette
    var compact: Bool
    var reduceMotion: Bool

    func text(_ key: String, _ pairs: [String: String] = [:]) -> String {
        WorkCopy.text(key, language: language, pairs)
    }

    var motion: Animation? {
        reduceMotion ? nil : .timingCurve(0.25, 0.1, 0.25, 1, duration: WorkMetrics.durationNormal)
    }
}

struct WorkTextButton: View {
    var title: String
    var chrome: WorkChrome
    var primary = false
    var enabled = true
    var selected = false
    var identifier: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: pt(WorkMetrics.fontBase), weight: primary ? .semibold : .medium))
                .frame(minHeight: pt(WorkMetrics.spacing11))
                .padding(.horizontal, pt(WorkMetrics.spacing3))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(primary ? chrome.palette.textOnPrimary : chrome.palette.textPrimary))
        .background(
            RoundedRectangle(cornerRadius: pt(WorkMetrics.radiusLG), style: .continuous)
                .fill(Color(fill))
        )
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier(identifier ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: SandColor {
        if primary || selected { return chrome.palette.fillPrimary }
        return chrome.palette.fillSecondary
    }
}

/// Room when the snapshot kind is `room`, NunuBar when it is `work`.
/// Cards come from the snapshot. This screen has no control that creates a card.
public struct WorkScreen: View {
    private let workId: String
    private let fallbackTitle: String
    private let language: Language
    private let theme: ThemePreference
    private let onBack: (() -> Void)?
    @StateObject private var model: WorkScreenModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    public init(
        workId: String,
        ports: WorkPorts,
        fallbackTitle: String = "",
        language: Language = .zhCN,
        theme: ThemePreference = .dark,
        onBack: (() -> Void)? = nil
    ) {
        self.workId = workId
        self.fallbackTitle = fallbackTitle
        self.language = language
        self.theme = theme
        self.onBack = onBack
        _model = StateObject(wrappedValue: WorkScreenModel(workId: workId, ports: ports))
    }

    public var body: some View {
        let chrome = WorkChrome(
            language: language,
            palette: WorkPalette.resolve(theme, systemDark: colorScheme == .dark),
            compact: sizeClass != .regular,
            reduceMotion: reduceMotion
        )
        GeometryReader { geometry in
            WorkBoardColumn(
                workId: workId,
                model: model,
                chrome: chrome,
                fallbackTitle: fallbackTitle,
                columnWidth: geometry.size.width,
                onBack: onBack
            )
        }
        .background(Color(chrome.palette.editor))
        .task { await model.activate() }
        .onChange(of: scenePhase) { _, phase in
            Task { @MainActor in  await model.setAcceptsModelRequests(phase == .active) }
        }
    }
}

public struct WorkCreationScreen: View {
    private let ports: WorkPorts
    private let canCancel: Bool
    private let language: Language
    private let theme: ThemePreference
    private let onCancel: () -> Void
    private let onCreated: (WorkProfile) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var form = WorkCreationForm()

    public init(
        ports: WorkPorts,
        canCancel: Bool,
        language: Language = .zhCN,
        theme: ThemePreference = .dark,
        onCancel: @escaping () -> Void,
        onCreated: @escaping (WorkProfile) -> Void
    ) {
        self.ports = ports
        self.canCancel = canCancel
        self.language = language
        self.theme = theme
        self.onCancel = onCancel
        self.onCreated = onCreated
    }

    public var body: some View {
        let chrome = WorkChrome(
            language: language,
            palette: WorkPalette.resolve(theme, systemDark: colorScheme == .dark),
            compact: false,
            reduceMotion: reduceMotion
        )
        ZStack {
            Color(chrome.palette.editor).ignoresSafeArea()
            VStack(alignment: .leading, spacing: pt(WorkMetrics.spacing3)) {
                Text(chrome.text("A place for the job, not another chat"))
                    .font(.system(size: pt(WorkMetrics.fontSM)))
                    .foregroundStyle(Color(chrome.palette.textTertiary))
                Text(chrome.text("Create a Work"))
                    .font(.system(size: pt(WorkMetrics.fontTitle), weight: .semibold))
                    .foregroundStyle(Color(chrome.palette.textPrimary))
                Text(chrome.text("Keep tasks, shared discussion, Agents, capabilities, and deliverables together."))
                    .font(.system(size: pt(WorkMetrics.fontLG)))
                    .foregroundStyle(Color(chrome.palette.textSecondary))
                HStack(spacing: pt(WorkMetrics.spacing2)) {
                    WorkTextButton(
                        title: chrome.text("Local room"),
                        chrome: chrome,
                        primary: form.kind == .room,
                        enabled: !form.submitting,
                        selected: form.kind == .room
                    ) { form.kind = .room }
                    WorkTextButton(
                        title: "NunuBar",
                        chrome: chrome,
                        primary: form.kind == .work,
                        enabled: !form.submitting,
                        selected: form.kind == .work
                    ) { form.kind = .work }
                }
                Text(chrome.text("Name"))
                    .font(.system(size: pt(WorkMetrics.fontSM)))
                    .foregroundStyle(Color(chrome.palette.textSecondary))
                TextField(chrome.text("e.g. Product launch"), text: $form.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: pt(WorkMetrics.fontBase)))
                    .foregroundStyle(Color(chrome.palette.textPrimary))
                    .padding(pt(WorkMetrics.spacing3))
                    .background(RoundedRectangle(cornerRadius: pt(WorkMetrics.radiusLG)).fill(Color(chrome.palette.elevated)))
                    .overlay(RoundedRectangle(cornerRadius: pt(WorkMetrics.radiusLG)).stroke(Color(chrome.palette.borderSubtle)))
                    .accessibilityLabel(chrome.text("Name"))
                    .accessibilityIdentifier("work-create-name")
                    .disabled(form.submitting)
                if let notice = form.notice {
                    Text(chrome.text(notice.message))
                        .font(.system(size: pt(WorkMetrics.fontSM)))
                        .foregroundStyle(Color(chrome.palette.textDanger))
                }
                HStack {
                    Spacer()
                    if canCancel {
                        WorkTextButton(title: chrome.text("Cancel"), chrome: chrome, enabled: !form.submitting, action: onCancel)
                    }
                    WorkTextButton(
                        title: chrome.text("Create Work"),
                        chrome: chrome,
                        primary: true,
                        enabled: form.canSubmit
                    ) {
                        let draft = form
                        form.submitting = true
                        form.notice = nil
                        Task { @MainActor in 
                            do {
                                let store = WorkStore(workId: "", ports: ports)
                                if let profile = try await store.create(name: draft.name, kind: draft.kind) {
                                    onCreated(profile)
                                } else {
                                    form.submitting = false
                                }
                            } catch is CancellationError {
                                form.submitting = false
                            } catch {
                                form.notice = workNotice(from: error)
                                form.submitting = false
                            }
                        }
                    }
                }
            }
            .padding(pt(WorkMetrics.spacing6))
            .frame(maxWidth: pt(WorkMetrics.createMaxWidth))
        }
    }
}
#endif
