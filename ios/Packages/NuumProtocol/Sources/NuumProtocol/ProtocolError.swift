import Foundation

public struct ProtocolIssue: Error, Sendable, Equatable {
    public let path: [String]
    public let message: String

    public init(path: [String], message: String) {
        self.path = path
        self.message = message
    }
}

/// Validation failure. `message` matches the compact Zod sentence returned to the model:
/// `path: message`, joined with `"; "` when more than one field is wrong.
public struct ProtocolParseException: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    public let issues: [ProtocolIssue]

    public init(_ issues: [ProtocolIssue]) {
        self.issues = issues
    }

    public init(_ path: [String], _ message: String) {
        self.issues = [ProtocolIssue(path: path, message: message)]
    }

    public init(_ path: String, _ message: String) {
        let parts = path.split(separator: ".").map(String.init)
        self.issues = [ProtocolIssue(path: parts, message: message)]
    }

    public var message: String { Self.compact(issues) }

    public var description: String { message }

    public var errorDescription: String? { message }

    public static func compact(_ issues: [ProtocolIssue]) -> String {
        issues.map { issue in
            let path = issue.path.isEmpty ? "(root)" : issue.path.joined(separator: ".")
            return "\(path): \(issue.message)"
        }.joined(separator: "; ")
    }
}

/// Same shape the host returns to the model: `Tool: invalid arguments — path: message`.
public func toolArgumentError(toolName: String, error: ProtocolParseException) -> String {
    "\(toolName): invalid arguments — \(error.message)"
}
