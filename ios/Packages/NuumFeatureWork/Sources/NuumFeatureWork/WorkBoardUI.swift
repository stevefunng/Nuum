#if canImport(SwiftUI)
import NuumContracts
import SwiftUI

struct WorkBoardColumn: View {
    var workId: String
    @ObservedObject var model: WorkScreenModel
    var chrome: WorkChrome
    var fallbackTitle: String
    var columnWidth: Double
    var onBack: (() -> Void)?

    @State private var page = WorkBoardPage.tasks
    @State private var catalogOpen = false
    @State private var selectedTaskId: String?
    @State private var chat = WorkChatDockState(roomForcesOpen: false)
    @State private var draft = CatalogDraft()
    @State private var detailNotice: WorkNotice?
    @State private var inspectorWidth = InspectorPreference.standard.width
    @State private var inspectorSplit = InspectorPreference.standard.split
    @State private var hoveringMembers = false
    @State private var draggingMember = false

    var body: some View {
        let surface = workSurface(state: model.state, language: chrome.language, fallbackTitle: fallbackTitle, page: page)
        let snapshot = model.state.snapshot
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                header(surface: surface, snapshot: snapshot)
                if surface.waitingCaption {
                    Text(chrome.text(WorkCopy.waitingForApproval))
                        .font(.system(size: pt(WorkMetrics.fontXS)))
                        .foregroundStyle(Color(chrome.palette.textTertiary))
                        .padding(.horizontal, pt(WorkMetrics.spacing4))
                }
                ApprovalList(approvals: model.state.approvals, members: snapshot?.members ?? [], chrome: chrome) { approval, resolution in
                    await model.decide(approval, resolution)
                }
                if let notice = model.state.notice {
                    Text(chrome.text(notice.message))
                        .font(.system(size: pt(WorkMetrics.fontSM)))
                        .foregroundStyle(Color(chrome.palette.textDanger))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, pt(WorkMetrics.spacing4))
                        .padding(.vertical, pt(WorkMetrics.spacing1))
                }
                if snapshot == nil {
                    Spacer()
                    WorkTextButton(
                        title: chrome.text(WorkCopy.enableTaskBoard),
                        chrome: chrome,
                        enabled: false,
                        identifier: "work-upgrade"
                    ) {}
                    .padding(.horizontal, pt(WorkMetrics.spacing4))
                } else if chrome.compact {
                    column(snapshot: snapshot, surface: surface)
                    people(snapshot: snapshot)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        column(snapshot: snapshot, surface: surface)
                        inspector(snapshot: snapshot)
                    }
                }
            }
            if catalogOpen, snapshot != nil {
                CatalogDialog(draft: $draft, chrome: chrome, onClose: { catalogOpen = false }) { entry in
                    await model.addCatalog(entry)
                } browse: {
                    await model.pickDirectory()
                }
            }
            if let snapshot, let selected = snapshot.tasks.first(where: { $0.task.id == selectedTaskId }) {
                TaskDetailDialog(
                    view: selected,
                    members: snapshot.members,
                    workId: snapshot.profile.id,
                    chrome: chrome,
                    notice: detailNotice,
                    onClose: { selectedTaskId = nil; detailNotice = nil }
                ) { task, destination in
                    detailNotice = await model.transition(task: task, to: destination)
                } dispatch: { agentId, taskId, instruction in
                    detailNotice = await model.dispatch(agentId: agentId, taskId: taskId, instruction: instruction)
                } trace: { taskId, sessionId, before in
                    try await model.loadTrace(taskId: taskId, sessionId: sessionId, beforeSeq: before)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(chrome.palette.editor))
        .onChange(of: snapshot?.profile.kind) { _, kind in
            chat.roomForcesOpen = kind == .room
        }
        .onAppear {
            chat.roomForcesOpen = snapshot?.profile.kind == .room
            let defaults = UserDefaults(suiteName: WorkInspectorLayout.suiteName) ?? .standard
            let saved = WorkInspectorLayout.read(defaults)
            inspectorWidth = saved.width
            inspectorSplit = saved.split
        }
    }

    private func header(surface: WorkSurface, snapshot: WorkSnapshot?) -> some View {
        HStack(spacing: pt(WorkMetrics.spacing2)) {
            if chrome.compact {
                Button(action: { onBack?() }) {
                    Text(chrome.text("Agents"))
                        .font(.system(size: pt(WorkMetrics.fontBase), weight: .semibold))
                        .frame(minWidth: pt(WorkMetrics.spacing11), minHeight: pt(WorkMetrics.spacing11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(chrome.palette.textPrimary))
                .accessibilityLabel(chrome.text("Agents"))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(surface.title)
                    .font(.system(size: pt(WorkMetrics.fontLG), weight: .semibold))
                    .foregroundStyle(Color(chrome.palette.textPrimary))
                    .lineLimit(1)
            }
            Spacer()
            if surface.showsStop {
                WorkTextButton(title: chrome.text(WorkCopy.stopDiscussion), chrome: chrome) {
                    Task { @MainActor in  await model.stopDiscussion() }
                }
            }
            if surface.showsBlockedCount {
                Text("\(surface.blockedCount) \(chrome.text("Blocked"))")
                    .font(.system(size: pt(WorkMetrics.fontBase)))
                    .foregroundStyle(Color(chrome.palette.textWarning))
            }
        }
        .frame(minHeight: pt(WorkMetrics.spacing14))
        .padding(.horizontal, pt(WorkMetrics.spacing2))
    }

    @ViewBuilder
    private func column(snapshot: WorkSnapshot, surface: WorkSurface) -> some View {
        VStack(alignment: .leading, spacing: pt(WorkMetrics.spacing2)) {
            if snapshot.profile.kind == .room {
                HStack {
                    Text(chrome.text("Local room"))
                        .font(.system(size: pt(WorkMetrics.fontBase), weight: .semibold))
                        .foregroundStyle(Color(chrome.palette.textPrimary))
                    Spacer()
                    WorkTextButton(
                        title: chrome.text(WorkCopy.enableTaskBoard),
                        chrome: chrome,
                        enabled: true,
                        identifier: "work-upgrade"
                    ) { Task { @MainActor in  await model.upgrade() } }
                }
                .padding(.horizontal, pt(WorkMetrics.spacing4))
            } else if snapshot.profile.kind == .work {
                PageSwitch(page: page, chrome: chrome) {
                    withAnimation(chrome.motion) { page.toggle() }
                }
                .disabled(!surface.showsLanes && model.state.loading)
                ZStack {
                    laneBoard(snapshot: snapshot)
                        .opacity(page == .tasks ? 1 : 0)
                        .accessibilityHidden(page != .tasks)
                        .allowsHitTesting(page == .tasks)
                    DeliverablePage(tasks: snapshot.tasks, members: snapshot.members, chrome: chrome) { id in
                        selectedTaskId = id
                    }
                    .opacity(page == .deliverables ? 1 : 0)
                    .accessibilityHidden(page != .deliverables)
                    .allowsHitTesting(page == .deliverables)
                }
            }
            InterruptionList(items: snapshot.interruptions, members: snapshot.members, chat: snapshot.chat, chrome: chrome) { eventId, after in
                Task { @MainActor in  await model.continueDiscussion(eventId: eventId, inputAfterSeq: after) }
            }
            WorkChatDockView(
                dock: $chat,
                chat: snapshot.chat,
                members: snapshot.members,
                room: snapshot.profile.kind == .room,
                chrome: chrome
            ) { body in
                Task { @MainActor in  await model.post(body) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func laneBoard(snapshot: WorkSnapshot) -> some View {
        let lanes = workLanes(snapshot.tasks)
        return VStack(spacing: pt(WorkMetrics.spacing2)) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: pt(WorkMetrics.laneGap)) {
                        ForEach(lanes, id: \.state.rawValue) { lane in
                            LaneColumn(lane: lane, members: snapshot.members, chrome: chrome) { id in
                                selectedTaskId = id
                            }
                            .id(lane.state.rawValue)
                        }
                    }
                    .padding(.horizontal, pt(WorkMetrics.spacing6))
                }
                LanePager(lanes: lanes, chrome: chrome) { state in
                    let scroll = {
                        proxy.scrollTo(state.rawValue, anchor: .leading)
                    }
                    if chrome.reduceMotion {
                        scroll()
                    } else {
                        withAnimation(.easeOut(duration: WorkMetrics.durationNormal)) { scroll() }
                    }
                }
            }
        }
    }

    private func people(snapshot: WorkSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CapabilitySection(catalog: snapshot.catalog, chrome: chrome, onAdd: { catalogOpen = true }) { id in
                Task { @MainActor in  await model.removeCatalog(entryId: id) }
            }
            MemberSection(
                workId: snapshot.profile.id,
                members: snapshot.members,
                snapshot: snapshot,
                pending: Set(model.state.approvals.map(\.agentId)),
                hovering: hoveringMembers,
                dragging: draggingMember,
                chrome: chrome,
                onDetach: { id, revision in Task { @MainActor in  await model.detach(agentId: id, revision: revision) } },
                onDrag: { draggingMember = $0 }
            )
            .dropDestination(for: String.self, action: { items, _ in
                guard let id = items.first.flatMap(WorkDrag.agentId) else { return false }
                Task { @MainActor in  await model.attach(agentId: id) }
                return true
            }, isTargeted: $hoveringMembers)
        }
    }

    private func inspector(snapshot: WorkSnapshot) -> some View {
        let width = WorkInspectorLayout.project(
            preference: InspectorPreference(width: inspectorWidth, split: inspectorSplit),
            columnWidth: columnWidth
        )
        return HStack(spacing: 0) {
            Rectangle()
                .fill(Color(chrome.palette.edge))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 8)
                .frame(width: 20)
                .contentShape(Rectangle())
                .gesture(DragGesture().onChanged { value in
                    inspectorWidth = width - value.translation.width
                }.onEnded { _ in
                    persistInspector()
                })
                .accessibilityLabel(chrome.text("Resize Work inspector"))
            VStack(spacing: 0) {
                CapabilitySection(catalog: snapshot.catalog, chrome: chrome, onAdd: { catalogOpen = true }) { id in
                    Task { @MainActor in  await model.removeCatalog(entryId: id) }
                }
                .frame(maxHeight: .infinity)
                Rectangle()
                    .fill(Color(chrome.palette.edge))
                    .frame(height: 1)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { value in
                        let height = max(columnWidth, 1)
                        inspectorSplit = min(1, max(0, inspectorSplit + value.translation.height / height))
                    }.onEnded { _ in persistInspector() })
                    .accessibilityLabel(chrome.text("Resize capabilities and agents"))
                MemberSection(
                    workId: snapshot.profile.id,
                    members: snapshot.members,
                    snapshot: snapshot,
                    pending: Set(model.state.approvals.map(\.agentId)),
                    hovering: hoveringMembers,
                    dragging: draggingMember,
                    chrome: chrome,
                    onDetach: { id, revision in Task { @MainActor in  await model.detach(agentId: id, revision: revision) } },
                    onDrag: { draggingMember = $0 }
                )
                .frame(maxHeight: .infinity)
                .dropDestination(for: String.self, action: { items, _ in
                    guard let id = items.first.flatMap(WorkDrag.agentId) else { return false }
                    Task { @MainActor in  await model.attach(agentId: id) }
                    return true
                }, isTargeted: $hoveringMembers)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(chrome.palette.editor))
        }
        .frame(width: pt(width))
    }

    private func persistInspector() {
        let defaults = UserDefaults(suiteName: WorkInspectorLayout.suiteName) ?? .standard
        WorkInspectorLayout.write(InspectorPreference(width: inspectorWidth, split: inspectorSplit), defaults)
    }
}

