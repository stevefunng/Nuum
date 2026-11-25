import Foundation
import NuumContracts

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if os(Linux)
@discardableResult
@_silgen_name("getxattr")
func nuum_getxattr(
    _ path: UnsafePointer<CChar>,
    _ name: UnsafePointer<CChar>,
    _ value: UnsafeMutableRawPointer?,
    _ size: Int
) -> Int

@discardableResult
@_silgen_name("setxattr")
func nuum_setxattr(
    _ path: UnsafePointer<CChar>,
    _ name: UnsafePointer<CChar>,
    _ value: UnsafeRawPointer,
    _ size: Int,
    _ flags: Int32
) -> Int32
#endif

public struct StorageIOError: Error, Sendable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// File protection and backup exclusion for the nuum data root.
/// JSON and JSONL use `completeUntilFirstUserAuthentication` on iOS, the same window as the Keychain item.
/// The data root is marked with `URLResourceValues.isExcludedFromBackup`.
public enum DataDirectoryProtection {
    public static let fileProtectionName = "completeUntilFirstUserAuthentication"

    /// Linux extended attribute used when Foundation accepts `isExcludedFromBackup` and does not store it.
    /// Apple platforms persist `URLResourceValues.isExcludedFromBackup` on the directory itself.
    static let linuxExclusionAttribute = "user.com.apple.metadata:com_apple_backup_excludeItem"

    public static func markExcludedFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var copy = url
        try copy.setResourceValues(values)
        if resourceExcluded(url) { return }
        #if os(Linux)
        try writeExclusionAttribute(url)
        #endif
        guard isExcludedFromBackup(url) else {
            throw StorageIOError(message: "could not mark the data root excluded from backup")
        }
    }

    public static func isExcludedFromBackup(_ url: URL) -> Bool {
        if resourceExcluded(url) { return true }
        return exclusionAttributePresent(url)
    }

    public static func applyFileProtection(to url: URL) {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }

    private static func resourceExcluded(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup == true
    }

    private static func exclusionAttributePresent(_ url: URL) -> Bool {
        #if os(Linux)
        url.path.withCString { path in
            linuxExclusionAttribute.withCString { name in
                nuum_getxattr(path, name, nil, 0) >= 0
            }
        }
        #else
        false
        #endif
    }

    #if os(Linux)
    private static func writeExclusionAttribute(_ url: URL) throws {
        var byte: UInt8 = 1
        let result = withUnsafePointer(to: &byte) { pointer in
            url.path.withCString { path in
                linuxExclusionAttribute.withCString { name in
                    nuum_setxattr(path, name, pointer, 1, 0)
                }
            }
        }
        if result != 0 {
            throw StorageIOError(message: "could not mark the data root excluded from backup")
        }
    }
    #endif
}

func invalid(_ message: String) -> NuumError {
    NuumError(code: KernelErrorCode.invalid, message: message)
}

func normalizeRelative(_ path: String) throws -> String {
    let slash = path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
    if slash.isEmpty {
        throw invalid("Path is empty")
    }
    if slash.hasPrefix("/") {
        throw invalid("Path must stay relative to the nuum directory")
    }
    let parts = slash.split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { $0 != "." }
    if parts.isEmpty || parts.contains(where: { $0 == ".." || $0.contains("\u{0000}") }) {
        throw invalid("Path escapes the nuum directory")
    }
    return parts.joined(separator: "/")
}

