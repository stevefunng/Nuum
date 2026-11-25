import Foundation

public enum WorkKind: String, Sendable, Equatable, Codable, CaseIterable {
    case room
    case work
}

public enum WorkRole: String, Sendable, Equatable, Codable, CaseIterable {
    case coordinator
    case worker
    case observer
}

public enum WorkTaskState: String, Sendable, Equatable, Codable, CaseIterable {
    case proposed
    case ready
    case inProgress = "in_progress"
    case blocked
    case review
    case done
    case cancelled
}

public let workTaskStates: [String] = WorkTaskState.allCases.map(\.rawValue)

public enum WorkTaskPriority: String, Sendable, Equatable, Codable, CaseIterable {
    case low
    case normal
    case high
}

public enum HandoffNextStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case inProgress = "in_progress"
    case review
    case blocked
    case done
}

public enum ExecutionFinishStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case completed
    case failed
    case cancelled
}

public enum DiscussionFinishStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case completed
    case cancelled
    case interrupted
}

public struct WorkProfile: WireRepresentable, Sendable, Equatable {
    public var kind: WorkKind?
    public var id: String
    public var name: String
    public var description: String
    public var avatar: String?
    public var projectRoot: String?
    public var workspaceId: String?
    public var createdAt: Int64

    public init(
        id: String,
        name: String,
        description: String,
        projectRoot: String?,
        createdAt: Int64,
        kind: WorkKind? = nil,
        avatar: String? = nil,
        workspaceId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.projectRoot = projectRoot
        self.createdAt = createdAt
        self.kind = kind
        self.avatar = avatar
        self.workspaceId = workspaceId
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        kind = try object.optionalEnumeration("kind", as: WorkKind.self)
        id = try object.string("id")
        name = try object.string("name")
        description = try object.string("description")
        avatar = try object.optionalString("avatar")
        projectRoot = try object.nullableString("projectRoot")
        workspaceId = try object.optionalString("workspaceId")
        createdAt = try object.int64("createdAt")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        if let kind { fields.add("kind", kind.rawValue) }
        fields.add("id", id)
        fields.add("name", name)
        fields.add("description", description)
        fields.addIfPresent("avatar", avatar)
        fields.add("projectRoot", projectRoot.map(JSONValue.string) ?? .null)
        fields.addIfPresent("workspaceId", workspaceId)
        fields.add("createdAt", createdAt)
        return fields.json
    }
}

/// Flat sidebar row: profile fields plus derived activity. Members are not stored here.
public struct WorkListItem: WireRepresentable, Sendable, Equatable {
    public var kind: WorkKind?
    public var id: String
    public var name: String
    public var description: String
    public var avatar: String?
    public var projectRoot: String?
    public var workspaceId: String?
    public var createdAt: Int64
    public var lastActivityAt: Int64
    public var preview: String?

    public init(
        id: String,
        name: String,
        description: String,
        projectRoot: String?,
        createdAt: Int64,
        lastActivityAt: Int64,
        kind: WorkKind? = nil,
        avatar: String? = nil,
        workspaceId: String? = nil,
        preview: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.projectRoot = projectRoot
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.kind = kind
        self.avatar = avatar
        self.workspaceId = workspaceId
        self.preview = preview
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        kind = try object.optionalEnumeration("kind", as: WorkKind.self)
        id = try object.string("id")
        name = try object.string("name")
        description = try object.string("description")
        avatar = try object.optionalString("avatar")
        projectRoot = try object.nullableString("projectRoot")
        workspaceId = try object.optionalString("workspaceId")
        createdAt = try object.int64("createdAt")
        lastActivityAt = try object.int64("lastActivityAt")
        preview = try object.optionalString("preview")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        if let kind { fields.add("kind", kind.rawValue) }
        fields.add("id", id)
        fields.add("name", name)
        fields.add("description", description)
        fields.addIfPresent("avatar", avatar)
        fields.add("projectRoot", projectRoot.map(JSONValue.string) ?? .null)
        fields.addIfPresent("workspaceId", workspaceId)
        fields.add("createdAt", createdAt)
        fields.add("lastActivityAt", lastActivityAt)
        fields.addIfPresent("preview", preview)
        return fields.json
    }
}

public struct WorkGrants: WireRepresentable, Sendable, Equatable {
    public var canPost: Bool
    public var canManageOwnTasks: Bool
    public var canAssignTasks: Bool
    public var canEditCatalog: Bool

    public init(canPost: Bool, canManageOwnTasks: Bool, canAssignTasks: Bool, canEditCatalog: Bool) {
        self.canPost = canPost
        self.canManageOwnTasks = canManageOwnTasks
        self.canAssignTasks = canAssignTasks
        self.canEditCatalog = canEditCatalog
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        canPost = try object.bool("canPost")
        canManageOwnTasks = try object.bool("canManageOwnTasks")
        canAssignTasks = try object.bool("canAssignTasks")
        canEditCatalog = try object.bool("canEditCatalog")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("canPost", canPost)
        fields.add("canManageOwnTasks", canManageOwnTasks)
        fields.add("canAssignTasks", canAssignTasks)
        fields.add("canEditCatalog", canEditCatalog)
        return fields.json
    }
}

public struct WorkBinding: WireRepresentable, Sendable, Equatable {
    public var workId: String
    public var role: WorkRole
    public var joinedAt: Int64
    public var grants: WorkGrants

