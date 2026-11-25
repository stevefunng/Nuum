import NuumContracts

/// One-to-one conversation surface. Room lanes and NunuBar stay in `NuumFeatureWork`.
public enum NuumFeatureConversationModule {
    public static let name = "NuumFeatureConversation"
    public static let attachmentCap = AttachmentLimits.maxCount
    public static let drawsNunuBar = false
    /// Room interruptions are drawn by the work surface, not this package.
    public static let showsDiscussionInterruption = false
}
