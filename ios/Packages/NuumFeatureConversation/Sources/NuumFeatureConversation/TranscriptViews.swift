#if canImport(SwiftUI)
import SwiftUI
import NuumContracts

#if canImport(UIKit)
import UIKit
#endif

struct TranscriptList: View {
    var state: ConversationUiState
    var onAnswer: (String, String) -> Void
    var onOpenAttachment: (String) -> Void
    var onOpenPeer: (String) -> Void
    @Environment(\.conversationTheme) private var theme
    @State private var pinned = true

    var body: some View {
        let blocks = state.visibleBlocks()
        let rows = transcriptRows(
            blocks,
            timestamps: transcriptTimestamps(state.events),
            language: theme.language
        )
        let answers = widgetAnswers(blocks)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SandMetrics.spacing4) {
                    ForEach(rows) { row in
                        rowView(row, answers: answers)
                    }
                    Color.clear.frame(height: 1).id("transcript-bottom")
                        .onAppear { pinned = true }
                        .onDisappear { pinned = false }
                }
                .padding(.top, SandMetrics.spacing12)
                .padding(.horizontal, SandMetrics.spacing4 + SandMetrics.spacing0_5)
                .padding(.bottom, SandMetrics.spacing7)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(theme.text(.transcript))
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: rows.count) { _, _ in
                guard pinned else { return }
                scroll(proxy, animated: !theme.reduceMotion)
            }
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [theme.color(SandToken.bgEditor), theme.color(SandToken.bgEditor).opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: SandMetrics.fade)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func rowView(_ row: TranscriptRow, answers: [String: String]) -> some View {
        switch row {
        case .time(_, let text):
            capsule(text)
        case .block(.user(let block)):
            UserBubble(block: block, chatHex: chatHex(state.agent), onOpenAttachment: onOpenAttachment)
        case .block(.assistant(let block)):
            AssistantActivity(block: block)
        case .block(.message(let block)):
            AssistantMessage(
                block: block,
                answer: answers[block.id],
                error: state.widgetErrors[block.id],
                onAnswer: { onAnswer(block.id, $0) },
                onOpenAttachment: onOpenAttachment
            )
        case .block(.peer(let block)):
            PeerRow(block: block, peers: state.peers, onOpen: { onOpenPeer(block.agentId) })
        case .block(.notice(let block)):
            capsule(localizedNotice(block, language: theme.language))
        }
    }

    private func capsule(_ text: String) -> some View {
        Text(text)
            .font(.system(size: SandMetrics.fontSM))
            .foregroundStyle(theme.color(SandToken.textTertiary))
            .padding(.horizontal, SandMetrics.spacing2 + SandMetrics.spacing0_5)
            .padding(.vertical, 4)
            .background(theme.color(SandToken.bgElevated), in: Capsule())
            .frame(maxWidth: .infinity)
    }

    private func chatHex(_ agent: AgentView?) -> String {
        guard let agent else { return "#3b4140" }
        return resolveNunuAppearance(
            agentId: agent.profile.id,
            color: agent.profile.avatarColor,
            shape: agent.profile.avatarShape,
            material: agent.profile.avatarMaterial
        ).chatHex
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.timingCurve(0.165, 0.84, 0.44, 1, duration: SandMetrics.durationSlow)) {
                proxy.scrollTo("transcript-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("transcript-bottom", anchor: .bottom)
        }
    }
}

struct UserBubble: View {
    var block: UserBlock
    var chatHex: String
    var onOpenAttachment: (String) -> Void
    @Environment(\.conversationTheme) private var theme

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if !block.text.isEmpty {
                    Text(block.text)
                        .font(.system(size: SandMetrics.fontLG))
                        .lineSpacing(SandMetrics.lineLG - SandMetrics.fontLG)
                        .foregroundStyle(theme.color(SandToken.textOnColor))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(sand: chatHex), in: RoundedRectangle(cornerRadius: SandMetrics.radius4XL))
                }
                ForEach(block.attachments, id: \.path) { attachment in
                    AttachmentChipButton(name: attachment.name) { onOpenAttachment(attachment.path) }
                }
            }
            .frame(maxWidth: userMax, alignment: .trailing)
        }
    }

    private var userMax: CGFloat { 560 }
}