    public init(workId: String, role: WorkRole, joinedAt: Int64, grants: WorkGrants) {
        self.workId = workId
        self.role = role
        self.joinedAt = joinedAt
        self.grants = grants
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        workId = try object.string("workId")
        role = try object.enumeration("role", as: WorkRole.self)
        joinedAt = try object.int64("joinedAt")
        grants = try WorkGrants(protocolJSON: object.require("grants"))
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("workId", workId)
        fields.add("role", role.rawValue)
        fields.add("joinedAt", joinedAt)
        fields.add("grants", grants.protocolJSON)
        return fields.json
    }
}

/// One dynamic slot. `revision` is the CAS token for drag in, drag out, and switching Works.
public struct WorkMembership: WireRepresentable, Sendable, Equatable {
    public var revision: Int
    public var binding: WorkBinding?

    public init(revision: Int, binding: WorkBinding?) {
        self.revision = revision
        self.binding = binding
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        revision = try object.int("revision")
        if let raw = object.value("binding") {
            binding = raw.isNull ? nil : try WorkBinding(protocolJSON: raw)
        } else {
            throw ProtocolParseException(["binding"], "Required")
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("revision", revision)
        fields.add("binding", binding?.protocolJSON ?? .null)
        return fields.json
    }
}

public struct WorkDeliverable: WireRepresentable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var uri: String
    public var mimeType: String?
    public var createdAt: Int64

    public init(id: String, name: String, uri: String, createdAt: Int64, mimeType: String? = nil) {
        self.id = id
        self.name = name
        self.uri = uri
        self.createdAt = createdAt
        self.mimeType = mimeType
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        id = try object.string("id")
        name = try object.string("name")
        uri = try object.string("uri")
        mimeType = try object.optionalString("mimeType")
        createdAt = try object.int64("createdAt")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("id", id)
        fields.add("name", name)
        fields.add("uri", uri)
        fields.addIfPresent("mimeType", mimeType)
        fields.add("createdAt", createdAt)
        return fields.json
    }
}

public struct WorkTaskBlocker: WireRepresentable, Sendable, Equatable {
    public var reason: String
    public var ownerId: String?
    public var resumeCondition: String?
    public var createdAt: Int64

    public init(reason: String, createdAt: Int64, ownerId: String? = nil, resumeCondition: String? = nil) {
        self.reason = reason
        self.createdAt = createdAt
        self.ownerId = ownerId
        self.resumeCondition = resumeCondition
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        reason = try object.string("reason")
        ownerId = try object.optionalString("ownerId")
        resumeCondition = try object.optionalString("resumeCondition")
        createdAt = try object.int64("createdAt")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("reason", reason)
        fields.addIfPresent("ownerId", ownerId)
        fields.addIfPresent("resumeCondition", resumeCondition)
        fields.add("createdAt", createdAt)
        return fields.json
    }
}

public struct WorkTransitionBlocker: WireRepresentable, Sendable, Equatable {
    public var reason: String
    public var ownerId: String?
    public var resumeCondition: String?

    public init(reason: String, ownerId: String? = nil, resumeCondition: String? = nil) {
        self.reason = reason
        self.ownerId = ownerId
        self.resumeCondition = resumeCondition
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        reason = try object.string("reason")
        ownerId = try object.optionalString("ownerId")
        resumeCondition = try object.optionalString("resumeCondition")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("reason", reason)
        fields.addIfPresent("ownerId", ownerId)
        fields.addIfPresent("resumeCondition", resumeCondition)
        return fields.json
    }
}

public struct WorkTask: WireRepresentable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var description: String
    public var acceptanceCriteria: [String]
    public var state: WorkTaskState
    public var ownerAgentId: String?
    public var assigneeIds: [String]
    public var dependencyIds: [String]
    public var priority: WorkTaskPriority
    public var revision: Int
    public var deliverables: [WorkDeliverable]
    public var blocker: WorkTaskBlocker?
    public var createdAt: Int64
    public var updatedAt: Int64
    public var allowedTransitions: [WorkTaskState]?

    public init(
        id: String,
        title: String,
        description: String,
        acceptanceCriteria: [String],
        state: WorkTaskState,
        assigneeIds: [String],
        dependencyIds: [String],
        priority: WorkTaskPriority,
        revision: Int,
        deliverables: [WorkDeliverable],
        createdAt: Int64,
        updatedAt: Int64,
        ownerAgentId: String? = nil,
        blocker: WorkTaskBlocker? = nil,
        allowedTransitions: [WorkTaskState]? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.acceptanceCriteria = acceptanceCriteria
        self.state = state
        self.assigneeIds = assigneeIds
        self.dependencyIds = dependencyIds
        self.priority = priority
        self.revision = revision
        self.deliverables = deliverables
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ownerAgentId = ownerAgentId
        self.blocker = blocker
        self.allowedTransitions = allowedTransitions
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        id = try object.string("id")
        title = try object.string("title")
        description = try object.string("description")
        acceptanceCriteria = try object.stringArray("acceptanceCriteria")
        state = try object.enumeration("state", as: WorkTaskState.self)
        ownerAgentId = try object.optionalString("ownerAgentId")
        assigneeIds = try object.stringArray("assigneeIds")
        dependencyIds = try object.stringArray("dependencyIds")
        priority = try object.enumeration("priority", as: WorkTaskPriority.self)
        revision = try object.int("revision")
        deliverables = try object.array("deliverables").map { try WorkDeliverable(protocolJSON: $0) }
        if let blockerJSON = try object.optionalObject("blocker") {
            blocker = try WorkTaskBlocker(protocolJSON: blockerJSON.json)
        } else {
            blocker = nil
        }
        createdAt = try object.int64("createdAt")
        updatedAt = try object.int64("updatedAt")
        if let raw = try object.optionalArray("allowedTransitions") {
            allowedTransitions = try raw.map { value in
                guard case .string(let wire) = value, let state = WorkTaskState(rawValue: wire) else {
                    throw ProtocolParseException(["allowedTransitions"], "Invalid enum value")
                }
                return state
            }
        } else {
            allowedTransitions = nil
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("id", id)
        fields.add("title", title)
        fields.add("description", description)
        fields.add("acceptanceCriteria", .array(acceptanceCriteria.map(JSONValue.string)))
        fields.add("state", state.rawValue)
        fields.addIfPresent("ownerAgentId", ownerAgentId)
        fields.add("assigneeIds", .array(assigneeIds.map(JSONValue.string)))
        fields.add("dependencyIds", .array(dependencyIds.map(JSONValue.string)))
        fields.add("priority", priority.rawValue)
        fields.add("revision", revision)
        fields.add("deliverables", .array(deliverables.map(\.protocolJSON)))
        if let blocker { fields.add("blocker", blocker.protocolJSON) }
        fields.add("createdAt", createdAt)
        fields.add("updatedAt", updatedAt)
        if let allowedTransitions {
            fields.add("allowedTransitions", .array(allowedTransitions.map { .string($0.rawValue) }))
        }
        return fields.json
    }

    public func asView(allowedTransitions: [WorkTaskState]) -> WorkTask {
        var copy = self
        copy.allowedTransitions = allowedTransitions
        return copy
    }
}

