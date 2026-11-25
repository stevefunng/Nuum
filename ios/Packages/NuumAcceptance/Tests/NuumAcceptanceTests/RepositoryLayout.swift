import Foundation

enum RepositoryLayout {
    static func root(file: String = #filePath) throws -> URL {
        var url = URL(fileURLWithPath: file).deletingLastPathComponent()
        let manager = FileManager.default
        while url.path != "/" {
            let marker = url.appendingPathComponent("ios/Packages/NuumAcceptance/Package.swift")
            if manager.fileExists(atPath: marker.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw LayoutError.missingRoot
    }

    static func text(_ root: URL, _ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    static func swiftFiles(under url: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let item as URL in enumerator {
            if item.lastPathComponent == ".build" || item.lastPathComponent == "DerivedData" {
                enumerator.skipDescendants()
                continue
            }
            if item.pathExtension == "swift" {
                files.append(item)
            }
        }
        return files
    }

    /// Property lines of a `public struct` up to its first `public init`.
    static func storedProperties(_ source: String, type name: String) -> [String] {
        guard let start = source.range(of: "public struct \(name)") else { return [] }
        let after = source[start.upperBound...]
        guard let initRange = after.range(of: "public init(") else { return [] }
        return after[..<initRange.lowerBound]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
            .filter { $0.contains("public var") || $0.contains("public let") }
    }

    static func configurationBlocks(_ project: String) -> [(name: String, body: String)] {
        project.components(separatedBy: "isa = XCBuildConfiguration;").dropFirst().compactMap { chunk in
            guard let nameRange = chunk.range(of: "name = ") else { return nil }
            let tail = chunk[nameRange.upperBound...]
            guard let semicolon = tail.firstIndex(of: ";") else { return nil }
            let name = tail[..<semicolon].trimmingCharacters(in: .whitespacesAndNewlines)
            return (name, String(chunk[..<semicolon]))
        }
    }

    enum LayoutError: Error, CustomStringConvertible {
        case missingRoot

        var description: String {
            "NuumAcceptance tests could not find the repository root"
        }
    }
}
