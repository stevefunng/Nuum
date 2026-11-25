/// Folds a work timeline into task rows and the sidebar preview.
/// Memory markdown is not read here. Chat text stays in the timeline file.
struct TimelineFold {
    var workId: String
    var tasks: [String: TaskListEntry] = [:]
    var lastActivityAt: Int64 = 0
    var preview: String?

    private static let previewLimit = 160

    mutating func apply(_ line: String) {
        guard let node = JSONDocument.parse(line) else { return }
        let createdAt = JSONDocument.int(JSONDocument.field(node, "createdAt")) ?? 0
        if createdAt > lastActivityAt { lastActivityAt = createdAt }
        switch JSONDocument.string(JSONDocument.field(node, "type")) ?? "" {
        case "chat.posted":
            updatePreview(JSONDocument.string(JSONDocument.field(node, "body")) ?? "")
        case "task.created":
            applyCreated(node, createdAt: createdAt)
        case "task.claimed":
            applyClaimed(node, createdAt: createdAt)
        case "task.assigned":
            applyAssigned(node, createdAt: createdAt)
        case "task.delegated":
            applyDelegated(node, createdAt: createdAt)
        case "task.transitioned":
            applyTransitioned(node, createdAt: createdAt)
        case "task.handed_off":
            applyHandedOff(node, createdAt: createdAt)
        default:
            break
        }
    }

    private mutating func applyCreated(_ node: JSONNode, createdAt: Int64) {
        guard let task = JSONDocument.field(node, "task") else { return }
        guard let taskId = JSONDocument.string(JSONDocument.field(task, "id")), !taskId.isEmpty,
              let title = JSONDocument.string(JSONDocument.field(task, "title")), !title.isEmpty,
              tasks[taskId] == nil
        else { return }
        var owner = JSONDocument.nullableString(task, "ownerAgentId")
        if owner == nil,
           let actor = JSONDocument.field(node, "actor"),
           JSONDocument.string(JSONDocument.field(actor, "kind")) == "agent" {
            owner = JSONDocument.nullableString(actor, "id")
        }
        let state = JSONDocument.string(JSONDocument.field(task, "state")) ?? ""
        let updatedAt: Int64
        if let updated = JSONDocument.field(task, "updatedAt"), !JSONDocument.isNull(updated) {
            updatedAt = JSONDocument.int(updated) ?? 0
        } else {
            updatedAt = createdAt
        }
        let revision: Int
        if JSONDocument.has(task, "revision") {
            revision = Int(JSONDocument.int(JSONDocument.field(task, "revision")) ?? 0)
        } else {
            revision = 1
        }
        tasks[taskId] = TaskListEntry(
            workId: workId,
            taskId: taskId,
            title: title,
            state: state.isEmpty ? "proposed" : state,
            updatedAt: updatedAt,
            assigneeIds: JSONDocument.stringList(JSONDocument.field(task, "assigneeIds")),
            ownerAgentId: owner,
            revision: revision
        )
    }

    private mutating func applyClaimed(_ node: JSONNode, createdAt: Int64) {
        guard let current = newer(node) else { return }
        tasks[current.taskId] = TaskListEntry(
            workId: current.workId,
            taskId: current.taskId,
            title: current.title,
            state: "in_progress",
            updatedAt: createdAt,
            assigneeIds: JSONDocument.stringList(JSONDocument.field(node, "assigneeIds")),
            ownerAgentId: current.ownerAgentId,
            revision: Int(JSONDocument.int(JSONDocument.field(node, "revision")) ?? 0)
        )
    }

    private mutating func applyAssigned(_ node: JSONNode, createdAt: Int64) {
        guard let current = newer(node) else { return }
        tasks[current.taskId] = TaskListEntry(
            workId: current.workId,
            taskId: current.taskId,
            title: current.title,
            state: current.state,
            updatedAt: createdAt,
            assigneeIds: JSONDocument.stringList(JSONDocument.field(node, "assigneeIds")),
            ownerAgentId: current.ownerAgentId,
            revision: Int(JSONDocument.int(JSONDocument.field(node, "revision")) ?? 0)
        )
    }

    private mutating func applyDelegated(_ node: JSONNode, createdAt: Int64) {
        guard let current = newer(node) else { return }
        let agentId = JSONDocument.string(JSONDocument.field(node, "agentId")) ?? ""
        var assignees = current.assigneeIds
        if !agentId.isEmpty, !assignees.contains(agentId) {
            assignees.append(agentId)
        }
        tasks[current.taskId] = TaskListEntry(
            workId: current.workId,
            taskId: current.taskId,
            title: current.title,
            state: "in_progress",
            updatedAt: createdAt,
            assigneeIds: assignees,
            ownerAgentId: current.ownerAgentId,
            revision: Int(JSONDocument.int(JSONDocument.field(node, "revision")) ?? 0)
        )
    }

    private mutating func applyTransitioned(_ node: JSONNode, createdAt: Int64) {
        guard let current = newer(node) else { return }
        let from = JSONDocument.string(JSONDocument.field(node, "from")) ?? ""
        if current.state != from { return }
        let to = JSONDocument.string(JSONDocument.field(node, "to")) ?? ""
        if to.isEmpty { return }
        tasks[current.taskId] = TaskListEntry(
            workId: current.workId,
            taskId: current.taskId,
            title: current.title,
            state: to,
            updatedAt: createdAt,
            assigneeIds: current.assigneeIds,
            ownerAgentId: current.ownerAgentId,
            revision: Int(JSONDocument.int(JSONDocument.field(node, "revision")) ?? 0)
        )
    }

    private mutating func applyHandedOff(_ node: JSONNode, createdAt: Int64) {
        if let messageId = JSONDocument.field(node, "messageId"), !JSONDocument.isNull(messageId) {
            updatePreview(JSONDocument.string(JSONDocument.field(node, "summary")) ?? "")
        }
        guard let current = newer(node) else { return }
        let next = JSONDocument.string(JSONDocument.field(node, "nextStatus")) ?? ""
        if next.isEmpty { return }
        tasks[current.taskId] = TaskListEntry(
            workId: current.workId,
            taskId: current.taskId,
            title: current.title,
            state: next,
            updatedAt: createdAt,
            assigneeIds: current.assigneeIds,
            ownerAgentId: current.ownerAgentId,
            revision: Int(JSONDocument.int(JSONDocument.field(node, "revision")) ?? 0)
        )
    }

    private func newer(_ node: JSONNode) -> TaskListEntry? {
        guard let taskId = JSONDocument.string(JSONDocument.field(node, "taskId")),
              let current = tasks[taskId]
        else { return nil }
        let revision = Int(JSONDocument.int(JSONDocument.field(node, "revision")) ?? 0)
        if revision <= current.revision { return nil }
        return current
    }

    private mutating func updatePreview(_ raw: String) {
        let text = raw.split { $0.isWhitespace }.joined(separator: " ")
        let clipped = String(text.prefix(Self.previewLimit))
        if !clipped.isEmpty { preview = clipped }
    }
}

func foldTimeline(workId: String, lines: [String]) -> TimelineFold {
    var fold = TimelineFold(workId: workId)
    for line in lines {
        fold.apply(line)
    }
    return fold
}