public enum WorkCatalogEntry: WireRepresentable, Sendable, Equatable {
    case skill(id: String, name: String, description: String, enabled: Bool, manifestPath: String)
    case cli(id: String, name: String, description: String, enabled: Bool, executable: String, allowedSubcommands: [String])
    case knowledge(id: String, name: String, description: String, enabled: Bool, roots: [String], readOnly: Bool)
    case localTool(id: String, name: String, description: String, enabled: Bool, toolNames: [String])

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        let id = try object.string("id")
        let name = try object.string("name")
        let description = try object.string("description")
        let enabled = try object.bool("enabled")
        switch try object.string("kind") {
        case "skill":
            self = .skill(id: id, name: name, description: description, enabled: enabled, manifestPath: try object.string("manifestPath"))
        case "cli":
            self = .cli(
                id: id,
                name: name,
                description: description,
                enabled: enabled,
                executable: try object.string("executable"),
                allowedSubcommands: try object.stringArray("allowedSubcommands")
            )
        case "knowledge":
            let readOnly = try object.bool("readOnly")
            guard readOnly else {
                throw ProtocolParseException(["readOnly"], "knowledge catalog entries are readOnly")
            }
            self = .knowledge(
                id: id,
                name: name,
                description: description,
                enabled: enabled,
                roots: try object.stringArray("roots"),
                readOnly: true
            )
        case "local-tool":
            self = .localTool(
                id: id,
                name: name,
                description: description,
                enabled: enabled,
                toolNames: try object.stringArray("toolNames")
            )
        default:
            throw ProtocolParseException(["kind"], "Invalid enum value")
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        switch self {
        case .skill(let id, let name, let description, let enabled, let manifestPath):
            fields.add("kind", "skill")
            catalogBase(&fields, id: id, name: name, description: description, enabled: enabled)
            fields.add("manifestPath", manifestPath)
        case .cli(let id, let name, let description, let enabled, let executable, let allowedSubcommands):
            fields.add("kind", "cli")
            catalogBase(&fields, id: id, name: name, description: description, enabled: enabled)
            fields.add("executable", executable)
            fields.add("allowedSubcommands", .array(allowedSubcommands.map(JSONValue.string)))
        case .knowledge(let id, let name, let description, let enabled, let roots, _):
            fields.add("kind", "knowledge")
            catalogBase(&fields, id: id, name: name, description: description, enabled: enabled)
            fields.add("roots", .array(roots.map(JSONValue.string)))
            fields.add("readOnly", true)
        case .localTool(let id, let name, let description, let enabled, let toolNames):
            fields.add("kind", "local-tool")
            catalogBase(&fields, id: id, name: name, description: description, enabled: enabled)
            fields.add("toolNames", .array(toolNames.map(JSONValue.string)))
        }
        return fields.json
    }
}

private func catalogBase(_ fields: inout JSONFieldList, id: String, name: String, description: String, enabled: Bool) {
    fields.add("id", id)
    fields.add("name", name)
    fields.add("description", description)
    fields.add("enabled", enabled)
}

public struct WorkCatalog: WireRepresentable, Sendable, Equatable {
    public var revision: Int
    public var entries: [WorkCatalogEntry]

    public init(revision: Int, entries: [WorkCatalogEntry]) {
        self.revision = revision
        self.entries = entries
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        revision = try object.int("revision")
        entries = try object.array("entries").map { try WorkCatalogEntry(protocolJSON: $0) }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("revision", revision)
        fields.add("entries", .array(entries.map(\.protocolJSON)))
        return fields.json
    }
}

public let emptyWorkCatalog = WorkCatalog(revision: 0, entries: [])

public enum WorkActor: WireRepresentable, Sendable, Equatable {
    case user(id: String)
    case agent(id: String)
    case system(id: String)