private struct PageSwitch: View {
    var page: WorkBoardPage
    var chrome: WorkChrome
    var toggle: () -> Void

    var body: some View {
        let label = chrome.text(page == .tasks ? "切换到产物" : "切换到 Tasks")
        Button(action: toggle) {
            HStack(spacing: pt(WorkMetrics.spacing3)) {
                Text(chrome.text(page == .tasks ? "Tasks" : "产物"))
                    .font(.system(size: pt(WorkMetrics.fontBase), weight: .semibold))
                    .foregroundStyle(Color(chrome.palette.textPrimary))
                Text(chrome.text(page == .tasks ? "产物" : "Tasks"))
                    .font(.system(size: pt(WorkMetrics.fontBase)))
                    .foregroundStyle(Color(chrome.palette.textTertiary))
            }
            .frame(minHeight: pt(WorkMetrics.spacing11))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, pt(WorkMetrics.spacing4))
        .accessibilityLabel(label)
        .accessibilityIdentifier("work-page-switch")
    }
}

private struct LaneColumn: View {
    var lane: WorkLane
    var members: [AgentView]
    var chrome: WorkChrome
    var open: (String) -> Void

    var body: some View {
        let title = chrome.text(lane.titleKey)
        VStack(alignment: .leading, spacing: pt(WorkMetrics.spacing2)) {
            HStack(spacing: 6) {
                Circle()
                    .strokeBorder(Color(dotStroke), lineWidth: 1.5)
                    .background(Circle().fill(Color(dotFill)))
                    .frame(width: pt(WorkMetrics.dot), height: pt(WorkMetrics.dot))
                Text(title)
                    .font(.system(size: pt(WorkMetrics.fontSM), weight: .semibold))
                    .foregroundStyle(Color(chrome.palette.textPrimary))
                Text("\(lane.tasks.count)")
                    .font(.system(size: pt(WorkMetrics.fontXS)))
                    .foregroundStyle(Color(chrome.palette.textTertiary))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chrome.text("{state} tasks", ["state": title]))
            if lane.tasks.isEmpty {
                Text(chrome.text(WorkCopy.noTasks))
                    .font(.system(size: pt(WorkMetrics.fontSM)))
                    .foregroundStyle(Color(chrome.palette.textTertiary))
            }
            ForEach(lane.tasks, id: \.id) { task in
                TaskCard(task: task, members: members, chrome: chrome) { open(task.id) }
            }
        }
        .frame(minWidth: pt(WorkMetrics.laneMin), maxWidth: .infinity, alignment: .topLeading)
    }

