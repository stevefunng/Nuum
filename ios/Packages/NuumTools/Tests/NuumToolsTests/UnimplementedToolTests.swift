import Foundation
import NuumContracts
import Testing
@testable import NuumTools

@Test func shellNetworkAndExternalReturnTheFixedSentence() async throws {
    let item = fixture(permission: .always)
    for name in ["shell", "request_network", "external_operation"] {
        let result = try await item.run(name, [
            "command": .string("echo hi"),
            "target": .string("example.com:443"),
        ])
        #expect(result.ok == false)
        #expect(result.output == UnimplementedToolMessage.iosClient)
    }
    #expect(item.files.text("\(item.scratch)/echo") == nil)
    #expect(UnimplementedToolMessage.iosClient == "This iOS client does not implement this tool.")
}

@Test func mainSourcesDoNotLaunchProcessesOrImportForbiddenModules() throws {
    let root = try packageSources()
    let banned = [
        "Process(",
        "NSTask",
        "posix_spawn",
        "popen(",
        "system(",
        "execve",
        "execl(",
        "fork(",
        "dlopen",
        "/usr/bin/rg",
        "import Security",
        "import UIKit",
        "import SwiftUI",
        "URLSession",
        "secrets.bin",
        "noBackupFilesDir",
        "safeStorage",
    ]
    var hits: [String] = []
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
        Issue.record("could not read \(root.path)")
        return
    }
    for case let file as URL in enumerator where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        for token in banned where text.contains(token) {
            hits.append("\(file.lastPathComponent) contains \(token)")
        }
    }
    #expect(hits.isEmpty, "\(hits.joined(separator: "\n"))")
}

private func packageSources() throws -> URL {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let manager = FileManager.default
    while !manager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
        let parent = url.deletingLastPathComponent()
        if parent.path == url.path {
            throw CocoaError(.fileNoSuchFile)
        }
        url = parent
    }
    let sources = url.appendingPathComponent("Sources/NuumTools")
    guard manager.fileExists(atPath: sources.path) else {
        throw CocoaError(.fileNoSuchFile)
    }
    return sources
}
