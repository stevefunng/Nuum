import Foundation

/// Room discussion policy. These three numbers live here, not in protocol.
public struct DiscussionLimits: Sendable, Equatable {
    public var rounds: Int
    public var messages: Int
    public var perTurn: Int

    public init(rounds: Int, messages: Int, perTurn: Int) {
        self.rounds = rounds
        self.messages = messages
        self.perTurn = perTurn
    }
}

public let discussionLimits = DiscussionLimits(rounds: 3, messages: 10, perTurn: 2)

public let defaultMaxConcurrentRuns = 3

/// A user wake is 0 hops. An agent wake is parent + 1.
public let maxHops = 3

/// Same ordered pair (from, to) per minute.
public let wakeRateLimit = 3
public let wakeRateWindowMs: Int64 = 60_000

/// One new teammate per turn. Creation is not approval-gated, so the cap is hard.
public let maxCreatesPerRun = 1

public let maxAgents = 50

public let profileFactLimit = 100
public let recallBudget = 4_000
public let halfLifeDays = 30.0

/// Unknown models use the same window. Do not guess a provider's real length.
public let defaultContextWindow = 128_000

public let compactionRatio = 0.75

public let runWorkCLIUnimplemented =
    "This version of Nuum has no local executable. RunWorkCLI is not implemented."

public let maxAgentsMessage =
    "Refused: there are already \(maxAgents) agents. Ask the user to delete one first."