    private var dotFill: SandColor {
        switch lane.state {
        case .inProgress: chrome.palette.blue
        case .blocked: chrome.palette.orange
        case .done: chrome.palette.green
        default: SandColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
    }

    private var dotStroke: SandColor {
        switch lane.state {
        case .inProgress: chrome.palette.blue
        case .blocked: chrome.palette.orange
        case .done: chrome.palette.green
        case .review: chrome.palette.magenta
        default: chrome.palette.textTertiary
        }
    }
}

private struct TaskCard: View {
    var task: WorkTask
    var members: [AgentView]
    var chrome: WorkChrome
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: pt(WorkMetrics.fontSM), weight: .semibold))
                    .foregroundStyle(Color(chrome.palette.textPrimary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.system(size: pt(WorkMetrics.cardBody)))
                        .foregroundStyle(Color(chrome.palette.textSecondary))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(assigneeLine)
                    .font(.system(size: pt(WorkMetrics.fontXS)))
                    .foregroundStyle(Color(chrome.palette.textTertiary))
                if !task.deliverables.isEmpty {
                    Text(chrome.text("{count} files", ["count": String(task.deliverables.count)]))
                        .font(.system(size: pt(WorkMetrics.fontXS)))
                        .foregroundStyle(Color(chrome.palette.textSecondary))
                }
            }
            .padding(pt(WorkMetrics.cardPadding))
            .frame(minHeight: pt(WorkMetrics.cardMinHeight), alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: pt(WorkMetrics.radiusLG), style: .continuous)
                    .fill(Color(chrome.palette.elevated))
            )
            .overlay(
                RoundedRectangle(cornerRadius: pt(WorkMetrics.radiusLG), style: .continuous)
                    .stroke(Color(chrome.palette.edge))
            )
            .shadow(color: Color(chrome.palette.textPrimary.opacity(0.06)), radius: 1, y: 1)
            .shadow(color: Color(chrome.palette.textPrimary.opacity(0.10)), radius: 6, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chrome.text("Open task: {title}", ["title": task.title]))
    }

    private var assigneeLine: String {
        let names = task.assigneeIds.prefix(3).map { memberName($0, members: members, language: chrome.language) }
        if names.isEmpty { return chrome.text("Unassigned") }
        return names.joined(separator: ", ")
    }
}

