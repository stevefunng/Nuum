import Foundation

struct MissingPath: Error, Equatable {
    var path: String
}

struct ToolDirEntry: Equatable, Sendable {
    var name: String
    var isDirectory: Bool
    var isSymlink: Bool
}

/// Byte port used by the sandbox. Tests substitute an in-memory tree.
/// `lacksAccess` is true for a user-picked tree whose bookmark has not been started.
protocol ToolFileSystem: Sendable {
    func canonicalize(cwd: String, input: String) -> String
    func lacksAccess(_ path: String) -> Bool
    func exists(_ path: String) -> Bool
    func isDirectory(_ path: String) -> Bool
    func isSymlink(_ path: String) -> Bool
    func readBytes(_ path: String) throws -> Data
    func writeBytes(_ path: String, _ bytes: Data) throws
    func list(_ path: String) throws -> [ToolDirEntry]
    func delete(_ path: String) throws
    func lastModifiedMillis(_ path: String) throws -> Int64
}
