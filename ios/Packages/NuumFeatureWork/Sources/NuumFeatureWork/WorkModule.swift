import NuumProtocol

/// Room and NunuBar surface. WP-12 places it in the shell content column.
public enum NuumFeatureWorkModule {
    public static let name = "NuumFeatureWork"
    public static let protocolModule = NuumProtocolModule.name

    /// Room discussion stops at 3 rounds, 10 messages, and 2 messages per turn.
    /// Those numbers are `discussionLimits` in NuumAgent. This package does not
    /// start model turns and does not apply a different budget. Continue and stop
    /// go through `WorkPort`.
    public static let discussionBudgetOwnedByAgent = true
}
