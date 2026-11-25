import Foundation
import NuumContracts

private let workTitlePattern = #"(?i)^(?:work\s*bar|nunubar)\s*[·:：—–\-]\s*"#

/// Strips a leading "work bar" / "nunubar" separator. Otherwise returns `name`.
func workDisplayTitle(_ name: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: workTitlePattern) else { return name }
    let range = NSRange(name.startIndex..., in: name)
    let stripped = regex.stringByReplacingMatches(in: name, range: range, withTemplate: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return stripped.isEmpty ? name : stripped
}

enum CatalogKind: String, CaseIterable, Sendable, Equatable {
    case skill
    case cli
    case knowledge
    case localTool

    var labelKey: String {
        switch self {
        case .skill: "Skill"
        case .cli: "CLI"
        case .knowledge: "Knowledge"
        case .localTool: "Local tools"
        }
    }

    var showsBrowse: Bool {
        self == .skill || self == .knowledge
    }
}

let workLaneOrder: [WorkTaskState] = [
    .proposed, .ready, .inProgress, .blocked, .review, .done, .cancelled,
]

func laneTitleKey(_ state: WorkTaskState) -> String {
    switch state {
    case .proposed: "Proposed"
    case .ready: "Ready"
    case .inProgress: "In progress"
    case .blocked: "Blocked"
    case .review: "Review"
    case .done: "Done"
    case .cancelled: "Cancelled"
    }
}

enum MemberActivity: Equatable, Sendable {
    case idle
    case error
    case discussion
    case elsewhere
    case card(title: String?)
}

enum WorkAvatarState: Equatable, Sendable {
    case idle
    case working
    case waiting
    case error
}

/// A card is "running" only while the agent runtime is running. `in_progress` alone is a task state.
func memberActivity(_ agent: AgentView, snapshot: WorkSnapshot) -> MemberActivity {
    if agent.runtime.status != .running {
        return agent.runtime.status == .error ? .error : .idle
    }
    if agent.runtime.activeRunId == nil { return .elsewhere }
    let finished = Set(snapshot.events.compactMap { event -> String? in
        guard case .executionFinished(let body) = event.body, body.agentId == agent.profile.id else { return nil }
        return body.sourceEventId
    })
    let requested = snapshot.events.reversed().compactMap { event -> WorkRequestedBody? in
        guard case .workRequested(let body) = event.body, body.agentId == agent.profile.id, !finished.contains(event.id) else {
            return nil
        }
        return body
    }.first
    if let taskId = requested?.taskId {
        let title = snapshot.tasks.first { $0.task.id == taskId }?.task.title
        return .card(title: title)
    }
    if snapshot.discussionRunning { return .discussion }
    if let assigned = snapshot.tasks.first(where: { view in
        view.task.state == .inProgress && view.task.assigneeIds.contains(agent.profile.id)
    }) {
        return .card(title: assigned.task.title)
    }
    return .elsewhere
}

func avatarState(agent: AgentView, pendingApproval: Bool) -> WorkAvatarState {
    if pendingApproval { return .waiting }
    switch agent.runtime.status {
    case .error: return .error
    case .running: return .working
    case .idle: return .idle
    }
}

func activitySentence(_ activity: MemberActivity, language: Language) -> String {
    switch activity {
    case .idle:
        return WorkCopy.text("Idle", language: language)
    case .error:
        return WorkCopy.text("Run failed", language: language)
    case .discussion:
        return WorkCopy.text("Discussing", language: language)
    case .elsewhere:
        return WorkCopy.text("Working in another session", language: language)
    case .card(let title):
        let base = WorkCopy.text("Working on card", language: language)
        if let title, !title.isEmpty { return base + "：" + title }
        return base
    }
}

func canDispatch(_ member: AgentView, workId: String) -> Bool {
    if let binding = member.roomMemberships[workId]?.binding {
        return binding.grants.canManageOwnTasks
    }
    return member.settings.workMembership?.binding?.grants.canManageOwnTasks == true
}

func membershipRevision(_ member: AgentView, workId: String) -> Int {
    member.roomMemberships[workId]?.revision
        ?? member.settings.workMembership?.revision
        ?? 0
}

/// A transition that starts on a blocked card, or lands on blocked, carries the card's existing blocker.
/// The screen does not invent a reason field.
func blockerForTransition(task: WorkTask, to: WorkTaskState) -> WorkBlocker? {
    if task.state != .blocked && to != .blocked { return nil }
    return task.blocker
}