    public var id: String {
        switch self {
        case .user(let id), .agent(let id), .system(let id):
            id
        }
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        let id = try object.string("id")
        switch try object.string("kind") {
        case "user": self = .user(id: id)
        case "agent": self = .agent(id: id)
        case "system": self = .system(id: id)
        default: throw ProtocolParseException(["kind"], "Invalid enum value")
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        switch self {
        case .user: fields.add("kind", "user")
        case .agent: fields.add("kind", "agent")
        case .system: fields.add("kind", "system")
        }
        fields.add("id", id)
        return fields.json
    }
}

public struct DispatchDiscussion: WireRepresentable, Sendable, Equatable {
    public var rootId: String
    public var round: Int
    public var order: [String]
    public var index: Int

    public init(rootId: String, round: Int, order: [String], index: Int) {
        self.rootId = rootId
        self.round = round
        self.order = order
        self.index = index
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        rootId = try object.string("rootId")
        round = try object.int("round")
        order = try object.stringArray("order")
        index = try object.int("index")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("rootId", rootId)
        fields.add("round", round)
        fields.add("order", .array(order.map(JSONValue.string)))
        fields.add("index", index)
        return fields.json
    }
}

public struct WorkEventHeader: Sendable, Equatable {
    public var id: String
    public var workId: String
    public var seq: Int
    public var createdAt: Int64
    public var actor: WorkActor
    public var causationId: String?
    public var correlationId: String?
    public var clientEventId: String?
    public var serverWatermark: Int?

    public init(
        id: String,
        workId: String,
        seq: Int,
        createdAt: Int64,
        actor: WorkActor,
        causationId: String? = nil,
        correlationId: String? = nil,
        clientEventId: String? = nil,
        serverWatermark: Int? = nil
    ) {
        self.id = id
        self.workId = workId
        self.seq = seq
        self.createdAt = createdAt
        self.actor = actor
        self.causationId = causationId
        self.correlationId = correlationId
        self.clientEventId = clientEventId
        self.serverWatermark = serverWatermark
    }

    init(_ object: JSONObject) throws {
        id = try object.string("id")
        workId = try object.string("workId")
        seq = try object.int("seq")
        createdAt = try object.int64("createdAt")
        actor = try WorkActor(protocolJSON: object.require("actor"))
        causationId = try object.optionalString("causationId")
        correlationId = try object.optionalString("correlationId")
        clientEventId = try object.optionalString("clientEventId")
        serverWatermark = try object.optionalInt("serverWatermark")
    }

    func write(_ type: String, extra: (inout JSONFieldList) -> Void) -> JSONValue {
        var fields = JSONFieldList()
        fields.add("type", type)
        fields.add("id", id)
        fields.add("workId", workId)
        fields.add("seq", seq)
        fields.add("createdAt", createdAt)
        fields.add("actor", actor.protocolJSON)
        extra(&fields)
        fields.addIfPresent("causationId", causationId)
        fields.addIfPresent("correlationId", correlationId)
        fields.addIfPresent("clientEventId", clientEventId)
        fields.addIfPresent("serverWatermark", serverWatermark)
        return fields.json
    }
}

public enum WorkEvent: WireRepresentable, Sendable, Equatable {
    case chatPosted(ChatPosted)
    case taskCreated(TaskCreated)
    case taskClaimed(TaskClaimed)
    case taskAssigned(TaskAssigned)
    case taskDelegated(TaskDelegated)
    case taskTransitioned(TaskTransitioned)
    case taskProgressed(TaskProgressed)
    case taskHandedOff(TaskHandedOff)
    case historyImported(HistoryImported)
    case workRequested(WorkRequested)
    case executionStarted(ExecutionStarted)
    case executionFinished(ExecutionFinished)
    case discussionStarted(DiscussionStarted)
    case discussionFinished(DiscussionFinished)
    case dispatchRequested(DispatchRequested)
    case dispatchAcknowledged(DispatchAcknowledged)
    case dispatchFinished(DispatchFinished)
    case memberAttached(MemberAttached)
    case memberDetached(MemberDetached)

    public var seq: Int { header.seq }
    public var id: String { header.id }
    public var workId: String { header.workId }