struct AssistantMessage: View {
    var block: MessageBlock
    var answer: String?
    var error: Banner?
    var onAnswer: (String) -> Void
    var onOpenAttachment: (String) -> Void
    @Environment(\.conversationTheme) private var theme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                payload
                if let error {
                    Text(error.text(language: theme.language))
                        .font(.system(size: SandMetrics.fontXS))
                        .foregroundStyle(theme.color(SandToken.textDanger))
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var payload: some View {
        switch block.payload {
        case .text(let text):
            VStack(alignment: .leading, spacing: 8) {
                if !text.content.isEmpty {
                    bubble { MarkdownBody(source: text.content) }
                }
                ForEach(Array(text.images.enumerated()), id: \.offset) { _, image in
                    AttachmentImage(path: image.path, alt: image.alt) { onOpenAttachment(image.path) }
                }
            }
        case .attachment(let attachment):
            VStack(alignment: .leading, spacing: 8) {
                if isImagePath(attachment.path) {
                    AttachmentImage(path: attachment.path, alt: attachment.caption) { onOpenAttachment(attachment.path) }
                } else {
                    AttachmentChipButton(name: fileName(of: attachment.path)) { onOpenAttachment(attachment.path) }
                }
                if let caption = attachment.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: SandMetrics.fontSM))
                        .foregroundStyle(theme.color(SandToken.textSecondary))
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
        case .widget(let widget):
            WidgetCard(widget: widget, answer: answer, onAnswer: onAnswer)
        case .legacyWidget(let legacy):
            bubble {
                Text("\(legacy.widget) \(prettyJSONObject(legacy.props))")
                    .font(.system(size: SandMetrics.fontSM, design: .monospaced))
                    .foregroundStyle(theme.color(SandToken.textPrimary))
            }
        }
    }

    private func bubble<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(SandToken.fillBubbleAgent), in: RoundedRectangle(cornerRadius: SandMetrics.radius4XL))
    }
}

struct MarkdownBody: View {
    var source: String
    @Environment(\.conversationTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseMarkdown(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let spans):
                    Text(inlineAttributed(spans))
                        .font(.system(size: SandMetrics.fontLG))
                        .foregroundStyle(theme.color(SandToken.textPrimary))
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(theme.color(SandToken.textSecondary))
                                Text(inlineAttributed(item))
                            }
                            .font(.system(size: SandMetrics.fontLG))
                            .foregroundStyle(theme.color(SandToken.textPrimary))
                        }
                    }
                case .numbers(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1).").foregroundStyle(theme.color(SandToken.textSecondary))
                                Text(inlineAttributed(item))
                            }
                            .font(.system(size: SandMetrics.fontLG))
                            .foregroundStyle(theme.color(SandToken.textPrimary))
                        }
                    }
                case .code(let code):
                    Text(code)
                        .font(.system(size: SandMetrics.fontSM, design: .monospaced))
                        .foregroundStyle(theme.color(SandToken.textPrimary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(theme.color(SandToken.bgElevated), in: RoundedRectangle(cornerRadius: SandMetrics.toolRadius))
                }
            }
        }
    }

    private func inlineAttributed(_ spans: [InlineSpan]) -> AttributedString {
        var result = AttributedString()
        for span in spans {
            switch span {
            case .text(let value):
                result += AttributedString(value)
            case .code(let value):
                var code = AttributedString(value)
                code.font = .system(size: SandMetrics.fontSM, design: .monospaced)
                result += code
            case .link(let label, let url):
                var piece = AttributedString(label)
                if isOpenableURL(url), let destination = URL(string: url) {
                    piece.link = destination
                    piece.foregroundColor = theme.color(SandToken.textLink)
                }
                result += piece
            }
        }
        return result
    }
}