private struct LanePager: View {
    var lanes: [WorkLane]
    var chrome: WorkChrome
    var select: (WorkTaskState) -> Void
    @State private var selected: WorkTaskState = .proposed

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: pt(WorkMetrics.spacing2)) {
                ForEach(lanes, id: \.state.rawValue) { lane in
                    let title = chrome.text(lane.titleKey)
                    Button(action: { selected = lane.state; select(lane.state) }) {
                        Text(title)
                            .font(.system(size: pt(WorkMetrics.fontXS), weight: selected == lane.state ? .semibold : .regular))
                            .frame(minHeight: pt(WorkMetrics.spacing11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(selected == lane.state ? chrome.palette.textPrimary : chrome.palette.textTertiary))
                    .accessibilityLabel("\(title): \(lane.tasks.count)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(chrome.text("Task states"))
            HStack(spacing: 6) {
                ForEach(lanes, id: \.state.rawValue) { lane in
                    Circle()
                        .fill(Color(selected == lane.state ? chrome.palette.textSecondary : chrome.palette.textTertiary.opacity(0.4)))
                        .frame(width: pt(WorkMetrics.pagerDot), height: pt(WorkMetrics.pagerDot))
                        .scaleEffect(!chrome.reduceMotion && selected == lane.state ? 1.3 : 1)
                }
            }
        }
        .padding(.bottom, pt(WorkMetrics.spacing2))
    }
}

private struct DeliverablePage: View {
    var tasks: [WorkTaskView]
    var members: [AgentView]
    var chrome: WorkChrome
    var open: (String) -> Void
    @State private var copied: Set<String> = []
    @State private var failed: Set<String> = []

    private var done: [WorkTask] { tasksIn(tasks, state: .done) }

    var body: some View {
        ScrollView {
            if done.isEmpty {
                VStack(spacing: pt(WorkMetrics.spacing2)) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(chrome.palette.textTertiary))
                        .accessibilityHidden(true)
                    Text(chrome.text(WorkCopy.noDeliverables))
                        .font(.system(size: pt(WorkMetrics.fontBase), weight: .semibold))
                        .foregroundStyle(Color(chrome.palette.textPrimary))
                    Text(chrome.text(WorkCopy.deliverablesHint))
                        .font(.system(size: pt(WorkMetrics.fontSM)))
                        .foregroundStyle(Color(chrome.palette.textSecondary))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(pt(WorkMetrics.spacing6))
            } else {
                VStack(alignment: .leading, spacing: pt(WorkMetrics.spacing4)) {
                    ForEach(done, id: \.id) { task in
                        VStack(alignment: .leading, spacing: 6) {
                            Button(action: { open(task.id) }) {
                                Text(task.title)
                                    .font(.system(size: pt(WorkMetrics.fontBase), weight: .semibold))
                                    .foregroundStyle(Color(chrome.palette.textPrimary))
                            }
                            .buttonStyle(.plain)
                            Text(chrome.text("Done"))
                                .font(.system(size: pt(WorkMetrics.fontXS)))
                                .foregroundStyle(Color(chrome.palette.textSecondary))
                            Text(owner(task))
                                .font(.system(size: pt(WorkMetrics.fontXS)))
                                .foregroundStyle(Color(chrome.palette.textTertiary))
                            if task.deliverables.isEmpty {
                                Text(chrome.text(WorkCopy.noDeliverableFiles))
                                    .font(.system(size: pt(WorkMetrics.fontSM)))
                                    .foregroundStyle(Color(chrome.palette.textSecondary))
                            }
                            ForEach(task.deliverables, id: \.id) { file in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                        .font(.system(size: pt(WorkMetrics.fontSM), weight: .semibold))
                                        .foregroundStyle(Color(chrome.palette.textPrimary))
                                    Text(file.mimeType ?? chrome.text("File"))
                                        .font(.system(size: pt(WorkMetrics.fontXS)))
                                        .foregroundStyle(Color(chrome.palette.textTertiary))
                                    Text(deliverableDate(file.createdAt))
                                        .font(.system(size: pt(WorkMetrics.fontXS)))
                                        .foregroundStyle(Color(chrome.palette.textTertiary))
                                    Text(file.uri)
                                        .font(.system(size: pt(WorkMetrics.fontXS), design: .monospaced))
                                        .foregroundStyle(Color(chrome.palette.textSecondary))
                                        .textSelection(.enabled)
                                    Button(action: { copy(file.uri) }) {
                                        Text(buttonTitle(file.uri))
                                            .font(.system(size: pt(WorkMetrics.fontSM)))
                                            .frame(minHeight: pt(WorkMetrics.spacing11))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color(chrome.palette.textPrimary))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(pt(WorkMetrics.spacing4))
            }
        }
    }

    private func owner(_ task: WorkTask) -> String {
        guard let id = task.ownerAgentId else { return chrome.text("Unassigned") }
        return memberName(id, members: members, language: chrome.language)
    }

    private func buttonTitle(_ uri: String) -> String {
        if failed.contains(uri) { return chrome.text("无法复制，请选择上方路径手动复制。") }
        if copied.contains(uri) { return chrome.text("已复制") }
        return chrome.text("复制路径")
    }

    private func copy(_ uri: String) {
        if WorkClipboard.copy(uri) {
            copied.insert(uri)
            failed.remove(uri)
        } else {
            failed.insert(uri)
            copied.remove(uri)
        }
    }
}
#endif