    public var header: WorkEventHeader {
        switch self {
        case .chatPosted(let value): value.header
        case .taskCreated(let value): value.header
        case .taskClaimed(let value): value.header
        case .taskAssigned(let value): value.header
        case .taskDelegated(let value): value.header
        case .taskTransitioned(let value): value.header
        case .taskProgressed(let value): value.header
        case .taskHandedOff(let value): value.header
        case .historyImported(let value): value.header
        case .workRequested(let value): value.header
        case .executionStarted(let value): value.header
        case .executionFinished(let value): value.header
        case .discussionStarted(let value): value.header
        case .discussionFinished(let value): value.header
        case .dispatchRequested(let value): value.header
        case .dispatchAcknowledged(let value): value.header
        case .dispatchFinished(let value): value.header
        case .memberAttached(let value): value.header
        case .memberDetached(let value): value.header
        }
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        switch try object.string("type") {
        case "chat.posted": self = .chatPosted(try ChatPosted(protocolJSON: protocolJSON))
        case "task.created": self = .taskCreated(try TaskCreated(protocolJSON: protocolJSON))
        case "task.claimed": self = .taskClaimed(try TaskClaimed(protocolJSON: protocolJSON))
        case "task.assigned": self = .taskAssigned(try TaskAssigned(protocolJSON: protocolJSON))
        case "task.delegated": self = .taskDelegated(try TaskDelegated(protocolJSON: protocolJSON))
        case "task.transitioned": self = .taskTransitioned(try TaskTransitioned(protocolJSON: protocolJSON))
        case "task.progressed": self = .taskProgressed(try TaskProgressed(protocolJSON: protocolJSON))
        case "task.handed_off": self = .taskHandedOff(try TaskHandedOff(protocolJSON: protocolJSON))
        case "history.imported": self = .historyImported(try HistoryImported(protocolJSON: protocolJSON))
        case "work.requested": self = .workRequested(try WorkRequested(protocolJSON: protocolJSON))
        case "execution.started": self = .executionStarted(try ExecutionStarted(protocolJSON: protocolJSON))
        case "execution.finished": self = .executionFinished(try ExecutionFinished(protocolJSON: protocolJSON))
        case "discussion.started": self = .discussionStarted(try DiscussionStarted(protocolJSON: protocolJSON))
        case "discussion.finished": self = .discussionFinished(try DiscussionFinished(protocolJSON: protocolJSON))
        case "dispatch.requested": self = .dispatchRequested(try DispatchRequested(protocolJSON: protocolJSON))
        case "dispatch.acknowledged": self = .dispatchAcknowledged(try DispatchAcknowledged(protocolJSON: protocolJSON))
        case "dispatch.finished": self = .dispatchFinished(try DispatchFinished(protocolJSON: protocolJSON))
        case "member.attached": self = .memberAttached(try MemberAttached(protocolJSON: protocolJSON))
        case "member.detached": self = .memberDetached(try MemberDetached(protocolJSON: protocolJSON))
        default:
            throw ProtocolParseException(["type"], "Invalid enum value")
        }
    }

    public var protocolJSON: JSONValue {
        switch self {
        case .chatPosted(let value): value.protocolJSON
        case .taskCreated(let value): value.protocolJSON
        case .taskClaimed(let value): value.protocolJSON
        case .taskAssigned(let value): value.protocolJSON
        case .taskDelegated(let value): value.protocolJSON
        case .taskTransitioned(let value): value.protocolJSON
        case .taskProgressed(let value): value.protocolJSON
        case .taskHandedOff(let value): value.protocolJSON
        case .historyImported(let value): value.protocolJSON
        case .workRequested(let value): value.protocolJSON
        case .executionStarted(let value): value.protocolJSON
        case .executionFinished(let value): value.protocolJSON
        case .discussionStarted(let value): value.protocolJSON
        case .discussionFinished(let value): value.protocolJSON
        case .dispatchRequested(let value): value.protocolJSON
        case .dispatchAcknowledged(let value): value.protocolJSON
        case .dispatchFinished(let value): value.protocolJSON
        case .memberAttached(let value): value.protocolJSON
        case .memberDetached(let value): value.protocolJSON
        }
    }

    public struct ChatPosted: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var messageId: String
        public var inputAfterSeq: Int?
        public var body: String
        public var mentionedAgentIds: [String]
        public var sourceSessionId: String?
        public var taskId: String?
        public var seq: Int { header.seq }

        public init(header: WorkEventHeader, messageId: String, body: String, mentionedAgentIds: [String], inputAfterSeq: Int? = nil, sourceSessionId: String? = nil, taskId: String? = nil) {
            self.header = header
            self.messageId = messageId
            self.body = body
            self.mentionedAgentIds = mentionedAgentIds
            self.inputAfterSeq = inputAfterSeq
            self.sourceSessionId = sourceSessionId
            self.taskId = taskId
        }

        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            messageId = try object.string("messageId")
            inputAfterSeq = try object.optionalInt("inputAfterSeq")
            body = try object.string("body")
            mentionedAgentIds = try object.stringArray("mentionedAgentIds")
            sourceSessionId = try object.optionalString("sourceSessionId")
            taskId = try object.optionalString("taskId")
        }

