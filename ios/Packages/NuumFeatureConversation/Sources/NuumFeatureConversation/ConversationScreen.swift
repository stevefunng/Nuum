#if canImport(SwiftUI)
import SwiftUI
import NuumContracts
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ConversationModel: ObservableObject {
    @Published private(set) var state: ConversationUiState
    let session: ConversationSession

    init(agentId: String?, ports: ConversationPorts) {
        let session = ConversationSession(agentId: agentId, ports: ports)
        self.session = session
        self.state = session.state
        session.onChange = { [weak self] in
            guard let self else { return }
            self.state = self.session.state
        }
    }
}

/// One-to-one conversation. The shell owns compact versus regular columns and
/// passes `onBack` for the compact return to the agent list.
public struct ConversationScreen: View {
    private let agentId: String?
    private let ports: ConversationPorts
    private let language: Language
    private let theme: ThemePreference
    private let onOpenProfile: ((String) -> Void)?
    private let onBack: (() -> Void)?

    public init(
        agentId: String?,
        ports: ConversationPorts,
        language: Language = .zhCN,
        theme: ThemePreference = .dark,
        onOpenProfile: ((String) -> Void)? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.agentId = agentId
        self.ports = ports
        self.language = language
        self.theme = theme
        self.onOpenProfile = onOpenProfile
        self.onBack = onBack
    }

    public var body: some View {
        ConversationHost(
            agentId: agentId,
            ports: ports,
            language: language,
            theme: theme,
            onOpenProfile: onOpenProfile,
            onBack: onBack
        )
        .id(agentId ?? "none")
    }
}

private struct ConversationHost: View {
    @StateObject private var model: ConversationModel
    private let language: Language
    private let themePreference: ThemePreference
    private let onOpenProfile: ((String) -> Void)?
    private let onBack: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor
    init(
        agentId: String?,
        ports: ConversationPorts,
        language: Language,
        theme: ThemePreference,
        onOpenProfile: ((String) -> Void)?,
        onBack: (() -> Void)?
    ) {
        _model = StateObject(wrappedValue: ConversationModel(agentId: agentId, ports: ports))
        self.language = language
        self.themePreference = theme
        self.onOpenProfile = onOpenProfile
        self.onBack = onBack
    }

