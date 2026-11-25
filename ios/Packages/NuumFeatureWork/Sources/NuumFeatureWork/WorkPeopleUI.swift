#if canImport(SwiftUI)
import NuumContracts
import SwiftUI

struct ApprovalList: View {
    var approvals: [PendingApproval]
    var members: [AgentView]
    var chrome: WorkChrome
    var decide: (PendingApproval, ToolResolution) async -> Void

    var body: some View {
        if approvals.isEmpty { EmptyView() } else {
            VStack(spacing: pt(WorkMetrics.spacing2)) {
                ForEach(approvals) { approval in
                    ApprovalBar(
                        approval: approval,
                        agentName: memberName(approval.agentId, members: members, language: chrome.language),
                        chrome: chrome,
                        decide: { decide(approval, $0) }
                    )
                }
            }
            .padding(.horizontal, pt(WorkMetrics.spacing4))
            .padding(.vertical, pt(WorkMetrics.spacing2))
        }
    }
}

private struct ApprovalBar: View {
    var approval: PendingApproval
    var agentName: String
    var chrome: WorkChrome
    var decide: (ToolResolution) async -> Void
    @State private var busy = false
    @State private var detailsOpen = false

    var body: some View {
        let action = actionLabel(approval.action, language: chrome.language)
        let title = approval.justification ?? chrome.text("Allow {action}?", ["action": action])
        VStack(alignment: .leading, spacing: pt(WorkMetrics.spacing2)) {
            if chrome.compact {
                Text("\(agentName) · \(title)")
                    .font(.system(size: pt(WorkMetrics.fontBase), weight: .semibold))
                    .foregroundStyle(Color(chrome.palette.textPrimary))
                if approval.action != .runCommand {
                    preview
                }
                Button(chrome.text("Execution details")) { detailsOpen.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: pt(WorkMetrics.fontSM)))
                    .foregroundStyle(Color(chrome.palette.textSecondary))
                if detailsOpen { detailBody }
                buttons
                if let failure = approval.failureMessage {
                    Text(chrome.text(failure))
                        .font(.system(size: pt(WorkMetrics.fontSM)))
                        .foregroundStyle(Color(chrome.palette.textDanger))
                }
            } else {
                HStack(alignment: .center, spacing: pt(WorkMetrics.spacing4)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(agentName) · \(title)")
                            .font(.system(size: pt(WorkMetrics.fontBase), weight: .semibold))
                            .foregroundStyle(Color(chrome.palette.textPrimary))
                        if approval.action != .runCommand { preview }
                        Button(chrome.text("Execution details")) { detailsOpen.toggle() }
                            .buttonStyle(.plain)
                            .font(.system(size: pt(WorkMetrics.fontSM)))
                            .foregroundStyle(Color(chrome.palette.textSecondary))
                        if detailsOpen { detailBody }
                        if let failure = approval.failureMessage {
                            Text(chrome.text(failure))
                                .font(.system(size: pt(WorkMetrics.fontSM)))
                                .foregroundStyle(Color(chrome.palette.textDanger))
                        }
                    }
                    Spacer(minLength: pt(WorkMetrics.spacing2))
                    buttons
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: pt(WorkMetrics.radius2XL), style: .continuous)
                .fill(Color(chrome.palette.elevated))
        )
        .overlay(
            RoundedRectangle(cornerRadius: pt(WorkMetrics.radius2XL), style: .continuous)
                .stroke(Color(chrome.palette.borderSubtle))
        )
    }

    private var preview: some View {
        Text(approval.target.split(whereSeparator: \.isNewline).first.map(String.init) ?? approval.target)
            .font(.system(size: pt(WorkMetrics.fontSM), design: .monospaced))
            .foregroundStyle(Color(chrome.palette.textTertiary))
            .lineLimit(2)
    }

    private var detailBody: some View {
        Text(approval.details ?? approval.target)
            .font(.system(size: pt(WorkMetrics.fontSM), design: .monospaced))
            .foregroundStyle(Color(chrome.palette.textSecondary))
            .textSelection(.enabled)
    }

    private var buttons: some View {
        HStack(spacing: pt(WorkMetrics.spacing1)) {
            decisionButton(chrome.text("Deny"), fill: SandColor(red: 0, green: 0, blue: 0, alpha: 0), text: chrome.palette.textSecondary, pressedFill: chrome.palette.dangerSubtle, pressedText: chrome.palette.textDanger) {
                await decide(.deny)
            }
            decisionButton(chrome.text("Allow once"), fill: chrome.palette.fillSecondary, text: chrome.palette.textPrimary, pressedFill: chrome.palette.fillSecondary, pressedText: chrome.palette.textPrimary) {
                await decide(.once)
            }
            decisionButton(
                chrome.text("Always allow"),
                fill: chrome.palette.fillPrimary,
                text: chrome.palette.textOnPrimary,
                pressedFill: chrome.palette.fillPrimaryHover,
                pressedText: chrome.palette.textOnPrimary,
                enabled: approval.allowAlways && !busy
            ) { await decide(.always) }
        }
        .disabled(busy)
    }

    private func decisionButton(
        _ title: String,
        fill: SandColor,
        text: SandColor,
        pressedFill: SandColor,
        pressedText: SandColor,
        enabled: Bool = true,
        action: @escaping () async -> Void
    ) -> some View {
        Button(action: {
            Task { @MainActor in 
                busy = true
                await action()
                busy = false
            }
        }) {
            Text(title)
                .font(.system(size: pt(WorkMetrics.fontSM), weight: .medium))
                .frame(minHeight: pt(WorkMetrics.spacing11))
                .padding(.horizontal, 10)
        }
        .buttonStyle(WorkFillButtonStyle(idle: fill, pressed: pressedFill, idleText: text, pressedText: pressedText))
        .disabled(!enabled || busy)
        .accessibilityHint(title == chrome.text("Always allow") && !approval.allowAlways ? chrome.text("Dynamic commands require one-time approval") : "")
    }
}