func canonicalPath(_ path: String) -> String? {
    path.withCString { pointer in
        guard let resolved = realpath(pointer, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

func resolveInside(root: URL, relativePath: String) throws -> (relative: String, url: URL) {
    let relative = try normalizeRelative(relativePath)
    guard let rootPath = canonicalPath(root.path) else {
        throw StorageIOError(message: "data root is unavailable")
    }
    var current = rootPath
    var literal = false
    for part in relative.split(separator: "/") {
        if literal {
            current += "/" + part
            continue
        }
        let next = current + "/" + part
        if let real = canonicalPath(next) {
            guard isInside(root: rootPath, path: real) else {
                throw invalid("Path escapes the nuum directory")
            }
            current = real
        } else {
            guard isInside(root: rootPath, path: next) else {
                throw invalid("Path escapes the nuum directory")
            }
            current = next
            literal = true
        }
    }
    guard isInside(root: rootPath, path: current) else {
        throw invalid("Path escapes the nuum directory")
    }
    return (relative, URL(fileURLWithPath: current))
}

private func isInside(root: String, path: String) -> Bool {
    if path == root { return true }
    let prefix = root.hasSuffix("/") ? root : root + "/"
    return path.hasPrefix(prefix)
}

func fileURL(_ root: URL, _ relative: String) -> URL {
    relative.split(separator: "/").reduce(root) { partial, part in
        partial.appendingPathComponent(String(part))
    }
}

func ensureDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    DataDirectoryProtection.applyFileProtection(to: url)
}

func ensureLayout(_ root: URL) throws {
    try ensureDirectory(root)
    for name in StoragePaths.topLevelDirectories {
        try ensureDirectory(root.appendingPathComponent(name, isDirectory: true))
    }
}

func ensureMigrationMarker(root: URL, beforeCommit: @Sendable () throws -> Void) throws {
    let marker = root.appendingPathComponent(StoragePaths.migrationsPath())
    if FileManager.default.fileExists(atPath: marker.path) { return }
    var isDirectory: ObjCBool = false
    let sessions = root.appendingPathComponent("sessions", isDirectory: true)
    if FileManager.default.fileExists(atPath: sessions.path, isDirectory: &isDirectory), isDirectory.boolValue {
        return
    }
    let body = JSONDocument.renderFields([("version", .int(Int64(StoragePaths.migrationVersion)))]) + "\n"
    try AtomicFiles.write(marker, bytes: Data(body.utf8), beforeCommit: beforeCommit)
}

func readMigrationVersion(root: URL) -> Int {
    let marker = root.appendingPathComponent(StoragePaths.migrationsPath())
    guard let data = try? Data(contentsOf: marker),
          let text = String(data: data, encoding: .utf8),
          let node = JSONDocument.parse(text),
          let version = JSONDocument.int(JSONDocument.field(node, "version"))
    else { return 0 }
    return Int(version)
}

func isRegularFile(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    return exists && !isDirectory.boolValue
}

enum AtomicFiles {
    /// Writes `bytes` to a temp file in the same directory, then renames it over `target`.
    /// `beforeCommit` runs after the temp file is durable and before the rename.
    /// If it throws, `target` is left unchanged and the temp file is removed.
    static func write(_ target: URL, bytes: Data, beforeCommit: @Sendable () throws -> Void) throws {
        let parent = target.deletingLastPathComponent()
        try ensureDirectory(parent)
        let temp = parent.appendingPathComponent("\(target.lastPathComponent).\(UUID().uuidString).tmp")
        var moved = false
        defer {
            if !moved {
                try? FileManager.default.removeItem(at: temp)
            }
        }
        guard FileManager.default.createFile(atPath: temp.path, contents: nil) else {
            throw StorageIOError(message: "could not create a temporary file for \(target.lastPathComponent)")
        }
        let handle = try FileHandle(forWritingTo: temp)
        defer { try? handle.close() }
        try handle.write(contentsOf: bytes)
        try handle.synchronize()
        DataDirectoryProtection.applyFileProtection(to: temp)
        try beforeCommit()
        try replaceFile(temp, with: target)
        moved = true
        DataDirectoryProtection.applyFileProtection(to: target)
    }
}

func replaceFile(_ source: URL, with destination: URL) throws {
    let result = source.path.withCString { sourcePath in
        destination.path.withCString { destinationPath in
            rename(sourcePath, destinationPath)
        }
    }
    if result != 0 {
        throw StorageIOError(message: "atomic replace failed for \(destination.lastPathComponent)")
    }
}

func normalizeJSONLLine(_ line: String) throws -> String {
    var clean = line
    if clean.hasSuffix("\n") { clean.removeLast() }
    if clean.hasSuffix("\r") { clean.removeLast() }
    if clean.isEmpty || clean.contains("\n") || clean.contains("\r") {
        throw invalid("JSONL line must be a single non-empty line")
    }
    return clean
}

enum JsonlFiles {
    private static let newline: UInt8 = 0x0A
    private static let scanChunk = 8192

    static func repairTrailingPartialLine(_ url: URL) throws {
        guard isRegularFile(url) else { return }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        if size == 0 { return }
        try handle.seek(toOffset: size - 1)
        let last = try readFully(handle, count: 1)
        if last.first == newline { return }
        var position = size - 1
        var newlineAt: UInt64?
        while position > 0 {
            let start = position > UInt64(scanChunk) ? position - UInt64(scanChunk) : 0
            let length = Int(position - start)
            try handle.seek(toOffset: start)
            let chunk = try readFully(handle, count: length)
            if let found = chunk.lastIndex(of: newline) {
                let delta = chunk.distance(from: chunk.startIndex, to: found)
                newlineAt = start + UInt64(delta)
                break
            }
            if start == 0 { break }
            position = start
        }
        try handle.truncate(atOffset: newlineAt.map { $0 + 1 } ?? 0)
        try handle.synchronize()
    }

    static func readLines(_ url: URL) throws -> [String] {
        try repairTrailingPartialLine(url)
        guard isRegularFile(url) else { return [] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [] }
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    static func appendLine(_ url: URL, line: String) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw StorageIOError(message: "could not create \(url.lastPathComponent)")
            }
        }
        try repairTrailingPartialLine(url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        _ = try handle.seekToEnd()
        var data = Data(line.utf8)
        data.append(newline)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        DataDirectoryProtection.applyFileProtection(to: url)
    }

    static func readTail(_ url: URL, maxBytes: Int) throws -> String {
        try repairTrailingPartialLine(url)
        guard isRegularFile(url), maxBytes > 0 else { return "" }
        let bytes = try tailBytes(url, maxBytes: maxBytes)
        if bytes.isEmpty { return "" }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// `createdAt` of the last JSON object in the tail window, or 0 when there is none.
    static func lastCreatedAt(_ url: URL) throws -> Int64 {
        try repairTrailingPartialLine(url)
        guard isRegularFile(url) else { return 0 }
        let bytes = try tailBytes(url, maxBytes: StoragePaths.tailWindowBytes)
        if bytes.isEmpty { return 0 }
        let text = String(decoding: bytes, as: UTF8.self)
        var last: Int64 = 0
        var seen = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let created = createdAt(String(line)) else { continue }
            last = created
            seen = true
        }
        return seen ? last : 0
    }

    private static func tailBytes(_ url: URL, maxBytes: Int) throws -> Data {
        guard maxBytes > 0, isRegularFile(url) else { return Data() }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        if size == 0 { return Data() }
        let length = min(size, UInt64(maxBytes))
        let start = size - length
        let startsAtLine: Bool
        if start == 0 {
            startsAtLine = true
        } else {
            try handle.seek(toOffset: start - 1)
            let previous = try readFully(handle, count: 1)
            startsAtLine = previous.first == newline
        }
        try handle.seek(toOffset: start)
        let bytes = try readFully(handle, count: Int(length))
        if startsAtLine { return bytes }
        guard let newlineIndex = bytes.firstIndex(of: newline) else { return Data() }
        let offset = bytes.distance(from: bytes.startIndex, to: newlineIndex)
        if offset == bytes.count - 1 { return Data() }
        return Data(bytes.suffix(from: bytes.index(after: newlineIndex)))
    }

    private static func createdAt(_ line: String) -> Int64? {
        guard let node = JSONDocument.parse(line) else { return nil }
        guard let value = JSONDocument.field(node, "createdAt"), !JSONDocument.isNull(value) else { return nil }
        return JSONDocument.int(value)
    }

    private static func readFully(_ handle: FileHandle, count: Int) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            guard let chunk = try handle.read(upToCount: count - data.count), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data
    }
}
