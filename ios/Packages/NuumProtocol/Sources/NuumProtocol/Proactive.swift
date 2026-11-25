import Foundation

public let proactiveIntervalMinMs: Int64 = 60_000
public let proactiveIntervalMaxMs: Int64 = 3_600_000
public let proactiveIntervalDefaultMs: Int64 = 300_000
public let proactiveMaxSources = 20
public let duplicateContextSource = "Duplicate context source"

public struct ProactivePolicy: WireRepresentable, Sendable, Equatable {
    public var revision: Int
    public var isDefault: Bool
    public var enabled: Bool
    public var pausedUntil: Int64?
    public var sourceIds: [String]
    public var intervalMs: Int64

    public init(
        revision: Int,
        isDefault: Bool = false,
        enabled: Bool = false,
        pausedUntil: Int64? = nil,
        sourceIds: [String] = [],
        intervalMs: Int64 = proactiveIntervalDefaultMs
    ) {
        self.revision = revision
        self.isDefault = isDefault
        self.enabled = enabled
        self.pausedUntil = pausedUntil
        self.sourceIds = sourceIds
        self.intervalMs = intervalMs
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        revision = try object.int("revision")
        isDefault = try object.optionalBool("isDefault") ?? false
        enabled = try object.optionalBool("enabled") ?? false
        pausedUntil = try object.optionalInt64("pausedUntil")
        sourceIds = try object.stringArray("sourceIds")
        intervalMs = try object.optionalInt64("intervalMs") ?? proactiveIntervalDefaultMs
        try validateProactivePolicy(self)
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("revision", revision)
        fields.add("isDefault", isDefault)
        fields.add("enabled", enabled)
        if let pausedUntil { fields.add("pausedUntil", pausedUntil) }
        fields.add("sourceIds", .array(sourceIds.map(JSONValue.string)))
        fields.add("intervalMs", intervalMs)
        return fields.json
    }
}

public struct ProactiveConfigureParams: WireRepresentable, Sendable, Equatable {
    public var agentId: String?
    public var expectedRevision: Int
    public var enabled: Bool?
    public var pausedUntil: Int64?
    public var sourceIds: [String]?
    public var intervalMs: Int64?

    public init(
        expectedRevision: Int,
        agentId: String? = nil,
        enabled: Bool? = nil,
        pausedUntil: Int64? = nil,
        sourceIds: [String]? = nil,
        intervalMs: Int64? = nil
    ) {
        self.expectedRevision = expectedRevision
        self.agentId = agentId
        self.enabled = enabled
        self.pausedUntil = pausedUntil
        self.sourceIds = sourceIds
        self.intervalMs = intervalMs
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        agentId = try object.optionalString("agentId")
        expectedRevision = try object.int("expectedRevision")
        enabled = try object.optionalBool("enabled")
        pausedUntil = try object.optionalInt64("pausedUntil")
        sourceIds = try object.optionalStringArray("sourceIds")
        intervalMs = try object.optionalInt64("intervalMs")
        try validateProactiveConfigure(self)
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.addIfPresent("agentId", agentId)
        fields.add("expectedRevision", expectedRevision)
        fields.addIfPresent("enabled", enabled)
        if let pausedUntil { fields.add("pausedUntil", pausedUntil) }
        if let sourceIds { fields.add("sourceIds", .array(sourceIds.map(JSONValue.string))) }
        if let intervalMs { fields.add("intervalMs", intervalMs) }
        return fields.json
    }
}

public struct ProactiveCheckParams: WireRepresentable, Sendable, Equatable {
    public var agentId: String

    public init(agentId: String) {
        self.agentId = agentId
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        agentId = try object.string("agentId")
        if agentId.isEmpty {
            throw ProtocolParseException(["agentId"], "String must contain at least 1 character(s)")
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("agentId", agentId)
        return fields.json
    }
}

public enum ProactiveActivityKind: String, Sendable, Equatable, Codable, CaseIterable {
    case enabled
    case disabled
    case paused
    case resumed
    case configured
    case waitingContext = "waiting-context"
    case contextReady = "context-ready"
    case noChange = "no-change"
    case error
}

public struct ProactiveActivity: WireRepresentable, Sendable, Equatable {
    public var id: String
    public var at: Int64
    public var kind: ProactiveActivityKind
    public var contextRefs: [String]

    public init(id: String, at: Int64, kind: ProactiveActivityKind, contextRefs: [String] = []) {
        self.id = id
        self.at = at
        self.kind = kind
        self.contextRefs = contextRefs
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        id = try object.string("id")
        at = try object.int64("at")
        kind = try object.enumeration("kind", as: ProactiveActivityKind.self)
        contextRefs = try object.stringArray("contextRefs")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("id", id)
        fields.add("at", at)
        fields.add("kind", kind.rawValue)
        fields.add("contextRefs", .array(contextRefs.map(JSONValue.string)))
        return fields.json
    }
}

public enum ProactiveAgentState: String, Sendable, Equatable, Codable, CaseIterable {
    case disabled
    case paused
    case waitingContext = "waiting-context"
    case ready
    case checking
    case error
}

public struct ProactiveAgentSnapshot: WireRepresentable, Sendable, Equatable {
    public var agentId: String
    public var name: String
    public var policy: ProactivePolicy
    public var state: ProactiveAgentState
    public var activity: [ProactiveActivity]