private struct WorkFillButtonStyle: ButtonStyle {
    var idle: SandColor
    var pressed: SandColor
    var idleText: SandColor
    var pressedText: SandColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(configuration.isPressed ? pressedText : idleText))
            .background(
                RoundedRectangle(cornerRadius: pt(WorkMetrics.radiusLG), style: .continuous)
                    .fill(Color(configuration.isPressed ? pressed : idle))
            )
    }
}

struct InterruptionList: View {
    var items: [WorkInterruption]
    var members: [AgentView]
    var chat: [WorkEvent]
    var chrome: WorkChrome
    var resume: (String, Int?) -> Void
    @State private var openEditors: Set<String> = []
    @State private var counts: [String: Int] = [:]

    var body: some View {
        if items.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: pt(WorkMetrics.spacing2)) {
                ForEach(items, id: \.eventId) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line(item))
                            .font(.system(size: pt(WorkMetrics.fontSM)))
                            .foregroundStyle(Color(chrome.palette.textPrimary))
                        HStack {
                            WorkTextButton(title: chrome.text("Continue"), chrome: chrome) {
                                resume(item.eventId, nil)
                            }
                            if item.taskId == nil {
                                Button(chrome.text("Use less room history")) {
                                    if openEditors.contains(item.eventId) {
                                        openEditors.remove(item.eventId)
                                    } else {
                                        openEditors.insert(item.eventId)
                                    }
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: pt(WorkMetrics.fontSM)))
                                .foregroundStyle(Color(chrome.palette.textSecondary))
                                .frame(minHeight: pt(WorkMetrics.spacing11))
                            }
                        }
                        if item.taskId == nil && openEditors.contains(item.eventId) {
                            let maxCount = max(chat.count, 1)
                            let count = counts[item.eventId] ?? maxCount
                            Stepper(value: binding(item.eventId, maxCount: maxCount), in: 1...maxCount) {
                                Text(chrome.text("Only include the most recent messages"))
                                    .font(.system(size: pt(WorkMetrics.fontSM)))
                                    .foregroundStyle(Color(chrome.palette.textSecondary))
                            }
                            Text("\(count)")
                                .font(.system(size: pt(WorkMetrics.fontSM), design: .monospaced))
                                .accessibilityLabel(chrome.text("Only include the most recent messages"))
                            WorkTextButton(title: chrome.text("Continue with this history"), chrome: chrome) {
                                resume(item.eventId, inputAfterSeq(chat: chat, recentCount: count))
                            }
                        }
                    }
                    .padding(pt(WorkMetrics.spacing3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: pt(WorkMetrics.radiusLG)).fill(Color(chrome.palette.elevated)))
                }
            }
            .padding(.horizontal, pt(WorkMetrics.spacing4))
        }
    }

    private func line(_ item: WorkInterruption) -> String {
        let body = presentHostSentence(item.error, language: chrome.language)
        guard let agentId = item.agentId else { return body }
        return memberName(agentId, members: members, language: chrome.language) + ": " + body
    }

    private func binding(_ id: String, maxCount: Int) -> Binding<Int> {
        Binding(
            get: { counts[id] ?? maxCount },
            set: { counts[id] = clampedHistoryCount($0, chatCount: maxCount) }
        )
    }
}

