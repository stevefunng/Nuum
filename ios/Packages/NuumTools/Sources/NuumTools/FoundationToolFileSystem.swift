import Foundation
import NuumContracts

/// App-container and bookmark paths. Symlinks are resolved so a link cannot hide an escape.
/// `unauthorizedRoots` are bookmark trees whose access has not been started. Paths inside them
/// fail closed as outside the allowed root.
final class FoundationToolFileSystem: ToolFileSystem, @unchecked Sendable {
    private let unauthorizedRoots: [String]

    init(unauthorizedRoots: [String] = []) {
        self.unauthorizedRoots = unauthorizedRoots.map { root in
            let lexical = lexicalNormalize(root)
            return FoundationToolFileSystem.resolveExistingPrefix(lexical)
        }
    }

    func canonicalize(cwd: String, input: String) -> String {
        let combined: String
        if input.hasPrefix("/") {
            combined = input
        } else {
            combined = joinPath(cwd, input)
        }
        return Self.resolveExistingPrefix(lexicalNormalize(combined))
    }

    func lacksAccess(_ path: String) -> Bool {
        unauthorizedRoots.contains { pathContains($0, path) }
    }

    func exists(_ path: String) -> Bool {
        if symlinkDestination(path) != nil { return true }
        return FileManager.default.fileExists(atPath: path)
    }

    func isDirectory(_ path: String) -> Bool {
        if symlinkDestination(path) != nil { return false }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func isSymlink(_ path: String) -> Bool {
        symlinkDestination(path) != nil
    }

    func readBytes(_ path: String) throws -> Data {
        if !exists(path) { throw MissingPath(path: path) }
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw NuumError(code: KernelErrorCode.tool, message: "Couldn't read file: \(path).")
        }
    }

    func writeBytes(_ path: String, _ bytes: Data) throws {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        if parent.path != url.path {
            do {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                throw NuumError(code: KernelErrorCode.tool, message: "Couldn't write file: \(path).")
            }
        }
        do {
            try bytes.write(to: url, options: .atomic)
        } catch {
            throw NuumError(code: KernelErrorCode.tool, message: "Couldn't write file: \(path).")
        }
    }

    func list(_ path: String) throws -> [ToolDirEntry] {
        if !exists(path) { throw MissingPath(path: path) }
        if !isDirectory(path) { return [] }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: path)
        } catch {
            throw MissingPath(path: path)
        }
        return names.map { name in
            let child = joinPath(path, name)
            let link = isSymlink(child)
            return ToolDirEntry(
                name: name,
                isDirectory: !link && isDirectory(child),
                isSymlink: link
            )
        }
    }

    func delete(_ path: String) throws {
        if !exists(path) { throw MissingPath(path: path) }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            throw NuumError(code: KernelErrorCode.tool, message: "Couldn't delete \(path).")
        }
    }

    func lastModifiedMillis(_ path: String) throws -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard let date = attributes[.modificationDate] as? Date else { return 0 }
            return Int64((date.timeIntervalSince1970 * 1000.0).rounded())
        } catch {
            throw MissingPath(path: path)
        }
    }

    private func symlinkDestination(_ path: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    /// Longest existing prefix is resolved, then the missing suffix is appended.
    /// An existing symlink is followed, so the policy sees the real target.
    private static func resolveExistingPrefix(_ lexical: String) -> String {
        var cursor = lexical
        while true {
            if let resolved = resolveIfExists(cursor) {
                let rest = suffix(after: cursor, in: lexical)
                if rest.isEmpty { return resolved }
                return lexicalNormalize(joinPath(resolved, rest))
            }
            let parent = parentPath(cursor)
            if parent == cursor { return lexical }
            cursor = parent
        }
    }

    private static func resolveIfExists(_ path: String, hops: Int = 0) -> String? {
        if hops > 40 { return nil }
        let parts = path.split(separator: "/").map(String.init)
        var current = "/"
        for (index, part) in parts.enumerated() {
            let next = joinPath(current, part)
            if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: next) {
                let resolvedBase = destination.hasPrefix("/") ? destination : joinPath(current, destination)
                let rest = parts[(index + 1)...].joined(separator: "/")
                let combined = rest.isEmpty ? resolvedBase : joinPath(resolvedBase, rest)
                return resolveIfExists(lexicalNormalize(combined), hops: hops + 1)
            }
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: next, isDirectory: &isDirectory) {
                return nil
            }
            current = next
        }
        return lexicalNormalize(current)
    }

    private static func suffix(after cursor: String, in full: String) -> String {
        if cursor == full { return "" }
        let prefix = cursor == "/" ? "/" : cursor + "/"
        guard full.hasPrefix(prefix) else { return "" }
        return String(full.dropFirst(prefix.count))
    }
}