    public init(
        agentId: String,
        name: String,
        policy: ProactivePolicy,
        state: ProactiveAgentState,
        activity: [ProactiveActivity]
    ) {
        self.agentId = agentId
        self.name = name
        self.policy = policy
        self.state = state
        self.activity = activity
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        agentId = try object.string("agentId")
        name = try object.string("name")
        policy = try ProactivePolicy(protocolJSON: object.require("policy"))
        state = try object.enumeration("state", as: ProactiveAgentState.self)
        activity = try object.array("activity").map { try ProactiveActivity(protocolJSON: $0) }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("agentId", agentId)
        fields.add("name", name)
        fields.add("policy", policy.protocolJSON)
        fields.add("state", state.rawValue)
        fields.add("activity", .array(activity.map(\.protocolJSON)))
        return fields.json
    }
}

/// `actionsAvailable` is the literal `false`. The snapshot cannot represent a
/// future in which actions run; that stays false until an executor exists.
public struct ProactiveSnapshot: WireRepresentable, Sendable, Equatable {
    public var defaultAgentId: String?
    public var agents: [ProactiveAgentSnapshot]
    public var availableSourceIds: [String]
    public var actionsAvailable: Bool

    public init(
        defaultAgentId: String?,
        agents: [ProactiveAgentSnapshot],
        availableSourceIds: [String],
        actionsAvailable: Bool
    ) throws {
        guard actionsAvailable == false else {
            throw ProtocolParseException(["actionsAvailable"], "actionsAvailable must be false")
        }
        self.defaultAgentId = defaultAgentId
        self.agents = agents
        self.availableSourceIds = availableSourceIds
        self.actionsAvailable = false
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        let defaultAgentId = try object.nullableString("defaultAgentId")
        let agents = try object.array("agents").map { try ProactiveAgentSnapshot(protocolJSON: $0) }
        let availableSourceIds = try object.stringArray("availableSourceIds")
        guard object.contains("actionsAvailable") else {
            throw ProtocolParseException(["actionsAvailable"], "actionsAvailable must be false")
        }
        let actionsAvailable = try object.bool("actionsAvailable")
        try self.init(
            defaultAgentId: defaultAgentId,
            agents: agents,
            availableSourceIds: availableSourceIds,
            actionsAvailable: actionsAvailable
        )
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("defaultAgentId", defaultAgentId.map(JSONValue.string) ?? .null)
        fields.add("agents", .array(agents.map(\.protocolJSON)))
        fields.add("availableSourceIds", .array(availableSourceIds.map(JSONValue.string)))
        fields.add("actionsAvailable", false)
        return fields.json
    }
}

public func validateProactivePolicy(_ policy: ProactivePolicy) throws {
    var issues: [ProtocolIssue] = []
    if policy.revision < 0 {
        issues.append(ProtocolIssue(path: ["revision"], message: "Number must be greater than or equal to 0"))
    }
    validateSourceIds(policy.sourceIds, &issues)
    validateInterval(policy.intervalMs, &issues)
    if let paused = policy.pausedUntil, paused < 0 {
        issues.append(ProtocolIssue(path: ["pausedUntil"], message: "Number must be greater than or equal to 0"))
    }
    if !issues.isEmpty { throw ProtocolParseException(issues) }
}

public func validateProactiveConfigure(_ params: ProactiveConfigureParams) throws {
    var issues: [ProtocolIssue] = []
    if params.expectedRevision < 0 {
        issues.append(ProtocolIssue(path: ["expectedRevision"], message: "Number must be greater than or equal to 0"))
    }
    if let id = params.agentId, id.isEmpty {
        issues.append(ProtocolIssue(path: ["agentId"], message: "String must contain at least 1 character(s)"))
    }
    if let sourceIds = params.sourceIds {
        validateSourceIds(sourceIds, &issues)
    }
    if let interval = params.intervalMs {
        validateInterval(interval, &issues)
    }
    if let paused = params.pausedUntil, paused < 0 {
        issues.append(ProtocolIssue(path: ["pausedUntil"], message: "Number must be greater than or equal to 0"))
    }
    if !issues.isEmpty { throw ProtocolParseException(issues) }
}

private func validateSourceIds(_ ids: [String], _ issues: inout [ProtocolIssue]) {
    if ids.count > proactiveMaxSources {
        issues.append(ProtocolIssue(path: ["sourceIds"], message: "Array must contain at most 20 element(s)"))
    }
    for (index, id) in ids.enumerated() where id.isEmpty {
        issues.append(ProtocolIssue(path: ["sourceIds", String(index)], message: "String must contain at least 1 character(s)"))
    }
    if Set(ids).count != ids.count {
        issues.append(ProtocolIssue(path: ["sourceIds"], message: duplicateContextSource))
    }
}

private func validateInterval(_ intervalMs: Int64, _ issues: inout [ProtocolIssue]) {
    if intervalMs < proactiveIntervalMinMs {
        issues.append(ProtocolIssue(path: ["intervalMs"], message: "Number must be greater than or equal to 60000"))
    } else if intervalMs > proactiveIntervalMaxMs {
        issues.append(ProtocolIssue(path: ["intervalMs"], message: "Number must be less than or equal to 3600000"))
    }
}