struct WorkChatDockView: View {
    @Binding var dock: WorkChatDockState
    var chat: [WorkEvent]
    var members: [AgentView]
    var room: Bool
    var chrome: WorkChrome
    var post: (String) -> Void
    @State private var message = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if dock.isOpen {
                HStack {
                    Text(chrome.text("Shared room") + " \(chat.count)")
                        .font(.system(size: pt(WorkMetrics.fontSM), weight: .semibold))
                        .foregroundStyle(Color(chrome.palette.textPrimary))
                    Spacer()
                    Button(action: {
                        dock.close()
                        focused = false
                    }) {
                        Image(systemName: "xmark")
                            .frame(width: pt(WorkMetrics.spacing11), height: pt(WorkMetrics.spacing11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(chrome.palette.textSecondary))
                    .accessibilityLabel(chrome.text("Close shared room"))
                }
                .padding(.horizontal, pt(WorkMetrics.spacing4))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: pt(WorkMetrics.spacing2)) {
                        if chat.isEmpty {
                            Text(chrome.text(WorkCopy.noMessages))
                                .font(.system(size: pt(WorkMetrics.fontSM)))
                                .foregroundStyle(Color(chrome.palette.textTertiary))
                        }
                        ForEach(posted, id: \.id) { item in
                            messageRow(item)
                        }
                    }
                    .padding(.horizontal, pt(WorkMetrics.spacing4))
                }
                .accessibilityLabel(chrome.text("Shared room messages"))
            }
            HStack(alignment: .bottom, spacing: pt(WorkMetrics.spacing2)) {
                TextField(chrome.text("Message the Work…"), text: $message, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: pt(WorkMetrics.fontLG)))
                    .foregroundStyle(Color(chrome.palette.textPrimary))
                    .lineLimit(1...4)
                    .focused($focused)
                    .accessibilityLabel(chrome.text("Message the Work"))
                    .onChange(of: focused) { _, isFocused in
                        if isFocused { dock.focusInput() }
                    }
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .frame(width: pt(WorkMetrics.spacing11), height: pt(WorkMetrics.spacing11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(chrome.palette.textOnPrimary))
                .background(Circle().fill(Color(chrome.palette.fillPrimary)))
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(chrome.text("Post message"))
            }
            .padding(pt(WorkMetrics.spacing3))
        }
        .onAppear { dock.roomForcesOpen = room }
        .onChange(of: room) { _, isRoom in dock.roomForcesOpen = isRoom }
    }

    private var posted: [(id: String, user: Bool, author: String?, text: String)] {
        chat.compactMap { event in
            guard case .chatPosted(let body) = event.body else { return nil }
            if case .user = event.actor {
                return (event.id, true, nil, body.body)
            }
            let name = members.first { $0.profile.id == event.actor.id }?.profile.name
                ?? chrome.text("Agent")
            return (event.id, false, name, body.body)
        }
    }

    @ViewBuilder
    private func messageRow(_ item: (id: String, user: Bool, author: String?, text: String)) -> some View {
        HStack {
            if item.user { Spacer(minLength: 24) }
            VStack(alignment: item.user ? .trailing : .leading, spacing: 2) {
                if let author = item.author, !item.user {
                    Text(author)
                        .font(.system(size: pt(WorkMetrics.fontXS), weight: .semibold))
                        .foregroundStyle(Color(chrome.palette.textSecondary))
                }
                if item.user {
                    Text(item.text)
                        .font(.system(size: pt(WorkMetrics.fontLG)))
                        .foregroundStyle(Color(chrome.palette.textOnColor))
                        .padding(pt(WorkMetrics.spacing3))
                        .background(
                            RoundedRectangle(cornerRadius: pt(WorkMetrics.radius4XL), style: .continuous)
                                .fill(Color(chrome.palette.bubbleUser))
                        )
                } else {
                    Text(markdown(item.text))
                        .font(.system(size: pt(WorkMetrics.fontLG)))
                        .foregroundStyle(Color(chrome.palette.textPrimary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !item.user { Spacer(minLength: 24) }
        }
    }

    private func markdown(_ body: String) -> AttributedString {
        (try? AttributedString(markdown: body, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)))
            ?? AttributedString(body)
    }

    private func send() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        post(trimmed)
        message = ""
    }
}

struct CapabilitySection: View {
    var catalog: WorkCatalog
    var chrome: WorkChrome
    var onAdd: () -> Void
    var onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: pt(WorkMetrics.spacing2)) {
            HStack {
                Text(chrome.text("Capabilities") + " \(catalog.entries.count)")
                    .font(.system(size: pt(WorkMetrics.fontSM), weight: .semibold))
                    .foregroundStyle(Color(chrome.palette.textPrimary))
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: pt(WorkMetrics.spacing11), height: pt(WorkMetrics.spacing11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(chrome.palette.textPrimary))
                .accessibilityLabel(chrome.text("Add capability"))
            }
            ForEach(catalog.entries, id: \.id) { entry in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: pt(WorkMetrics.fontSM), weight: .semibold))
                            .foregroundStyle(Color(chrome.palette.textPrimary))
                        Text(chrome.text(kindKey(entry)))
                            .font(.system(size: pt(WorkMetrics.fontXS)))
                            .foregroundStyle(Color(chrome.palette.textTertiary))
                    }
                    Spacer()
                    Button(action: { onRemove(entry.id) }) {
                        Image(systemName: "xmark")
                            .frame(width: pt(WorkMetrics.spacing11), height: pt(WorkMetrics.spacing11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(chrome.palette.textSecondary))
                    .accessibilityLabel(chrome.text("Remove {name}", ["name": entry.name]))
                }
            }
        }
        .padding(pt(WorkMetrics.spacing3))
    }

    private func kindKey(_ entry: WorkCatalogEntry) -> String {
        switch entry {
        case .skill: "Skill"
        case .localTool: "Local tool"
        case .cli: "CLI"
        case .knowledge: "Knowledge"
        }
    }
}