        public var protocolJSON: JSONValue {
            header.write("chat.posted") { fields in
                fields.add("messageId", messageId)
                fields.addIfPresent("inputAfterSeq", inputAfterSeq)
                fields.add("body", body)
                fields.add("mentionedAgentIds", .array(mentionedAgentIds.map(JSONValue.string)))
                fields.addIfPresent("sourceSessionId", sourceSessionId)
                fields.addIfPresent("taskId", taskId)
            }
        }
    }

    public struct TaskCreated: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var task: WorkTask
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, task: WorkTask) { self.header = header; self.task = task }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            task = try WorkTask(protocolJSON: object.require("task"))
        }
        public var protocolJSON: JSONValue { header.write("task.created") { $0.add("task", task.protocolJSON) } }
    }

    public struct TaskClaimed: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var taskId: String
        public var assigneeIds: [String]
        public var revision: Int
        public var messageId: String
        public var body: String
        public var sourceSessionId: String?
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, taskId: String, assigneeIds: [String], revision: Int, messageId: String, body: String, sourceSessionId: String? = nil) {
            self.header = header
            self.taskId = taskId
            self.assigneeIds = assigneeIds
            self.revision = revision
            self.messageId = messageId
            self.body = body
            self.sourceSessionId = sourceSessionId
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            taskId = try object.string("taskId")
            assigneeIds = try object.stringArray("assigneeIds")
            revision = try object.int("revision")
            messageId = try object.string("messageId")
            body = try object.string("body")
            sourceSessionId = try object.optionalString("sourceSessionId")
        }
        public var protocolJSON: JSONValue {
            header.write("task.claimed") { fields in
                fields.add("taskId", taskId)
                fields.add("assigneeIds", .array(assigneeIds.map(JSONValue.string)))
                fields.add("revision", revision)
                fields.add("messageId", messageId)
                fields.add("body", body)
                fields.addIfPresent("sourceSessionId", sourceSessionId)
            }
        }
    }

    public struct TaskAssigned: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var taskId: String
        public var assigneeIds: [String]
        public var revision: Int
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, taskId: String, assigneeIds: [String], revision: Int) {
            self.header = header
            self.taskId = taskId
            self.assigneeIds = assigneeIds
            self.revision = revision
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            taskId = try object.string("taskId")
            assigneeIds = try object.stringArray("assigneeIds")
            revision = try object.int("revision")
        }
        public var protocolJSON: JSONValue {
            header.write("task.assigned") { fields in
                fields.add("taskId", taskId)
                fields.add("assigneeIds", .array(assigneeIds.map(JSONValue.string)))
                fields.add("revision", revision)
            }
        }
    }

    public struct TaskDelegated: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var taskId: String
        public var agentId: String
        public var instruction: String
        public var revision: Int
        public var messageId: String
        public var membershipRevision: Int
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, taskId: String, agentId: String, instruction: String, revision: Int, messageId: String, membershipRevision: Int) {
            self.header = header
            self.taskId = taskId
            self.agentId = agentId
            self.instruction = instruction
            self.revision = revision
            self.messageId = messageId
            self.membershipRevision = membershipRevision
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            taskId = try object.string("taskId")
            agentId = try object.string("agentId")
            instruction = try object.string("instruction")
            revision = try object.int("revision")
            messageId = try object.string("messageId")
            membershipRevision = try object.int("membershipRevision")
        }
        public var protocolJSON: JSONValue {
            header.write("task.delegated") { fields in
                fields.add("taskId", taskId)
                fields.add("agentId", agentId)
                fields.add("instruction", instruction)
                fields.add("revision", revision)
                fields.add("messageId", messageId)
                fields.add("membershipRevision", membershipRevision)
            }
        }
    }

    public struct TaskTransitioned: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var taskId: String
        public var from: WorkTaskState
        public var to: WorkTaskState
        public var revision: Int
        public var blocker: WorkTransitionBlocker?
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, taskId: String, from: WorkTaskState, to: WorkTaskState, revision: Int, blocker: WorkTransitionBlocker? = nil) {
            self.header = header
            self.taskId = taskId
            self.from = from
            self.to = to
            self.revision = revision
            self.blocker = blocker
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            taskId = try object.string("taskId")
            from = try object.enumeration("from", as: WorkTaskState.self)
            to = try object.enumeration("to", as: WorkTaskState.self)
            revision = try object.int("revision")
            blocker = try object.optionalObject("blocker").map { try WorkTransitionBlocker(protocolJSON: $0.json) }
        }
        public var protocolJSON: JSONValue {
            header.write("task.transitioned") { fields in
                fields.add("taskId", taskId)
                fields.add("from", from.rawValue)
                fields.add("to", to.rawValue)
                fields.add("revision", revision)
                if let blocker { fields.add("blocker", blocker.protocolJSON) }
            }
        }
    }

    public struct TaskProgressed: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var taskId: String
        public var summary: String
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, taskId: String, summary: String) {
            self.header = header
            self.taskId = taskId
            self.summary = summary
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            taskId = try object.string("taskId")
            summary = try object.string("summary")
        }
        public var protocolJSON: JSONValue {
            header.write("task.progressed") { fields in
                fields.add("taskId", taskId)
                fields.add("summary", summary)
            }
        }
    }

    public struct TaskHandedOff: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var taskId: String
        public var summary: String
        public var deliverables: [WorkDeliverable]
        public var nextStatus: HandoffNextStatus
        public var returnToAgentId: String?
        public var blockerReason: String?
        public var revision: Int
        public var messageId: String?
        public var sourceSessionId: String?
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, taskId: String, summary: String, deliverables: [WorkDeliverable], nextStatus: HandoffNextStatus, revision: Int, returnToAgentId: String? = nil, blockerReason: String? = nil, messageId: String? = nil, sourceSessionId: String? = nil) {
            self.header = header
            self.taskId = taskId
            self.summary = summary
            self.deliverables = deliverables
            self.nextStatus = nextStatus
            self.revision = revision
            self.returnToAgentId = returnToAgentId
            self.blockerReason = blockerReason
            self.messageId = messageId
            self.sourceSessionId = sourceSessionId
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            taskId = try object.string("taskId")
            summary = try object.string("summary")
            deliverables = try object.array("deliverables").map { try WorkDeliverable(protocolJSON: $0) }
            nextStatus = try object.enumeration("nextStatus", as: HandoffNextStatus.self)
            returnToAgentId = try object.optionalString("returnToAgentId")
            blockerReason = try object.optionalString("blockerReason")
            revision = try object.int("revision")
            messageId = try object.optionalString("messageId")
            sourceSessionId = try object.optionalString("sourceSessionId")
        }
        public var protocolJSON: JSONValue {
            header.write("task.handed_off") { fields in
                fields.add("taskId", taskId)
                fields.add("summary", summary)
                fields.add("deliverables", .array(deliverables.map(\.protocolJSON)))
                fields.add("nextStatus", nextStatus.rawValue)
                fields.addIfPresent("returnToAgentId", returnToAgentId)
                fields.addIfPresent("blockerReason", blockerReason)
                fields.add("revision", revision)
                fields.addIfPresent("messageId", messageId)
                fields.addIfPresent("sourceSessionId", sourceSessionId)
            }
        }
    }

    public struct HistoryImported: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var unconfirmedEventIds: [String]
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, unconfirmedEventIds: [String]) {
            self.header = header
            self.unconfirmedEventIds = unconfirmedEventIds
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            unconfirmedEventIds = try object.stringArray("unconfirmedEventIds")
        }
        public var protocolJSON: JSONValue {
            header.write("history.imported") { $0.add("unconfirmedEventIds", .array(unconfirmedEventIds.map(JSONValue.string))) }
        }
    }

    public struct WorkRequested: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var agentId: String
        public var taskId: String?
        public var instruction: String
        public var membershipRevision: Int
        public var resumesExecutionId: String?
        public var inputAfterSeq: Int?
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, agentId: String, instruction: String, membershipRevision: Int, taskId: String? = nil, resumesExecutionId: String? = nil, inputAfterSeq: Int? = nil) {
            self.header = header
            self.agentId = agentId
            self.instruction = instruction
            self.membershipRevision = membershipRevision
            self.taskId = taskId
            self.resumesExecutionId = resumesExecutionId
            self.inputAfterSeq = inputAfterSeq
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            agentId = try object.string("agentId")
            taskId = try object.optionalString("taskId")
            instruction = try object.string("instruction")
            membershipRevision = try object.int("membershipRevision")
            resumesExecutionId = try object.optionalString("resumesExecutionId")
            inputAfterSeq = try object.optionalInt("inputAfterSeq")
        }
        public var protocolJSON: JSONValue {
            header.write("work.requested") { fields in
                fields.add("agentId", agentId)
                fields.addIfPresent("taskId", taskId)
                fields.add("instruction", instruction)
                fields.add("membershipRevision", membershipRevision)
                fields.addIfPresent("resumesExecutionId", resumesExecutionId)
                fields.addIfPresent("inputAfterSeq", inputAfterSeq)
            }
        }
    }

    public struct ExecutionStarted: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var executionId: String
        public var sourceEventId: String
        public var agentId: String
        public var taskId: String?
        public var sessionId: String
        public var runId: String
        public var membershipRevision: Int
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, executionId: String, sourceEventId: String, agentId: String, sessionId: String, runId: String, membershipRevision: Int, taskId: String? = nil) {
            self.header = header
            self.executionId = executionId
            self.sourceEventId = sourceEventId
            self.agentId = agentId
            self.sessionId = sessionId
            self.runId = runId
            self.membershipRevision = membershipRevision
            self.taskId = taskId
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            executionId = try object.string("executionId")
            sourceEventId = try object.string("sourceEventId")
            agentId = try object.string("agentId")
            taskId = try object.optionalString("taskId")
            sessionId = try object.string("sessionId")
            runId = try object.string("runId")
            membershipRevision = try object.int("membershipRevision")
        }
        public var protocolJSON: JSONValue {
            header.write("execution.started") { fields in
                fields.add("executionId", executionId)
                fields.add("sourceEventId", sourceEventId)
                fields.add("agentId", agentId)
                fields.addIfPresent("taskId", taskId)
                fields.add("sessionId", sessionId)
                fields.add("runId", runId)
                fields.add("membershipRevision", membershipRevision)
            }
        }
    }

    public struct ExecutionFinished: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var executionId: String
        public var sourceEventId: String
        public var agentId: String
        public var taskId: String?
        public var status: ExecutionFinishStatus
        public var error: String?
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, executionId: String, sourceEventId: String, agentId: String, status: ExecutionFinishStatus, taskId: String? = nil, error: String? = nil) {
            self.header = header
            self.executionId = executionId
            self.sourceEventId = sourceEventId
            self.agentId = agentId
            self.status = status
            self.taskId = taskId
            self.error = error
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            executionId = try object.string("executionId")
            sourceEventId = try object.string("sourceEventId")
            agentId = try object.string("agentId")
            taskId = try object.optionalString("taskId")
            status = try object.enumeration("status", as: ExecutionFinishStatus.self)
            error = try object.optionalString("error")
        }
        public var protocolJSON: JSONValue {
            header.write("execution.finished") { fields in
                fields.add("executionId", executionId)
                fields.add("sourceEventId", sourceEventId)
                fields.add("agentId", agentId)
                fields.addIfPresent("taskId", taskId)
                fields.add("status", status.rawValue)
                fields.addIfPresent("error", error)
            }
        }
    }

    public struct DiscussionStarted: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var triggerEventIds: [String]
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, triggerEventIds: [String]) {
            self.header = header
            self.triggerEventIds = triggerEventIds
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            triggerEventIds = try object.stringArray("triggerEventIds")
        }
        public var protocolJSON: JSONValue {
            header.write("discussion.started") { $0.add("triggerEventIds", .array(triggerEventIds.map(JSONValue.string))) }
        }
    }

    public struct DiscussionFinished: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var discussionId: String
        public var status: DiscussionFinishStatus
        public var error: String?
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, discussionId: String, status: DiscussionFinishStatus, error: String? = nil) {
            self.header = header
            self.discussionId = discussionId
            self.status = status
            self.error = error
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            discussionId = try object.string("discussionId")
            status = try object.enumeration("status", as: DiscussionFinishStatus.self)
            error = try object.optionalString("error")
        }
        public var protocolJSON: JSONValue {
            header.write("discussion.finished") { fields in
                fields.add("discussionId", discussionId)
                fields.add("status", status.rawValue)
                fields.addIfPresent("error", error)
            }
        }
    }

    public struct DispatchRequested: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var bridgeId: String
        public var agentId: String
        public var taskId: String?
        public var instruction: String
        public var membershipRevision: Int?
        public var discussion: DispatchDiscussion?
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, bridgeId: String, agentId: String, instruction: String, taskId: String? = nil, membershipRevision: Int? = nil, discussion: DispatchDiscussion? = nil) {
            self.header = header
            self.bridgeId = bridgeId
            self.agentId = agentId
            self.instruction = instruction
            self.taskId = taskId
            self.membershipRevision = membershipRevision
            self.discussion = discussion
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            bridgeId = try object.string("bridgeId")
            agentId = try object.string("agentId")
            taskId = try object.optionalString("taskId")
            instruction = try object.string("instruction")
            membershipRevision = try object.optionalInt("membershipRevision")
            discussion = try object.optionalObject("discussion").map { try DispatchDiscussion(protocolJSON: $0.json) }
        }
        public var protocolJSON: JSONValue {
            header.write("dispatch.requested") { fields in
                fields.add("bridgeId", bridgeId)
                fields.add("agentId", agentId)
                fields.addIfPresent("taskId", taskId)
                fields.add("instruction", instruction)
                fields.addIfPresent("membershipRevision", membershipRevision)
                if let discussion { fields.add("discussion", discussion.protocolJSON) }
            }
        }
    }

    public struct DispatchAcknowledged: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var bridgeId: String
        public var agentId: String
        public var transcriptEventId: String
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, bridgeId: String, agentId: String, transcriptEventId: String) {
            self.header = header
            self.bridgeId = bridgeId
            self.agentId = agentId
            self.transcriptEventId = transcriptEventId
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            bridgeId = try object.string("bridgeId")
            agentId = try object.string("agentId")
            transcriptEventId = try object.string("transcriptEventId")
        }
        public var protocolJSON: JSONValue {
            header.write("dispatch.acknowledged") { fields in
                fields.add("bridgeId", bridgeId)
                fields.add("agentId", agentId)
                fields.add("transcriptEventId", transcriptEventId)
            }
        }
    }

    public struct DispatchFinished: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var bridgeId: String
        public var agentId: String
        public var status: ExecutionFinishStatus
        public var error: String?
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, bridgeId: String, agentId: String, status: ExecutionFinishStatus, error: String? = nil) {
            self.header = header
            self.bridgeId = bridgeId
            self.agentId = agentId
            self.status = status
            self.error = error
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            bridgeId = try object.string("bridgeId")
            agentId = try object.string("agentId")
            status = try object.enumeration("status", as: ExecutionFinishStatus.self)
            error = try object.optionalString("error")
        }
        public var protocolJSON: JSONValue {
            header.write("dispatch.finished") { fields in
                fields.add("bridgeId", bridgeId)
                fields.add("agentId", agentId)
                fields.add("status", status.rawValue)
                fields.addIfPresent("error", error)
            }
        }
    }

    public struct MemberAttached: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var membershipOperationId: String
        public var agentId: String
        public var role: WorkRole
        public var membershipRevision: Int
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, membershipOperationId: String, agentId: String, role: WorkRole, membershipRevision: Int) {
            self.header = header
            self.membershipOperationId = membershipOperationId
            self.agentId = agentId
            self.role = role
            self.membershipRevision = membershipRevision
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            membershipOperationId = try object.string("membershipOperationId")
            agentId = try object.string("agentId")
            role = try object.enumeration("role", as: WorkRole.self)
            membershipRevision = try object.int("membershipRevision")
        }
        public var protocolJSON: JSONValue {
            header.write("member.attached") { fields in
                fields.add("membershipOperationId", membershipOperationId)
                fields.add("agentId", agentId)
                fields.add("role", role.rawValue)
                fields.add("membershipRevision", membershipRevision)
            }
        }
    }

    public struct MemberDetached: WireRepresentable, Sendable, Equatable {
        public var header: WorkEventHeader
        public var membershipOperationId: String
        public var agentId: String
        public var membershipRevision: Int
        public var seq: Int { header.seq }
        public init(header: WorkEventHeader, membershipOperationId: String, agentId: String, membershipRevision: Int) {
            self.header = header
            self.membershipOperationId = membershipOperationId
            self.agentId = agentId
            self.membershipRevision = membershipRevision
        }
        public init(protocolJSON: JSONValue) throws {
            let object = try JSONObject(protocolJSON)
            header = try WorkEventHeader(object)
            membershipOperationId = try object.string("membershipOperationId")
            agentId = try object.string("agentId")
            membershipRevision = try object.int("membershipRevision")
        }
        public var protocolJSON: JSONValue {
            header.write("member.detached") { fields in
                fields.add("membershipOperationId", membershipOperationId)
                fields.add("agentId", agentId)
                fields.add("membershipRevision", membershipRevision)
            }
        }
    }
}

public struct WorkProjection: Sendable, Equatable {
    public var tasks: [WorkTask]
    public var chat: [WorkEvent.ChatPosted]

    public init(tasks: [WorkTask], chat: [WorkEvent.ChatPosted]) {
        self.tasks = tasks
        self.chat = chat
    }
}