func inputAfterSeq(chat: [WorkEvent], recentCount: Int) -> Int {
    let recent = chat.suffix(max(recentCount, 1))
    let first = recent.first?.seq ?? 1
    return max(first - 1, 0)
}

func clampedHistoryCount(_ requested: Int, chatCount: Int) -> Int {
    let upper = max(chatCount, 1)
    return min(max(requested, 1), upper)
}

func skillManifestPath(_ directory: String) -> String {
    trimTrailingSeparators(directory) + "/SKILL.md"
}

func directoryName(_ directory: String) -> String {
    let trimmed = trimTrailingSeparators(directory)
    return trimmed.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
}

private func trimTrailingSeparators(_ value: String) -> String {
    var result = value
    while result.hasSuffix("/") || result.hasSuffix("\\") {
        result.removeLast()
    }
    return result
}

func applyPickedDirectory(kind: CatalogKind, directory: String, name: String) -> (name: String, path: String) {
    let path = kind == .skill ? skillManifestPath(directory) : directory
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let nextName = trimmed.isEmpty ? directoryName(directory) : name
    return (nextName, path)
}

enum CatalogBuild: Equatable, Sendable {
    case input(WorkCatalogInput)
    case missingToolName
    case incomplete
}

/// One of the four catalog inputs the protocol accepts. Description is always empty. Knowledge is read-only.
func catalogInput(kind: CatalogKind, name: String, path: String, commands: String) -> CatalogBuild {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedName.isEmpty || trimmedPath.isEmpty { return .incomplete }
    switch kind {
    case .skill:
        return .input(WorkCatalogInput.skill(SkillCatalogInput(name: trimmedName, description: "", manifestPath: trimmedPath)))
    case .cli:
        let subcommands = trimmedPath.isEmpty ? [] : commands.split { $0 == "," || $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
        return .input(WorkCatalogInput.cli(CliCatalogInput(
            name: trimmedName,
            description: "",
            executable: trimmedPath,
            allowedSubcommands: subcommands
        )))
    case .knowledge:
        return .input(WorkCatalogInput.knowledge(KnowledgeCatalogInput(
            name: trimmedName,
            description: "",
            roots: [trimmedPath],
            readOnly: true
        )))
    case .localTool:
        let tools = trimmedPath.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if tools.isEmpty { return .missingToolName }
        return .input(WorkCatalogInput.localTool(LocalToolCatalogInput(name: trimmedName, description: "", toolNames: tools)))
    }
}

func tasksIn(_ tasks: [WorkTaskView], state: WorkTaskState) -> [WorkTask] {
    tasks.map(\.task).filter { $0.state == state }
}

func traceText(_ event: TranscriptEvent) -> String {
    switch event {
    case .user(let event):
        return event.text
    case .wake(let event):
        return event.text
    case .assistant(let event):
        return event.parts.map(assistantText).joined(separator: "\n\n")
    case .tool(let event):
        return event.name + "\n" + event.content
    case .message:
        return event.type
    case .compact(let event):
        return event.summary
    case .profile(let event):
        return event.name ?? "profile"
    }
}

private func assistantText(_ part: AssistantPart) -> String {
    switch part {
    case .thinking(let part):
        return part.text
    case .text(let part):
        return part.text
    case .toolCall(let part):
        let arguments = part.arguments.map { "\($0.key)=\(jsonText($0.value))" }.sorted().joined(separator: ", ")
        return part.name + "\n" + arguments
    }
}

func jsonText(_ value: JSONValue) -> String {
    switch value {
    case .null: return "null"
    case .bool(let value): return value ? "true" : "false"
    case .int(let value): return String(value)
    case .double(let value): return String(value)
    case .string(let value): return value
    case .array(let values): return values.map(jsonText).joined(separator: ",")
    case .object(let object):
        return object.map { "\($0.key)=\(jsonText($0.value))" }.sorted().joined(separator: ", ")
    }
}

func deliverableDate(_ millis: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

func actionLabel(_ action: LocalToolAction, language: Language) -> String {
    let key: String
    switch action {
    case .readFile: key = "read-file"
    case .listDirectory: key = "list-directory"
    case .writeFile: key = "write-file"
    case .runCommand: key = "run-command"
    case .network: key = "network"
    }
    return WorkCopy.text(key, language: language)
}

func priorityLabel(_ priority: WorkTaskPriority, language: Language) -> String {
    switch priority {
    case .low: WorkCopy.text("Low", language: language)
    case .normal: WorkCopy.text("Normal", language: language)
    case .high: WorkCopy.text("High", language: language)
    }
}

func memberName(_ id: String, members: [AgentView], language: Language) -> String {
    members.first { $0.profile.id == id }?.profile.name ?? WorkCopy.text("Agent", language: language)
}

enum TaskDetailAction: String, CaseIterable, Equatable, Sendable {
    case confirmResume
    case cancelTask
    case requestChanges
    case acceptDelivery
    case dispatch

    var labelKey: String {
        switch self {
        case .confirmResume: "Confirm and resume"
        case .cancelTask: "Cancel task"
        case .requestChanges: "Request changes"
        case .acceptDelivery: "Accept delivery"
        case .dispatch: "Run"
        }
    }

    var destination: WorkTaskState? {
        switch self {
        case .confirmResume, .requestChanges: .inProgress
        case .cancelTask: .cancelled
        case .acceptDelivery: .done
        case .dispatch: nil
        }
    }
}

/// Buttons the detail is allowed to show. There is no free-form state picker and no create-card action.
func taskDetailActions(_ state: WorkTaskState) -> [TaskDetailAction] {
    switch state {
    case .blocked: [.confirmResume, .cancelTask]
    case .review: [.requestChanges, .acceptDelivery]
    case .ready, .inProgress: [.dispatch]
    case .proposed, .done, .cancelled: []
    }
}

struct WorkChatDockState: Equatable, Sendable {
    var roomForcesOpen: Bool
    var opened: Bool = false

    var isOpen: Bool { roomForcesOpen || opened }

    mutating func focusInput() { opened = true }
    mutating func close() { opened = false }
}

enum WorkDrag {
    static let agentPrefix = "nuum-agent:"

    static func payload(agentId: String) -> String { agentPrefix + agentId }

    static func agentId(from payload: String) -> String? {
        guard payload.hasPrefix(agentPrefix) else { return nil }
        let id = String(payload.dropFirst(agentPrefix.count))
        return id.isEmpty ? nil : id
    }
}

enum WorkSecrets {
    /// Host sentences may name a missing key. The surface must not show that, or a raw token.
    static func shouldHide(_ message: String) -> Bool {
        let folded = message.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
        if folded.contains("api key") || folded.contains("apikey") || folded.contains("api_key") || folded.contains("api-key") {
            return true
        }
        if folded.contains("secrets" + ".bin") { return true }
        if folded.range(of: #"sk-[a-z0-9]"#, options: .regularExpression) != nil { return true }
        if folded.range(of: #"bearer\s+[a-z0-9]"#, options: .regularExpression) != nil { return true }
        return false
    }
}

func workNotice(from error: Error) -> WorkNotice {
    guard let nuum = error as? NuumError else {
        return WorkNotice(message: WorkCopy.hostError, code: nil)
    }
    if nuum.code == HostErrorCode.noAPIKey || WorkSecrets.shouldHide(nuum.message) {
        return WorkNotice(message: WorkCopy.roomResponseFailed, code: HostErrorCode.noAPIKey)
    }
    return WorkNotice(message: nuum.message, code: nuum.code)
}

func presentHostSentence(_ sentence: String, language: Language) -> String {
    if WorkSecrets.shouldHide(sentence) {
        return WorkCopy.text(WorkCopy.roomResponseFailed, language: language)
    }
    return WorkCopy.text(sentence, language: language)
}

struct InspectorPreference: Codable, Equatable, Sendable {
    var width: Double
    var split: Double

    static let standard = InspectorPreference(width: 250, split: 0.32)
}

enum WorkInspectorLayout {
    static let storageKey = "nuum.ui.workInspector.v1"
    static let suiteName = "nuum-ui"
    static let minWidth = 184.0
    static let maxCap = 380.0
    static let columnReserve = 440.0

    static func maxWidth(columnWidth: Double) -> Double {
        max(minWidth, min(maxCap, columnWidth - columnReserve))
    }

    static func project(preference: InspectorPreference, columnWidth: Double) -> Double {
        let upper = maxWidth(columnWidth: columnWidth)
        return min(upper, max(minWidth, preference.width))
    }

    static func read(_ defaults: UserDefaults) -> InspectorPreference {
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(InspectorPreference.self, from: data),
              saved.width.isFinite, saved.split.isFinite else {
            return .standard
        }
        return InspectorPreference(
            width: min(maxCap, max(minWidth, saved.width)),
            split: min(1, max(0, saved.split))
        )
    }

    static func write(_ preference: InspectorPreference, _ defaults: UserDefaults) {
        let clamped = InspectorPreference(
            width: min(maxCap, max(minWidth, preference.width)),
            split: min(1, max(0, preference.split))
        )
        guard let data = try? JSONEncoder().encode(clamped) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct WorkCreationForm: Equatable, Sendable {
    var name: String = ""
    var kind: WorkKind = .work
    var canCancel: Bool = false
    var submitting: Bool = false
    var notice: WorkNotice?

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSubmit: Bool { !submitting && !trimmedName.isEmpty }
    /// Mac `WorkCreation` has no goal field.
    var includesGoal: Bool { false }
}

enum CatalogPage: Equatable, Sendable {
    case discover
    case local
}

struct CatalogDraft: Equatable, Sendable {
    var page: CatalogPage = .discover
    var kind: CatalogKind = .skill
    var name = ""
    var path = ""
    var commands = ""
    var errorKey: String?
    var importing = false

    var canSubmit: Bool {
        !importing
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func selectKind(_ kind: CatalogKind) {
        self.kind = kind
        path = ""
        errorKey = nil
    }

    mutating func selectPage(_ page: CatalogPage) {
        self.page = page
        errorKey = nil
    }

    func build() -> CatalogBuild {
        catalogInput(kind: kind, name: name, path: path, commands: commands)
    }
}

struct DiscoverCard: Equatable, Sendable {
    var eyebrow: String
    var title: String
    var body: String
    var badge: String
    /// The collection is coming soon. Cards do not install or purchase.
    var interactive: Bool
}

func discoverCards(language: Language) -> [DiscoverCard] {
    let badge = WorkCopy.text("Presets on the way", language: language)
    return [
        DiscoverCard(
            eyebrow: WorkCopy.text("KNOW-HOW", language: language),
            title: WorkCopy.text("Skills", language: language),
            body: WorkCopy.text("Thoughtful workflows.", language: language) + " "
                + WorkCopy.text("Ready for your next task.", language: language),
            badge: badge,
            interactive: false
        ),
        DiscoverCard(
            eyebrow: WorkCopy.text("HANDS-ON", language: language),
            title: WorkCopy.text("CLI tools", language: language),
            body: WorkCopy.text("Familiar tools.", language: language) + " "
                + WorkCopy.text("A little more possibility.", language: language),
            badge: badge,
            interactive: false
        ),
    ]
}

enum WorkBoardPage: Equatable, Sendable {
    case tasks
    case deliverables

    mutating func toggle() {
        self = self == .tasks ? .deliverables : .tasks
    }
}

struct WorkLane: Equatable, Sendable {
    var state: WorkTaskState
    var titleKey: String
    var tasks: [WorkTask]
}

func workLanes(_ tasks: [WorkTaskView]) -> [WorkLane] {
    workLaneOrder.map { state in
        WorkLane(state: state, titleKey: laneTitleKey(state), tasks: tasksIn(tasks, state: state))
    }
}

/// Approval buttons are deny, once, and always. `never` is not on this bar.
let approvalResolutions: [ToolResolution] = [.deny, .once, .always]

func approvalTitle(_ approval: PendingApproval, agentName: String, language: Language) -> String {
    let action = actionLabel(approval.action, language: language)
    let sentence = approval.justification ?? WorkCopy.text("Allow {action}?", language: language, ["action": action])
    return "\(agentName) · \(sentence)"
}

struct WorkNotice: Sendable, Equatable {
    var message: String
    var code: Int?
}

struct PendingApproval: Sendable, Equatable, Identifiable {
    var agentId: String
    var toolCallId: String
    var action: LocalToolAction
    var target: String
    var justification: String?
    var allowAlways: Bool
    var details: String?
    var failureMessage: String?

    var id: String { "\(agentId):\(toolCallId)" }
}

enum DirectoryPick: Sendable, Equatable {
    case cancelled
    case path(String)
    case failed(WorkNotice)
}