struct MemberSection: View {
    var workId: String
    var members: [AgentView]
    var snapshot: WorkSnapshot
    var pending: Set<String>
    var hovering: Bool
    var dragging: Bool
    var chrome: WorkChrome
    var onDetach: (String, Int) -> Void
    var onDrag: (Bool) -> Void
    @State private var statusId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: pt(WorkMetrics.spacing2)) {
            Text(chrome.text("Agents") + " \(members.count)")
                .font(.system(size: pt(WorkMetrics.fontSM), weight: .semibold))
                .foregroundStyle(Color(chrome.palette.textPrimary))
            if members.isEmpty && !hovering && !dragging {
                Text(chrome.text("拖到此处以添加Nunu到当前NunuBar"))
                    .font(.system(size: pt(WorkMetrics.fontSM)))
                    .foregroundStyle(Color(chrome.palette.textTertiary))
            }
            if hovering {
                Text(chrome.text("Release to add Agent"))
                    .font(.system(size: pt(WorkMetrics.fontSM)))
                    .foregroundStyle(Color(chrome.palette.textPrimary))
            }
            if dragging {
                Text(chrome.text("Drop outside to remove"))
                    .font(.system(size: pt(WorkMetrics.fontSM)))
                    .foregroundStyle(Color(chrome.palette.textSecondary))
            }
            ForEach(members, id: \.profile.id) { member in
                memberRow(member)
            }
        }
        .padding(pt(WorkMetrics.spacing3))
    }

    private func memberRow(_ member: AgentView) -> some View {
        let activity = memberActivity(member, snapshot: snapshot)
        let state = avatarState(agent: member, pendingApproval: pending.contains(member.profile.id))
        return HStack(spacing: pt(WorkMetrics.spacing2)) {
            Button(action: {
                statusId = statusId == member.profile.id ? nil : member.profile.id
            }) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color(chrome.palette.fillSecondary))
                        .frame(width: pt(WorkMetrics.avatarMember), height: pt(WorkMetrics.avatarMember))
                        .overlay(Text(String(member.profile.name.prefix(1))).font(.system(size: 13, weight: .semibold)))
                    Circle()
                        .fill(Color(dot(state)))
                        .frame(width: 8, height: 8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chrome.text("Status of {name}", ["name": member.profile.name]))
            VStack(alignment: .leading, spacing: 2) {
                Text(member.profile.name)
                    .font(.system(size: pt(WorkMetrics.fontSM), weight: .semibold))
                    .foregroundStyle(Color(chrome.palette.textPrimary))
                if statusId == member.profile.id {
                    Text(activitySentence(activity, language: chrome.language))
                        .font(.system(size: pt(WorkMetrics.fontXS)))
                        .foregroundStyle(Color(chrome.palette.textSecondary))
                        .accessibilityLabel(chrome.text("Status of {name}", ["name": member.profile.name]))
                }
            }
            Spacer()
            Button(action: { onDetach(member.profile.id, membershipRevision(member, workId: workId)) }) {
                Image(systemName: "xmark")
                    .frame(width: pt(WorkMetrics.spacing11), height: pt(WorkMetrics.spacing11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(chrome.palette.textSecondary))
            .accessibilityLabel(chrome.text("Remove {name}", ["name": member.profile.name]))
        }
        .draggable(WorkDrag.payload(agentId: member.profile.id))
        .gesture(
            LongPressGesture(minimumDuration: 0.35).sequenced(before: DragGesture(minimumDistance: 12))
                .onChanged { value in
                    if case .second(true, .some) = value { onDrag(true) }
                }
                .onEnded { value in
                    onDrag(false)
                    guard case .second(true, let drag?) = value else { return }
                    if abs(drag.translation.width) > 28 || abs(drag.translation.height) > 28 {
                        onDetach(member.profile.id, membershipRevision(member, workId: workId))
                    }
                }
        )
    }

    private func dot(_ state: WorkAvatarState) -> SandColor {
        switch state {
        case .waiting: chrome.palette.fillWarning
        case .error: chrome.palette.fillDanger
        case .working: chrome.palette.fillAccent
        case .idle: SandColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
    }
}

struct CatalogDialog: View {
    @Binding var draft: CatalogDraft
    var chrome: WorkChrome
    var onClose: () -> Void
    var submit: (WorkCatalogInput) async -> WorkNotice?
    var browse: () async -> DirectoryPick

    var body: some View {
        ZStack {
            Color(chrome.palette.scrim).ignoresSafeArea().onTapGesture(perform: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: pt(WorkMetrics.spacing3)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chrome.text("Capabilities"))
                                .font(.system(size: pt(WorkMetrics.fontLG), weight: .semibold))
                                .foregroundStyle(Color(chrome.palette.textPrimary))
                            Text(chrome.text("Skills, tools and knowledge for this Work."))
                                .font(.system(size: pt(WorkMetrics.fontSM)))
                                .foregroundStyle(Color(chrome.palette.textSecondary))
                        }
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark").frame(width: pt(WorkMetrics.spacing11), height: pt(WorkMetrics.spacing11))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(chrome.text("Close dialog"))
                    }
                    HStack {
                        pageButton(.discover, chrome.text("Discover"))
                        pageButton(.local, chrome.text("Import local"))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(chrome.text("Capability source"))
                    if draft.page == .discover {
                        discover
                    } else {
                        localForm
                    }
                }
                .padding(pt(WorkMetrics.spacing4))
            }
            .frame(maxWidth: 520, maxHeight: 640)
            .background(RoundedRectangle(cornerRadius: pt(WorkMetrics.radius2XL)).fill(Color(chrome.palette.elevated)))
            .padding(pt(WorkMetrics.spacing4))
        }
    }

    private var discover: some View {
        VStack(alignment: .leading, spacing: pt(WorkMetrics.spacing3)) {
            HStack {
                Text(chrome.text("THE COLLECTION"))
                    .font(.system(size: pt(WorkMetrics.fontXS), weight: .semibold))
                    .foregroundStyle(Color(chrome.palette.textTertiary))
                Text(chrome.text("Coming soon"))
                    .font(.system(size: pt(WorkMetrics.fontXS)))
                    .foregroundStyle(Color(chrome.palette.textSecondary))
            }
            ForEach(discoverCards(language: chrome.language), id: \.title) { card in
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.eyebrow).font(.system(size: pt(WorkMetrics.fontXS))).foregroundStyle(Color(chrome.palette.textTertiary))
                    Text(card.title).font(.system(size: pt(WorkMetrics.fontBase), weight: .semibold)).foregroundStyle(Color(chrome.palette.textPrimary))
                    Text(card.body).font(.system(size: pt(WorkMetrics.fontSM))).foregroundStyle(Color(chrome.palette.textSecondary))
                    Text(card.badge).font(.system(size: pt(WorkMetrics.fontXS))).foregroundStyle(Color(chrome.palette.textTertiary))
                }
                .padding(pt(WorkMetrics.spacing3))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: pt(WorkMetrics.radiusLG)).stroke(Color(chrome.palette.edge)))
                .accessibilityElement(children: .combine)
            }
            Button(action: { draft.selectPage(.local) }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chrome.text("Already have something in mind?"))
                        .font(.system(size: pt(WorkMetrics.fontSM), weight: .semibold))
                    Text(chrome.text("Bring a local Skill, CLI or knowledge folder."))
                        .font(.system(size: pt(WorkMetrics.fontXS)))
                    Text(chrome.text("Import local"))
                        .font(.system(size: pt(WorkMetrics.fontSM), weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: pt(WorkMetrics.spacing11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(chrome.palette.textPrimary))
        }
    }

    private var localForm: some View {
        VStack(alignment: .leading, spacing: pt(WorkMetrics.spacing2)) {
            HStack {
                ForEach(CatalogKind.allCases, id: \.rawValue) { kind in
                    WorkTextButton(
                        title: chrome.text(kind.labelKey),
                        chrome: chrome,
                        primary: draft.kind == kind,
                        enabled: !draft.importing,
                        selected: draft.kind == kind,
                        identifier: "work-catalog-kind-\(kind.rawValue)"
                    ) { draft.selectKind(kind) }
                }
            }
            Text(chrome.text("Name")).font(.system(size: pt(WorkMetrics.fontXS))).foregroundStyle(Color(chrome.palette.textSecondary))
            TextField(chrome.text(draft.kind == .skill ? "e.g. Design review" : "A short, recognizable name"), text: $draft.name)
                .textFieldStyle(.plain)
                .font(.system(size: pt(WorkMetrics.fontBase)))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(chrome.palette.editor)))
                .accessibilityIdentifier("work-catalog-name")
                .disabled(draft.importing)
            Text(chrome.text(pathLabel)).font(.system(size: pt(WorkMetrics.fontXS))).foregroundStyle(Color(chrome.palette.textSecondary))
            HStack {
                TextField(chrome.text(pathPlaceholder), text: $draft.path)
                    .textFieldStyle(.plain)
                    .font(.system(size: pt(WorkMetrics.fontSM), design: .monospaced))
                    .padding(8)
                    .accessibilityIdentifier("work-catalog-path")
                    .disabled(draft.importing)
                if draft.kind.showsBrowse {
                    WorkTextButton(title: chrome.text("Browse"), chrome: chrome, enabled: !draft.importing) {
                        Task { @MainActor in 
                            let picked = await browse()
                            if case .path(let directory) = picked {
                                let applied = applyPickedDirectory(kind: draft.kind, directory: directory, name: draft.name)
                                draft.name = applied.name
                                draft.path = applied.path
                                draft.errorKey = nil
                            } else if case .failed(let notice) = picked {
                                draft.errorKey = notice.message
                            }
                        }
                    }
                }
            }
            if draft.kind == .cli {
                Text(chrome.text("Allowed subcommands")).font(.system(size: pt(WorkMetrics.fontXS))).foregroundStyle(Color(chrome.palette.textSecondary))
                TextField(chrome.text("e.g. status, diff, log"), text: $draft.commands)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .accessibilityIdentifier("work-catalog-commands")
                    .disabled(draft.importing)
            }
            Text(chrome.text(noteKey))
                .font(.system(size: pt(WorkMetrics.fontXS)))
                .foregroundStyle(Color(chrome.palette.textSecondary))
            if let error = draft.errorKey {
                Text(chrome.text(error))
                    .font(.system(size: pt(WorkMetrics.fontSM)))
                    .foregroundStyle(Color(chrome.palette.textDanger))
            }
            WorkTextButton(
                title: chrome.text(draft.importing ? "Importing…" : "Add to Work"),
                chrome: chrome,
                primary: true,
                enabled: draft.canSubmit,
                identifier: "work-catalog-submit"
            ) {
                switch draft.build() {
                case .incomplete:
                    break
                case .missingToolName:
                    draft.errorKey = WorkCopy.enterToolName
                case .input(let entry):
                    draft.importing = true
                    draft.errorKey = nil
                    Task { @MainActor in 
                        let notice = await submit(entry)
                        draft.importing = false
                        if let notice {
                            draft.errorKey = notice.message
                        } else {
                            onClose()
                        }
                    }
                }
            }
        }
    }

    private var pathLabel: String {
        switch draft.kind {
        case .skill: "Skill manifest"
        case .cli: "Executable"
        case .knowledge: "Knowledge folder"
        case .localTool: "Tool names"
        }
    }

    private var pathPlaceholder: String {
        switch draft.kind {
        case .skill: "/path/to/skill/SKILL.md"
        case .cli: "/path/to/executable"
        case .knowledge: "/path/to/knowledge"
        case .localTool: "Tool names, separated by commas"
        }
    }

    private var noteKey: String {
        switch draft.kind {
        case .knowledge: "Agents can read this folder. The source files stay in place."
        case .skill: "Choose the folder containing SKILL.md, or enter its full path."
        case .cli: "Use an installed executable. List the subcommands this Work can use."
        case .localTool: "Add tools already registered in Nuum."
        }
    }

    private func pageButton(_ page: CatalogPage, _ title: String) -> some View {
        WorkTextButton(title: title, chrome: chrome, primary: draft.page == page, selected: draft.page == page) {
            draft.selectPage(page)
        }
    }
}

