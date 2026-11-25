import Foundation
import NuumContracts
import NuumStorage
import Testing

func withStore(
    beforeCommit: @escaping @Sendable () throws -> Void = {},
    _ body: (FileAgentStore) async throws -> Void
) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nuum-test-\(UUID().uuidString)", isDirectory: true)
    let suite = "nuum-ui-test-\(UUID().uuidString)"
    let store = try FileAgentStore(root: root, preferencesSuite: suite, beforeCommit: beforeCommit)
    defer {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: store.root)
    }
    try await body(store)
}

func fileURL(_ root: URL, _ relative: String) -> URL {
    relative.split(separator: "/").reduce(root) { partial, part in
        partial.appendingPathComponent(String(part))
    }
}

func appendRaw(root: URL, relative: String, text: String) throws {
    let url = fileURL(root, relative)
    if !FileManager.default.fileExists(atPath: url.path) {
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    _ = try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
}

func descendantNames(under root: URL) -> [String] {
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
        return [root.lastPathComponent]
    }
    var names = [root.lastPathComponent]
    while let item = enumerator.nextObject() as? URL {
        names.append(item.lastPathComponent)
    }
    return names
}

func assertNoKeyFields(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
    let data = try #require(text.data(using: .utf8), sourceLocation: sourceLocation)
    let json = try JSONSerialization.jsonObject(with: data)
    func walk(_ value: Any) {
        if let object = value as? [String: Any] {
            for (key, child) in object {
                reject(key, sourceLocation: sourceLocation)
                walk(child)
            }
        } else if let array = value as? [Any] {
            array.forEach(walk)
        }
    }
    walk(json)
}

private func reject(_ key: String, sourceLocation: SourceLocation) {
    let lower = key.lowercased()
    #expect(!lower.contains("key"), "key field \(key)", sourceLocation: sourceLocation)
    #expect(!lower.contains("secret"), "secret field \(key)", sourceLocation: sourceLocation)
    #expect(lower != "authorization", "authorization field \(key)", sourceLocation: sourceLocation)
}

final class CommitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false

    func arm() {
        lock.lock()
        armed = true
        lock.unlock()
    }

    func checkpoint() throws {
        lock.lock()
        defer { lock.unlock() }
        guard armed else { return }
        armed = false
        throw StorageIOError(message: "atomic write failed before replace")
    }
}