    var body: some View {
        let compact = sizeClass == .compact
        let dark = resolvedDark
        let theme = ConversationTheme(dark: dark, language: language, reduceMotion: reduceMotion, compact: compact)
        let state = model.state
        VStack(spacing: 0) {
            topBar(state: state, theme: theme, compact: compact)
            ZStack {
                if state.phase == .loading || (state.loadFailed && state.agent == nil) {
                    Color.clear
                } else if state.showsTranscript {
                    TranscriptList(
                        state: state,
                        onAnswer: { messageId, value in
                            Task { await model.session.answerWidget(messageId: messageId, value: value) }
                        },
                        onOpenAttachment: { path in
                            Task { await model.session.openAttachment(path: path) }
                        },
                        onOpenPeer: { model.session.openPeer($0) }
                    )
                } else if state.showsWordmark {
                    emptyWelcome(theme)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            composer(state: state, theme: theme)
        }
        .background(theme.color(SandToken.bgEditor))
        .environment(\.conversationTheme, theme)
        .overlay {
            if let peerId = state.openPeerId, let agent = state.agent {
                let blocks = state.visibleBlocks().compactMap { block -> PeerBlock? in
                    if case .peer(let peer) = block, peer.agentId == peerId { return peer }
                    return nil
                }
                let peer = state.peers.first { $0.profile.id == peerId }
                PeerDrawer(
                    agent: agent,
                    peer: peer,
                    peerName: peer?.profile.name ?? blocks.first?.agentName ?? theme.text(.agent),
                    blocks: blocks,
                    timestamps: transcriptTimestamps(state.events),
                    onClose: { model.session.closePeer() }
                )
            }
        }
        .task { await model.session.run() }
    }

    private var resolvedDark: Bool {
        switch themePreference {
        case .dark: true
        case .light: false
        case .system: colorScheme == .dark
        }
    }

    private func topBar(state: ConversationUiState, theme: ConversationTheme, compact: Bool) -> some View {
        HStack(spacing: 8) {
            if compact, let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.color(SandToken.textPrimary))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(theme.text(.agents))
            }
            if let agent = state.agent {
                Button {
                    onOpenProfile?(agent.profile.id)
                } label: {
                    HStack(spacing: 8) {
                        NunuAvatarView(
                            agentId: agent.profile.id,
                            colorId: agent.profile.avatarColor,
                            shapeId: agent.profile.avatarShape,
                            materialId: agent.profile.avatarMaterial,
                            size: 28,
                            activity: state.activity
                        )
                        VStack(alignment: .leading, spacing: 0) {
                            Text(agent.profile.name)
                                .font(.system(size: SandMetrics.fontBase, weight: .semibold))
                                .foregroundStyle(theme.color(SandToken.textPrimary))
                            if let caption = state.topBarCaption {
                                Text(theme.text(caption))
                                    .font(.system(size: SandMetrics.fontXS))
                                    .foregroundStyle(theme.color(SandToken.textTertiary))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(onOpenProfile == nil)
                .accessibilityLabel(theme.text(.openProfile, ["name": agent.profile.name]))
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 4)
        .frame(height: SandMetrics.spacing14)
    }

    private func emptyWelcome(_ theme: ConversationTheme) -> some View {
        VStack(spacing: SandMetrics.spacing2 + SandMetrics.spacing0_5) {
            Text("Nuum")
                .font(.system(size: SandMetrics.wordmark, weight: .semibold))
                .tracking(SandMetrics.wordmarkTracking)
                .foregroundStyle(theme.color(SandToken.textPrimary))
            Text(theme.text(.askAnything))
                .font(.system(size: SandMetrics.fontBase))
                .foregroundStyle(theme.color(SandToken.textTertiary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 120)
    }

    private func composer(state: ConversationUiState, theme: ConversationTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.showsRunningRow, let agent = state.agent, let caption = state.runningCaption {
                HStack(spacing: 8) {
                    NunuAvatarView(
                        agentId: agent.profile.id,
                        colorId: agent.profile.avatarColor,
                        shapeId: agent.profile.avatarShape,
                        materialId: agent.profile.avatarMaterial,
                        size: 40,
                        activity: state.activity
                    )
                    Text(theme.text(caption))
                        .font(.system(size: SandMetrics.fontSM))
                        .foregroundStyle(theme.color(SandToken.textTertiary))
                }
            }
            if let pending = oneToOneApproval(state.pending) {
                ApprovalBarView(pending: pending, deciding: state.deciding, error: state.approvalError) { resolution in
                    Task { await model.session.decide(resolution) }
                }
            }
            if state.readingAttachments {
                statusLine(theme.text(.reading), danger: false, theme: theme)
            }
            if state.showsImageWarning {
                statusLine(theme.text(.noImageSupport), danger: false, theme: theme)
            }
            if let error = state.attachmentError {
                statusLine(theme.text(error), danger: true, theme: theme)
            }
            if let notice = state.notice {
                statusLine(notice.text(language: theme.language), danger: notice.alert, theme: theme)
            }
            composerShell(state: state, theme: theme)
        }
        .padding(.horizontal, SandMetrics.spacing3)
        .padding(.bottom, SandMetrics.spacing3)
        .background(theme.color(SandToken.bgEditor))
    }

    private func statusLine(_ text: String, danger: Bool, theme: ConversationTheme) -> some View {
        Text(text)
            .font(.system(size: danger ? SandMetrics.fontXS : SandMetrics.fontXS))
            .foregroundStyle(danger ? theme.color(SandToken.textDanger) : theme.color(SandToken.textTertiary))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func composerShell(state: ConversationUiState, theme: ConversationTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !state.attachments.isEmpty {
                FlowLayout(spacing: SandMetrics.spacing1_5).callAsFunction {
                    ForEach(Array(state.attachments.enumerated()), id: \.offset) { index, file in
                        ComposerChip(file: file, enabled: state.canRemoveAttachment) {
                            model.session.removeAttachment(at: index)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(theme.text(.attachments))
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button {
                        Task { await model.session.pickAttachments() }
                    } label: {
                        Label(theme.text(.addAttachment), systemImage: "paperclip")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(theme.color(SandToken.textPrimary))
                }
                .accessibilityLabel(theme.text(.composerActions))
                .disabled(!state.canPickAttachments)
                TextField(placeholder(state, theme), text: draft, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.system(size: SandMetrics.fontLG))
                    .disabled(!state.canEditDraft)
                    .onSubmit { Task { await submit(state) } }
                Button {
                    Task { await submit(state) }
                } label: {
                    Image(systemName: state.showStop ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(state.showStop ? theme.color(SandToken.textOnPrimary) : theme.color(SandToken.textOnColor))
                        .background(
                            state.sendEnabled ? theme.color(SandToken.fillPrimary) : theme.color(SandToken.fillSecondary),
                            in: Circle()
                        )
                }
                .disabled(!state.sendEnabled)
                .accessibilityLabel(theme.text(state.showStop ? .stop : .sendMessage))
            }
        }
        .padding(12)
        .background(theme.color(SandToken.bgInput), in: RoundedRectangle(cornerRadius: SandMetrics.radius3XL))
        .overlay(
            RoundedRectangle(cornerRadius: SandMetrics.radius3XL)
                .stroke(theme.color(SandToken.borderDefault), lineWidth: 1)
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard state.canPickAttachments else { return false }
            switch readPickedFiles(urls) {
            case .success(let files):
                model.session.ingestDropped(files)
            case .failure:
                model.session.noteAttachmentReadFailed()
            }
            return true
        }
    }

    private var draft: Binding<String> {
        Binding(
            get: { model.state.draft },
            set: { model.session.setDraft($0) }
        )
    }

    private func placeholder(_ state: ConversationUiState, _ theme: ConversationTheme) -> String {
        if let name = state.agent?.profile.name {
            return theme.text(.messageName, ["name": name])
        }
        return theme.text(.askAnything)
    }

    private func submit(_ state: ConversationUiState) async {
        if state.showStop {
            await model.session.cancelRun()
        } else {
            await model.session.send()
        }
    }
}

private struct ComposerChip: View {
    var file: ComposerAttachment
    var enabled: Bool
    var remove: () -> Void
    @Environment(\.conversationTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: SandMetrics.fontXS))
                    .lineLimit(1)
                    .foregroundStyle(theme.color(SandToken.textPrimary))
                Text("\(attachmentKilobytes(file.bytes.count)) KB")
                    .font(.system(size: SandMetrics.fontXS))
                    .foregroundStyle(theme.color(SandToken.textTertiary))
            }
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(!enabled)
            .accessibilityLabel(theme.text(.removeName, ["name": file.name]))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: 210, minHeight: SandMetrics.spacing12, alignment: .leading)
        .background(theme.color(SandToken.bgTertiary), in: RoundedRectangle(cornerRadius: SandMetrics.radiusLG))
        .overlay(
            RoundedRectangle(cornerRadius: SandMetrics.radiusLG)
                .stroke(theme.color(SandToken.borderDefault), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        #if canImport(UIKit)
        if isImageMime(file.mimeType), let image = UIImage(data: file.bytes) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: SandMetrics.radiusSM))
        } else {
            Image(systemName: "paperclip")
                .frame(width: 32, height: 32)
        }
        #else
        Image(systemName: "paperclip")
            .frame(width: 32, height: 32)
        #endif
    }
}
#endif