struct AssistantActivity: View {
    var block: AssistantBlock
    @Environment(\.conversationTheme) private var theme
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if activityLine(for: block) == .thinking {
                Text(theme.text(.thinking))
                    .font(.system(size: SandMetrics.fontSM))
                    .foregroundStyle(theme.reduceMotion ? theme.color(SandToken.textTertiary) : theme.color(SandToken.shimmerHighlight))
                    .opacity(theme.reduceMotion || !shimmer ? 1 : 0.55)
                    .onAppear {
                        guard !theme.reduceMotion else { return }
                        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: true)) {
                            shimmer = true
                        }
                    }
            }
            if block.tools.count > 1 {
                ToolCard(summary: groupSummary, status: groupToolStatus(block.tools)) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(block.tools.enumerated()), id: \.offset) { _, tool in
                            SingleTool(tool: tool)
                        }
                    }
                }
            } else {
                ForEach(Array(block.tools.enumerated()), id: \.offset) { _, tool in
                    SingleTool(tool: tool)
                }
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var groupSummary: String {
        let count = theme.text(.toolCalls, ["count": String(block.tools.count)])
        let status = theme.text(toolStatusKey(groupToolStatus(block.tools)))
        return "\(count) · \(status)"
    }
}

struct SingleTool: View {
    var tool: ToolView
    @Environment(\.conversationTheme) private var theme

    var body: some View {
        ToolCard(summary: summary, status: tool.status) {
            VStack(alignment: .leading, spacing: 8) {
                Text(theme.text(.arguments))
                    .font(.system(size: SandMetrics.fontXS))
                Text(prettyJSONObject(tool.arguments))
                    .font(.system(size: SandMetrics.fontSM, design: .monospaced))
                if let output = tool.output {
                    Text(theme.text(.output))
                        .font(.system(size: SandMetrics.fontXS))
                    Text(output.isEmpty ? theme.text(.noOutput) : output)
                        .font(.system(size: SandMetrics.fontSM, design: .monospaced))
                }
            }
        }
    }

    private var summary: String {
        "\(toolLabel(tool.name, language: theme.language)) \(theme.text(toolStatusKey(tool.status)))"
    }
}

struct ToolCard<Content: View>: View {
    var summary: String
    var status: String
    @ViewBuilder var content: () -> Content
    @Environment(\.conversationTheme) private var theme

