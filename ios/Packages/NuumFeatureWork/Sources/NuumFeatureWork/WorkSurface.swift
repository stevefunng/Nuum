import NuumContracts

enum WorkPhase: Equatable, Sendable {
    case loading
    case room
    case board
    case unspecified
}

struct WorkSurface: Equatable, Sendable {
    var phase: WorkPhase
    var title: String
    var upgradeEnabled: Bool
    var showsUpgrade: Bool
    var showsStop: Bool
    var showsLanes: Bool
    var showsBlockedCount: Bool
    var blockedCount: Int
    var notice: String?
    var noticeCode: Int?
    var chatEmpty: Bool
    var memberEmpty: Bool
    var approvalIDs: [String]
    var approvalResolutions: [ToolResolution]
    var interruptions: Int
    var historyEditors: Int
    var continueButtons: Int
    var laneCount: Int
    var controlLabels: [String]
    var discoverInteractiveCount: Int
    var catalogKindCount: Int
    var showsGoalField: Bool
    var waitingCaption: Bool
}

func workPhase(_ state: WorkUiState) -> WorkPhase {
    guard let snapshot = state.snapshot else { return .loading }
    switch snapshot.profile.kind {
    case .room: return .room
    case .work: return .board
    case nil: return .unspecified
    }
}

func workSurface(
    state: WorkUiState,
    language: Language,
    fallbackTitle: String = "",
    page: WorkBoardPage = .tasks
) -> WorkSurface {
    let phase = workPhase(state)
    let snapshot = state.snapshot
    let title = snapshot.map { workDisplayTitle($0.profile.name) } ?? fallbackTitle
    let blocked = snapshot?.tasks.filter { $0.task.state == .blocked }.count ?? 0
    let chat = snapshot?.chat ?? []
    let members = snapshot?.members ?? []
    let interruptions = snapshot?.interruptions ?? []
    var labels: [String] = []
    if phase == .loading || phase == .room {
        labels.append(WorkCopy.text(WorkCopy.enableTaskBoard, language: language))
    }
    if snapshot?.discussionRunning == true {
        labels.append(WorkCopy.text(WorkCopy.stopDiscussion, language: language))
    }
    if phase == .board {
        labels.append(WorkCopy.text(page == .tasks ? "切换到产物" : "切换到 Tasks", language: language))
        labels.append(WorkCopy.text("Tasks", language: language))
        labels.append(WorkCopy.text("产物", language: language))
        for lane in workLanes(snapshot?.tasks ?? []) {
            labels.append(WorkCopy.text(lane.titleKey, language: language))
            if lane.tasks.isEmpty {
                labels.append(WorkCopy.text(WorkCopy.noTasks, language: language))
            }
            for task in lane.tasks {
                labels.append(WorkCopy.text("Open task: {title}", language: language, ["title": task.title]))
            }
        }
    }
    if !state.approvals.isEmpty {
        labels.append(contentsOf: approvalResolutions.map { resolutionLabel($0, language: language) })
    }
    let notice = state.notice.map { WorkCopy.text($0.message, language: language) }
    return WorkSurface(
        phase: phase,
        title: title,
        upgradeEnabled: phase == .room,
        showsUpgrade: phase == .loading || phase == .room,
        showsStop: snapshot?.discussionRunning == true,
        showsLanes: phase == .board,
        showsBlockedCount: phase == .board && blocked > 0,
        blockedCount: blocked,
        notice: notice,
        noticeCode: state.notice?.code,
        chatEmpty: chat.isEmpty,
        memberEmpty: members.isEmpty,
        approvalIDs: state.approvals.map(\.id),
        approvalResolutions: approvalResolutions,
        interruptions: interruptions.count,
        historyEditors: interruptions.filter { $0.taskId == nil }.count,
        continueButtons: interruptions.count,
        laneCount: phase == .board ? workLaneOrder.count : 0,
        controlLabels: labels,
        discoverInteractiveCount: discoverCards(language: language).filter(\.interactive).count,
        catalogKindCount: CatalogKind.allCases.count,
        showsGoalField: false,
        waitingCaption: !state.approvals.isEmpty
    )
}

private func resolutionLabel(_ resolution: ToolResolution, language: Language) -> String {
    switch resolution {
    case .deny: WorkCopy.text("Deny", language: language)
    case .once: WorkCopy.text("Allow once", language: language)
    case .always: WorkCopy.text("Always allow", language: language)
    case .never: "never"
    }
}

struct WorkUiState: Sendable, Equatable {
    var loading: Bool
    var snapshot: WorkSnapshot?
    var notice: WorkNotice?
    var approvals: [PendingApproval]
    var acceptsModelRequests: Bool

    init() {
        loading = true
        snapshot = nil
        notice = nil
        approvals = []
        acceptsModelRequests = true
    }
}
