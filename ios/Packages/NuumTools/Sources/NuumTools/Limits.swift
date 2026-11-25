enum ToolLimits {
    static let maxReadChars = 30_000
    static let maxTreeChars = 20_000
    static let maxDiffChars = 12_000
    static let maxGlobResults = 500
    static let maxGrepOutput = 500_000
}

/// Returned when a path is outside home, scratch, and the granted project.
let outsideRoot = "Path is outside the allowed local execution root."

let protectedStore = "Path is inside a protected host-only store."
