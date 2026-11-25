public struct ProactivePolicy: Sendable, Equatable {
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
        intervalMs: Int64 = 300_000
    ) {
        self.revision = revision
        self.isDefault = isDefault
        self.enabled = enabled
        self.pausedUntil = pausedUntil
        self.sourceIds = sourceIds
        self.intervalMs = intervalMs
    }
}

public struct ProactiveConfigureParams: Sendable, Equatable {
    public var expectedRevision: Int
    public var agentId: String?
    public var enabled: Bool?
    public var pausedUntil: Int64?
    public var resume: Bool
    public var sourceIds: [String]?
    public var intervalMs: Int64?

    public init(
        expectedRevision: Int,
        agentId: String? = nil,
        enabled: Bool? = nil,
        pausedUntil: Int64? = nil,
        resume: Bool = false,
        sourceIds: [String]? = nil,
        intervalMs: Int64? = nil
    ) {
        self.expectedRevision = expectedRevision
        self.agentId = agentId
        self.enabled = enabled
        self.pausedUntil = pausedUntil
        self.resume = resume
        self.sourceIds = sourceIds
        self.intervalMs = intervalMs
    }
}

public struct ProactiveActivity: Sendable, Equatable {
    public var id: String
    public var at: Int64
    public var kind: String
    public var contextRefs: [String]

    public init(id: String, at: Int64, kind: String, contextRefs: [String] = []) {
        self.id = id
        self.at = at
        self.kind = kind
        self.contextRefs = contextRefs
    }
}

public struct ProactiveAgentSnapshot: Sendable, Equatable {
    public var agentId: String
    public var name: String
    public var policy: ProactivePolicy
    public var state: String
    public var activity: [ProactiveActivity]

    public init(
        agentId: String,
        name: String,
        policy: ProactivePolicy,
        state: String,
        activity: [ProactiveActivity]
    ) {
        self.agentId = agentId
        self.name = name
        self.policy = policy
        self.state = state
        self.activity = activity
    }
}

/// `actionsAvailable` stays false until a real action executor exists.
/// UI reads the snapshot.
public struct ProactiveSnapshot: Sendable, Equatable {
    public var defaultAgentId: String?
    public var agents: [ProactiveAgentSnapshot]
    public var availableSourceIds: [String]
    public var actionsAvailable: Bool

    public init(
        defaultAgentId: String?,
        agents: [ProactiveAgentSnapshot],
        availableSourceIds: [String],
        actionsAvailable: Bool = false
    ) {
        self.defaultAgentId = defaultAgentId
        self.agents = agents
        self.availableSourceIds = availableSourceIds
        self.actionsAvailable = actionsAvailable
    }
}
