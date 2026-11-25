import Foundation
import NuumContracts
@testable import NuumTools

/// In-memory tree. Paths are absolute and `/`-separated. Symlinks are not modeled.
final class MemoryToolFileSystem: ToolFileSystem, @unchecked Sendable {
    private var files: [String: Data] = [:]
    private var directories: Set<String> = ["/"]
    private var modified: [String: Int64] = [:]
    private var clock: Int64 = 1
    var unauthorizedRoots: [String] = []

    func seed(_ path: String, _ text: String, modifiedAt: Int64? = nil) {
        seedBytes(path, Data(text.utf8), modifiedAt: modifiedAt)
    }

    func seedBytes(_ path: String, _ bytes: Data, modifiedAt: Int64? = nil) {
        let normalized = normalize(path)
        addParents(normalized)
        directories.remove(normalized)
        files[normalized] = bytes
        modified[normalized] = modifiedAt ?? nextClock()
    }

    func mkdir(_ path: String) {
        let normalized = normalize(path)
        addParents(normalized)
        if files[normalized] == nil {
            directories.insert(normalized)
        }
    }

    func text(_ path: String) -> String? {
        files[normalize(path)].map { String(decoding: $0, as: UTF8.self) }
    }

    func canonicalize(cwd: String, input: String) -> String {
        let raw = input.hasPrefix("/") ? input : joinPath(cwd, input)
        return normalize(raw)
    }

    func lacksAccess(_ path: String) -> Bool {
        let normalized = normalize(path)
        return unauthorizedRoots.contains { pathContains(normalize($0), normalized) }
    }

    func exists(_ path: String) -> Bool {
        let normalized = normalize(path)
        return files[normalized] != nil || directories.contains(normalized)
    }

    func isDirectory(_ path: String) -> Bool {
        let normalized = normalize(path)
        return directories.contains(normalized) && files[normalized] == nil
    }

    func isSymlink(_ path: String) -> Bool { false }

    func readBytes(_ path: String) throws -> Data {
        let normalized = normalize(path)
        guard let data = files[normalized] else { throw MissingPath(path: normalized) }
        return data
    }

    func writeBytes(_ path: String, _ bytes: Data) throws {
        let normalized = normalize(path)
        addParents(normalized)
        directories.remove(normalized)
        files[normalized] = bytes
        modified[normalized] = nextClock()
    }

    func list(_ path: String) throws -> [ToolDirEntry] {
        let normalized = normalize(path)
        if files[normalized] == nil && !directories.contains(normalized) {
            throw MissingPath(path: normalized)
        }
        if !directories.contains(normalized) { return [] }
        let prefix = normalized == "/" ? "/" : normalized + "/"
        var names = Set<String>()
        func consider(_ candidate: String) {
            guard candidate != normalized, candidate.hasPrefix(prefix) else { return }
            let rest = candidate.dropFirst(prefix.count)
            let name = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
            if !name.isEmpty { names.insert(name) }
        }
        directories.forEach(consider)
        files.keys.forEach(consider)
        return names.map { name in
            let child = normalized == "/" ? "/" + name : normalized + "/" + name
            return ToolDirEntry(
                name: name,
                isDirectory: directories.contains(child) && files[child] == nil,
                isSymlink: false
            )
        }
    }

    func delete(_ path: String) throws {
        let normalized = normalize(path)
        if files[normalized] == nil && !directories.contains(normalized) {
            throw MissingPath(path: normalized)
        }
        let prefix = normalized + "/"
        for key in files.keys where key == normalized || key.hasPrefix(prefix) {
            files.removeValue(forKey: key)
            modified.removeValue(forKey: key)
        }
        for key in directories where key == normalized || key.hasPrefix(prefix) {
            directories.remove(key)
        }
    }

    func lastModifiedMillis(_ path: String) throws -> Int64 {
        modified[normalize(path)] ?? 0
    }

    private func nextClock() -> Int64 {
        let value = clock
        clock += 1
        return value
    }

    private func addParents(_ path: String) {
        var cursor = parentPath(path)
        var pending: [String] = []
        while !cursor.isEmpty && cursor != "/" && !directories.contains(cursor) && files[cursor] == nil {
            pending.append(cursor)
            cursor = parentPath(cursor)
        }
        directories.insert("/")
        for directory in pending.reversed() {
            directories.insert(directory)
        }
    }

    private func normalize(_ path: String) -> String {
        lexicalNormalize(path)
    }
}