    var body: some View {
        DisclosureGroup {
            content()
                .font(.system(size: SandMetrics.fontSM))
                .foregroundStyle(theme.color(SandToken.textSecondary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Text(summary)
                .font(.system(size: SandMetrics.fontSM))
                .foregroundStyle(theme.color(SandToken.textTertiary))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(theme.color(SandToken.bgElevated), in: RoundedRectangle(cornerRadius: SandMetrics.toolRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SandMetrics.toolRadius)
                .stroke(theme.color(SandToken.borderSubtle), lineWidth: 1)
        )
        .accessibilityValue(theme.text(toolStatusKey(status)))
    }
}

struct WidgetCard: View {
    var widget: WidgetPayload
    var answer: String?
    var onAnswer: ((String) -> Void)?
    @Environment(\.conversationTheme) private var theme
    @State private var custom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: SandMetrics.spacing1_5) {
            Text(widget.prompt)
                .font(.system(size: SandMetrics.fontLG, weight: .semibold))
                .foregroundStyle(theme.color(SandToken.textPrimary))
            if let help = widget.helpText, !help.isEmpty {
                Text(help)
                    .font(.system(size: SandMetrics.fontSM))
                    .foregroundStyle(theme.color(SandToken.textSecondary))
            }
            ForEach(Array(widget.options.enumerated()), id: \.offset) { _, option in
                optionButton(option)
            }
            if widget.allowCustom, answer == nil {
                HStack(spacing: 8) {
                    TextField(theme.text(.customAnswer), text: $custom)
                        .font(.system(size: SandMetrics.fontBase))
                    Button(theme.text(.send)) {
                        onAnswer?(custom.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || onAnswer == nil)
                }
            }
            if let answer {
                Text(theme.text(.yourAnswer, ["answer": answer]))
                    .font(.system(size: SandMetrics.fontSM))
                    .foregroundStyle(theme.color(SandToken.textSecondary))
            }
        }
        .padding(12)
        .frame(minWidth: 260, maxWidth: 380, alignment: .leading)
        .background(theme.color(SandToken.bgElevated), in: RoundedRectangle(cornerRadius: SandMetrics.toolRadius))
    }

    private func optionButton(_ option: WidgetOption) -> some View {
        let value = option.value ?? option.label
        let chosen = answer == value
        let resolved = answer != nil
        return Button {
            onAnswer?(value)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(.system(size: SandMetrics.fontBase, weight: option.style == "primary" ? .semibold : .regular))
                if let description = option.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: SandMetrics.fontSM))
                        .foregroundStyle(theme.color(SandToken.textSecondary))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .foregroundStyle(option.style == "danger" ? theme.color(SandToken.textDanger) : theme.color(SandToken.textPrimary))
            .background(
                chosen ? theme.color(SandToken.fillGhostSelected) : theme.color(SandToken.fillElevated),
                in: RoundedRectangle(cornerRadius: SandMetrics.toolRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SandMetrics.toolRadius)
                    .stroke(border(chosen: chosen, style: option.style), lineWidth: 1)
            )
            .opacity(!chosen && (resolved || onAnswer == nil) ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(resolved || onAnswer == nil)
    }

    private func border(chosen: Bool, style: String?) -> Color {
        if chosen { return theme.color(SandToken.borderFocus) }
        switch style {
        case "primary": return theme.color(SandToken.borderStrong)
        case "danger": return theme.color(SandToken.borderDanger)
        default: return theme.color(SandToken.borderDefault)
        }
    }
}

struct AttachmentChipButton: View {
    var name: String
    var action: () -> Void
    @Environment(\.conversationTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                    .font(.system(size: 16))
                Text(name)
                    .font(.system(size: SandMetrics.fontXS))
                    .lineLimit(1)
            }
            .foregroundStyle(theme.color(SandToken.textPrimary))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(theme.color(SandToken.bgTertiary), in: RoundedRectangle(cornerRadius: SandMetrics.radiusLG))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}

struct AttachmentImage: View {
    var path: String
    var alt: String?
    var action: () -> Void

    var body: some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(contentsOfFile: path) {
            Button(action: action) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: SandMetrics.imageMax)
                    .clipShape(RoundedRectangle(cornerRadius: SandMetrics.radiusLG))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(alt ?? fileName(of: path))
        } else {
            AttachmentChipButton(name: fileName(of: path), action: action)
        }
        #else
        AttachmentChipButton(name: fileName(of: path), action: action)
        #endif
    }
}

struct PeerRow: View {
    var block: PeerBlock
    var peers: [AgentView]
    var onOpen: () -> Void
    @Environment(\.conversationTheme) private var theme

    var body: some View {
        let peer = peers.first { $0.profile.id == block.agentId }
        let outbound = block.direction == "outbound"
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Text(theme.text(outbound ? .sentTo : .messageFrom))
                    .foregroundStyle(theme.color(SandToken.textTertiary))
                NunuAvatarView(
                    agentId: block.agentId,
                    colorId: peer?.profile.avatarColor,
                    shapeId: peer?.profile.avatarShape,
                    materialId: peer?.profile.avatarMaterial,
                    size: 20,
                    activity: outbound ? .sending : .receiving
                )
                Text(peer?.profile.name ?? block.agentName)
                    .font(.system(size: SandMetrics.fontBase, weight: .semibold))
                    .foregroundStyle(theme.color(SandToken.textPrimary))
                if block.priority {
                    Text(theme.text(.priority))
                        .font(.system(size: SandMetrics.fontXS))
                        .foregroundStyle(theme.color(SandToken.textTertiary))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(SandToken.textTertiary))
            }
        }
        .buttonStyle(.plain)
    }
}

