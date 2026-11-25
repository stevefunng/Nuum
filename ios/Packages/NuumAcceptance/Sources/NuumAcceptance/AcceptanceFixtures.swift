/// Strings the debug router in `App/Graph/DebugModelPort.swift` already understands.
/// A later Mac types them into the composer. This package does not send them anywhere.
public enum AcceptanceFixture {
    /// Obvious stand-in. Not a provider credential. Search the container for it; do not print a match.
    public static let plantedKey = "sk-acceptance-not-a-real-key"

    public static let visibleReply = "Visible from SendMessage"
    public static let scratchpad = "scratchpad-not-the-body"
    public static let noteText = "accepted-note"
    public static let laneCard = "Lane card"
    public static let continuedReply = "continued after interrupt"
    public static let keptReply = "kept"

    /// User text that makes the debug router call `write` on `outside-scratch.txt`.
    public static let writeCue = "acceptance-write"

    /// User text that makes the debug router call `write` on the sealed JSON name under the data root.
    public static let sealedCue = "acceptance-secrets"

    public static let outsideScratchRelative = "outside-scratch.txt"

    /// Filename the router targets. iOS does not store keys in a file of this name.
    public static let sealedJSONName = "secrets.json"

    public static let fakeModelArgument = "nuum.fakeModel=router"
    public static let fakeModelEnvironment = "NUUM_FAKE_MODEL"
    public static let fakeModelEnvironmentValue = "router"

    public static let missingKeyCode = 2004
    public static let attachmentCode = 1007
    public static let missingKeyFragment = "API key"
    public static let deniedSentence = "User denied this tool call."
    public static let protectedFragment = "protected"
    public static let outsideFragment = "outside"
    public static let permissionDeniedFragment = "Permission denied"

    public static let maxAttachments = 5
    public static let maxAttachmentBytes = 10 * 1024 * 1024
    public static let maxAttachmentTotalBytes = 20 * 1024 * 1024

    public static let bundleID = "com.nuum"

    /// Labels a Room or NunuBar screen must not offer as a manual create-task control.
    public static let manualTaskLabels = [
        "New task",
        "Create task",
        "A new task",
        "新建任务",
        "创建任务",
    ]
}

public enum ScenarioExecution: String, Sendable, Equatable {
    /// No Xcode, simulator, or device pass has been recorded for this scenario.
    case notExecutedOnMac
}

public struct AcceptanceScenario: Sendable, Equatable {
    public let number: Int
    public let title: String
    public let execution: ScenarioExecution

    public init(number: Int, title: String, execution: ScenarioExecution = .notExecutedOnMac) {
        self.number = number
        self.title = title
        self.execution = execution
    }
}

public enum AcceptanceScenarios {
    public static let all: [AcceptanceScenario] = [
        AcceptanceScenario(number: 1, title: "Cold start"),
        AcceptanceScenario(number: 2, title: "Create a Nunu"),
        AcceptanceScenario(number: 3, title: "Send with no API key"),
        AcceptanceScenario(number: 4, title: "SendMessage is the visible body"),
        AcceptanceScenario(number: 5, title: "Write approval and Keychain"),
        AcceptanceScenario(number: 6, title: "Attachments over the limit"),
        AcceptanceScenario(number: 7, title: "Room, upgrade, and CreateTask"),
        AcceptanceScenario(number: 8, title: "Interrupt a discussion, then continue"),
        AcceptanceScenario(number: 9, title: "Kill the process and reopen"),
        AcceptanceScenario(number: 10, title: "Language, theme, and Proactive"),
        AcceptanceScenario(number: 11, title: "Backup exclusion"),
        AcceptanceScenario(number: 12, title: "Release build"),
    ]
}
