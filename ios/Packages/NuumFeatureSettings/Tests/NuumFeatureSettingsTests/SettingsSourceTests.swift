import Foundation
import Testing

@Test func settingsSourcesStayOnTheContractBoundary() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceRoot = packageRoot.appendingPathComponent("Sources/NuumFeatureSettings")
    let files = try FileManager.default.contentsOfDirectory(at: sourceRoot, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
    #expect(!files.isEmpty)
    let text = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    let forbidden = [
        "import NuumProtocol",
        "import NuumAgent",
        "import NuumStorage",
        "import NuumSecurity",
        "import NuumKernel",
        "import NuumModel",
        "import NuumTools",
        "import UIKit",
        "import Security",
        "SecretStore",
        "secrets.bin",
        "hasDeepseekKey",
        "hasOpenaiKey",
        "hasAnthropicKey",
        "URLSession",
        "FileManager",
        "UserDefaults",
        "defaultToolPermission",
        "actionsAvailable = false",
        "actionsAvailable: false",
        "\"Quit\"",
        "Datadog",
        "Sentry",
        "Firebase",
        "NSAllowsArbitraryLoads",
        "sk-",
    ]
    for needle in forbidden {
        #expect(!text.contains(needle), "sources contain \(needle)")
    }
    #expect(text.contains("actionsAvailable"))
    #expect(text.contains("SecretWriter"))
    #expect(text.contains("defaultModelID"))
    #expect(text.contains("SecureField"))
    #expect(!files.contains(where: { $0.lastPathComponent == "Placeholder.swift" }))

    let manifest = try String(contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
    let code = manifest.split(separator: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
    #expect(!code.contains("platforms:"))
    #expect(!code.contains("url:"))
    #expect(code.contains(".testTarget"))
    #expect(code.contains("NuumFeatureSettingsTests"))
}