struct PeerDrawer: View {
    var agent: AgentView
    var peer: AgentView?
    var peerName: String
    var blocks: [PeerBlock]
    var timestamps: [String: Int64]
    var onClose: () -> Void
    @Environment(\.conversationTheme) private var theme
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: theme.compact ? .bottom : .center) {
                theme.color(SandToken.bgScrim)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)
                sheet
                    .frame(maxWidth: theme.compact ? .infinity : 640)
                    .frame(maxHeight: theme.compact ? geo.size.height * SandMetrics.peerMax : min(640, geo.size.height - 48))
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(theme.text(.peerTitle, ["first": agent.profile.name, "second": peerName]))
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                avatar(agent, size: 30, activity: .idle)
                Text(agent.profile.name).font(.system(size: SandMetrics.fontBase, weight: .semibold))
                Text("⇄").foregroundStyle(theme.color(SandToken.textTertiary))
                avatar(peer, id: blocks.first?.agentId ?? peerName, size: 30, activity: .idle)
                Text(peerName).font(.system(size: SandMetrics.fontBase, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(theme.text(.closePeer))
            }
            .padding(16)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(transcriptRows(blocks.map { .peer($0) }, timestamps: timestamps, language: theme.language)) { row in
                        switch row {
                        case .time(_, let text):
                            Text(text)
                                .font(.system(size: SandMetrics.fontSM))
                                .foregroundStyle(theme.color(SandToken.textTertiary))
                        case .block(.peer(let block)):
                            peerBubble(block)
                        default:
                            EmptyView()
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(maxHeight: theme.compact ? nil : .infinity)
        .background(theme.color(SandToken.bgEditor), in: RoundedRectangle(cornerRadius: SandMetrics.radius3XL))
        .offset(y: theme.compact ? max(drag, 0) : 0)
        .gesture(
            DragGesture().onChanged { value in
                guard theme.compact else { return }
                drag = value.translation.height
            }.onEnded { value in
                guard theme.compact else { return }
                if value.translation.height > 80 { onClose() }
                drag = 0
            }
        )
    }

    private func peerBubble(_ block: PeerBlock) -> some View {
        let outbound = block.direction == "outbound"
        let chat = resolveNunuAppearance(
            agentId: agent.profile.id,
            color: agent.profile.avatarColor,
            shape: agent.profile.avatarShape,
            material: agent.profile.avatarMaterial
        ).chatHex
        return HStack {
            if outbound { Spacer(minLength: 0) }
            Text(block.text)
                .font(.system(size: SandMetrics.fontLG))
                .foregroundStyle(outbound ? theme.color(SandToken.textOnColor) : theme.color(SandToken.textPrimary))
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    outbound ? Color(sand: chat) : theme.color(SandToken.fillBubbleAgent),
                    in: RoundedRectangle(cornerRadius: SandMetrics.radius4XL)
                )
                .frame(maxWidth: 560, alignment: outbound ? .trailing : .leading)
            if !outbound { Spacer(minLength: 0) }
        }
    }

    private func avatar(_ agent: AgentView?, id: String? = nil, size: CGFloat, activity: NunuActivity) -> some View {
        NunuAvatarView(
            agentId: agent?.profile.id ?? id ?? "peer",
            colorId: agent?.profile.avatarColor,
            shapeId: agent?.profile.avatarShape,
            materialId: agent?.profile.avatarMaterial,
            size: size,
            activity: activity
        )
    }
}
#endif