struct TaskDetailDialog: View {
    var view: WorkTaskView
    var members: [AgentView]
    var workId: String
    var chrome: WorkChrome
    var notice: WorkNotice?
    var onClose: () -> Void
    var transition: (WorkTask, WorkTaskState) async -> WorkNotice?
    var dispatch: (String, String, String) async -> WorkNotice?
    var trace: (String, String?, Int?) async throws -> TranscriptPage

    @State private var workerId = ""
    @State private var instruction = ""
    @State private var localNotice: WorkNotice?
    @State private var traceOpen = false
    @State private var traceHold: TraceHold?
    @State private var expanded: Set<String> = []

    private var task: WorkTask { view.task }
    private var shownNotice: WorkNotice? { localNotice ?? notice }

    var body: some View {
        ZStack {
            Color(chrome.palette.scrim).ignoresSafeArea().onTapGesture(perform: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: pt(WorkMetrics.spacing3)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.system(size: pt(WorkMetrics.fontLG), weight: .semibold))
                                .foregroundStyle(Color(chrome.palette.textPrimary))
                            Text(chrome.text(laneTitleKey(task.state)))
                                .font(.system(size: pt(WorkMetrics.fontSM)))
                                .foregroundStyle(Color(chrome.palette.textSecondary))
                        }
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark").frame(width: pt(WorkMetrics.spacing11), height: pt(WorkMetrics.spacing11))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(chrome.text("Close dialog"))
                    }
                    if !task.description.isEmpty {
                        Text(task.description)
                            .font(.system(size: pt(WorkMetrics.fontBase)))
                            .foregroundStyle(Color(chrome.palette.textPrimary))
                    }
                    labeled("Card owner", ownerText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chrome.text("Workers")).font(.system(size: pt(WorkMetrics.fontXS))).foregroundStyle(Color(chrome.palette.textSecondary))
                        if task.assigneeIds.isEmpty {
                            Text(chrome.text("Unassigned")).font(.system(size: pt(WorkMetrics.fontSM)))
                        } else {
                            ForEach(task.assigneeIds, id: \.self) { id in
                                HStack {
                                    Circle().fill(Color(chrome.palette.fillSecondary)).frame(width: pt(WorkMetrics.avatarWorker), height: pt(WorkMetrics.avatarWorker))
                                    Text(memberName(id, members: members, language: chrome.language))
                                        .font(.system(size: pt(WorkMetrics.fontSM)))
                                }
                            }
                        }
                    }
                    labeled("Priority", priorityLabel(task.priority, language: chrome.language))
                    if !task.acceptanceCriteria.isEmpty {
                        Text(chrome.text("Acceptance criteria")).font(.system(size: pt(WorkMetrics.fontXS), weight: .semibold))
                        ForEach(task.acceptanceCriteria, id: \.self) { item in
                            Text("• " + item).font(.system(size: pt(WorkMetrics.fontSM)))
                        }
                    }
                    if let blocker = task.blocker {
                        Text(chrome.text("Blocked:") + " " + blocker.reason)
                            .font(.system(size: pt(WorkMetrics.fontSM)))
                            .foregroundStyle(Color(chrome.palette.textWarning))
                    }
                    if !task.deliverables.isEmpty {
                        Text(chrome.text("产物")).font(.system(size: pt(WorkMetrics.fontXS), weight: .semibold))
                        ForEach(task.deliverables, id: \.id) { file in
                            VStack(alignment: .leading) {
                                Text(file.name).font(.system(size: pt(WorkMetrics.fontSM), weight: .semibold))
                                Text(file.uri).font(.system(size: pt(WorkMetrics.fontXS), design: .monospaced)).textSelection(.enabled)
                            }
                        }
                    }
                    if task.state == .blocked {
                        Text(chrome.text("This card is paused until you confirm how to proceed."))
                            .font(.system(size: pt(WorkMetrics.fontSM)))
                            .foregroundStyle(Color(chrome.palette.textSecondary))
                    }
                    ForEach(taskDetailActions(task.state), id: \.rawValue) { action in
                        actionButton(action)
                    }
                    if let shownNotice {
                        Text(chrome.text(shownNotice.message))
                            .font(.system(size: pt(WorkMetrics.fontSM)))
                            .foregroundStyle(Color(chrome.palette.textDanger))
                    }
                    Button(chrome.text("Execution history")) { traceOpen.toggle(); if traceOpen { Task { @MainActor in  await loadTrace(nil) } } }
                        .buttonStyle(.plain)
                        .font(.system(size: pt(WorkMetrics.fontSM), weight: .semibold))
                        .frame(minHeight: pt(WorkMetrics.spacing11))
                    if traceOpen { traceBody }
                }
                .padding(pt(WorkMetrics.spacing4))
            }
            .frame(maxWidth: 560, maxHeight: 720)
            .background(RoundedRectangle(cornerRadius: pt(WorkMetrics.radius2XL)).fill(Color(chrome.palette.elevated)))
            .padding(pt(WorkMetrics.spacing4))
        }
    }

    private var ownerText: String {
        guard let id = task.ownerAgentId else { return chrome.text("Unassigned") }
        return memberName(id, members: members, language: chrome.language)
    }

    private func labeled(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chrome.text(key)).font(.system(size: pt(WorkMetrics.fontXS))).foregroundStyle(Color(chrome.palette.textSecondary))
            Text(value).font(.system(size: pt(WorkMetrics.fontSM))).foregroundStyle(Color(chrome.palette.textPrimary))
        }
    }

    @ViewBuilder
    private func actionButton(_ action: TaskDetailAction) -> some View {
        if action == .dispatch {
            let workers = members.filter { canDispatch($0, workId: workId) }
            Picker(chrome.text("Choose worker"), selection: $workerId) {
                Text(chrome.text("Choose worker")).tag("")
                ForEach(workers, id: \.profile.id) { member in
                    Text(member.profile.name).tag(member.profile.id)
                }
            }
            .accessibilityLabel(chrome.text("Choose worker"))
            TextField(chrome.text("Instruction for the Agent"), text: $instruction, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(chrome.palette.editor)))
            WorkTextButton(
                title: chrome.text("Run"),
                chrome: chrome,
                primary: true,
                enabled: !workerId.isEmpty && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                Task { @MainActor in 
                    localNotice = await dispatch(workerId, task.id, instruction)
                }
            }
        } else if let destination = action.destination {
            WorkTextButton(title: chrome.text(action.labelKey), chrome: chrome) {
                Task { @MainActor in  localNotice = await transition(task, destination) }
            }
        }
    }

    @ViewBuilder
    private var traceBody: some View {
        if let hold = traceHold {
            Picker(chrome.text("Execution history"), selection: Binding(get: { hold.sessionId }, set: { value in
                Task { @MainActor in  await loadTrace(value) }
            })) {
                Text(hold.sessionId).tag(hold.sessionId)
            }
            .accessibilityLabel(chrome.text("Execution history"))
            if hold.entries.isEmpty {
                Text(chrome.text("No execution history yet."))
                    .font(.system(size: pt(WorkMetrics.fontSM)))
                    .foregroundStyle(Color(chrome.palette.textTertiary))
            }
            ForEach(hold.entries, id: \.id) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Button("\(event.seq) \(event.type)") {
                        if expanded.contains(event.id) { expanded.remove(event.id) } else { expanded.insert(event.id) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: pt(WorkMetrics.fontXS), design: .monospaced))
                    if expanded.contains(event.id) {
                        Text(traceText(event))
                            .font(.system(size: pt(WorkMetrics.fontXS), design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            if hold.nextBeforeSeq != nil {
                Button(chrome.text("Load earlier")) { Task { @MainActor in  await loadEarlier() } }
                    .buttonStyle(.plain)
                    .frame(minHeight: pt(WorkMetrics.spacing11))
            }
        } else {
            Text(chrome.text("No execution history yet."))
                .font(.system(size: pt(WorkMetrics.fontSM)))
                .foregroundStyle(Color(chrome.palette.textTertiary))
        }
    }

    private func loadTrace(_ sessionId: String?) async {
        do {
            let page = try await trace(task.id, sessionId, nil)
            traceHold = TraceHold(sessionId: page.id, entries: page.entries, nextBeforeSeq: page.nextBeforeSeq)
        } catch is CancellationError {
            return
        } catch {
            localNotice = workNotice(from: error)
        }
    }

    private func loadEarlier() async {
        guard let hold = traceHold, let before = hold.nextBeforeSeq else { return }
        do {
            let page = try await trace(task.id, hold.sessionId, before)
            let known = Set(hold.entries.map(\.id))
            let older = page.entries.filter { !known.contains($0.id) }
            traceHold = TraceHold(sessionId: hold.sessionId, entries: older + hold.entries, nextBeforeSeq: page.nextBeforeSeq)
        } catch is CancellationError {
            return
        } catch {
            localNotice = workNotice(from: error)
        }
    }
}

private struct TraceHold {
    var sessionId: String
    var entries: [TranscriptEvent]
    var nextBeforeSeq: Int?
}
#endif
