import Foundation
import Testing

@testable import NuumAcceptance

@Test func acceptanceSourcesStayInsideThisPackage() throws {
    let root = try RepositoryLayout.root()
    let sources = root.appendingPathComponent("ios/Packages/NuumAcceptance/Sources")
    let files = try RepositoryLayout.swiftFiles(under: sources)
    #expect(!files.isEmpty)
    let forbidden = [
        "secrets.bin",
        "noBackupFilesDir",
        "safeStorage",
        "import Nuum",
        "import SwiftUI",
        "import UIKit",
        "import Security",
        "URLSession",
        "Datadog",
        "Sentry",
        "Firebase",
        "WidgetKit",
    ]
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        for token in forbidden {
            #expect(!text.contains(token), "\(file.lastPathComponent) contains \(token)")
        }
    }
    let manifest = try RepositoryLayout.text(root, "ios/Packages/NuumAcceptance/Package.swift")
    #expect(!manifest.contains(".package(path:"))
    #expect(!manifest.contains("https://"))
    #expect(!manifest.contains("github.com"))
    #expect(manifest.contains(".testTarget("))
}

@Test func debugRouterPhrasesMatchTheFixtures() throws {
    let root = try RepositoryLayout.root()
    let router = try RepositoryLayout.text(root, "ios/App/Graph/DebugModelPort.swift")
    #expect(router.contains("#if DEBUG"))
    #expect(router.contains("class AcceptanceRouterModel"))
    #expect(router.contains("private let fakeModelArgument = \"\(AcceptanceFixture.fakeModelArgument)\""))
    #expect(router.contains("ProcessInfo.processInfo.environment[\"\(AcceptanceFixture.fakeModelEnvironment)\"] == \"\(AcceptanceFixture.fakeModelEnvironmentValue)\""))
    #expect(router.contains("user.contains(\"\(AcceptanceFixture.sealedCue)\")"))
    #expect(router.contains("user.contains(\"\(AcceptanceFixture.writeCue)\")"))
    #expect(router.contains("\"\(AcceptanceFixture.outsideScratchRelative)\""))
    #expect(router.contains("SealedSecretFilename.secretsJSON"))
    #expect(router.contains("\"\(AcceptanceFixture.noteText)\""))
    #expect(router.contains("\"\(AcceptanceFixture.laneCard)\""))
    #expect(router.contains(".text(\"\(AcceptanceFixture.scratchpad)\")"))
    #expect(router.contains("send(\"\(AcceptanceFixture.visibleReply)\")"))
    #expect(router.contains("return URLSessionModelPort()"))
}

@Test func workSourcesHaveNoManualCreateTaskLabel() throws {
    let root = try RepositoryLayout.root()
    let sources = root.appendingPathComponent("ios/Packages/NuumFeatureWork/Sources")
    let files = try RepositoryLayout.swiftFiles(under: sources)
    #expect(!files.isEmpty)
    var hits: [String] = []
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if let label = AcceptanceFixture.manualTaskLabels.first(where: { line.contains($0) }) {
                hits.append("\(file.lastPathComponent):\(index + 1) \(label)")
            }
        }
    }
    #expect(hits.isEmpty, "\(hits.joined(separator: ", "))")
}

@Test func attachmentCeilingAndDocumentPickerAreTheIOSPath() throws {
    let root = try RepositoryLayout.root()
    let attachments = try RepositoryLayout.text(root, "ios/Packages/NuumProtocol/Sources/NuumProtocol/Attachments.swift")
    #expect(attachments.contains("public let maxAttachments = 5"))
    #expect(attachments.contains("public let maxAttachmentBytes = 10 * 1024 * 1024"))
    #expect(attachments.contains("public let maxAttachmentTotalBytes = 20 * 1024 * 1024"))
    #expect(attachments.contains("At most 5 attachments per message."))
    let desktop = try RepositoryLayout.text(root, "ios/App/Graph/IOSDesktopPort.swift")
    #expect(desktop.contains("fileImporter("))
    #expect(desktop.contains("allowsMultipleSelection: true"))
    #expect(desktop.contains("allowedContentTypes: [.folder]"))
    #expect(!desktop.contains("ACTION_OPEN_DOCUMENT"))
}

@Test func backupDeclarationsExcludeKeyMaterialWithoutABackupTool() throws {
    let root = try RepositoryLayout.root()
    let info = try RepositoryLayout.text(root, "ios/App/Info.plist")
    for key in [
        "UIBackgroundModes",
        "UIFileSharingEnabled",
        "LSSupportsOpeningDocumentsInPlace",
        "NSAllowsArbitraryLoads",
        "NSAppTransportSecurity",
        "NSUserTrackingUsageDescription",
    ] {
        #expect(!info.contains(key), "Info.plist contains \(key)")
    }
    let entitlements = try RepositoryLayout.text(root, "ios/App/Nuum.entitlements")
    #expect(!entitlements.contains("<key>"))
    let privacy = try RepositoryLayout.text(root, "ios/App/PrivacyInfo.xcprivacy")
    #expect(privacy.contains("<key>NSPrivacyTracking</key>"))
    #expect(privacy.contains("<false/>"))
    let storage = try RepositoryLayout.text(root, "ios/Packages/NuumStorage/Sources/NuumStorage/StorageIO.swift")
    #expect(storage.contains("values.isExcludedFromBackup = true"))
    let keychain = try RepositoryLayout.text(root, "ios/Packages/NuumSecurity/Sources/NuumSecurity/KeychainSecretStore.swift")
    #expect(keychain.contains("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"))
    #expect(keychain.contains("kSecAttrSynchronizable as String: false"))
    let project = try RepositoryLayout.text(root, "ios/Nuum.xcodeproj/project.pbxproj")
    #expect(!project.contains("productName = NuumAcceptance"))
}

@Test func releaseConfigurationDoesNotCompileTheDebugRouter() throws {
    let root = try RepositoryLayout.root()
    let project = try RepositoryLayout.text(root, "ios/Nuum.xcodeproj/project.pbxproj")
    let blocks = RepositoryLayout.configurationBlocks(project)
    let release = blocks.filter { $0.name == "Release" }
    let debug = blocks.filter { $0.name == "Debug" }
    #expect(release.count == 2)
    #expect(debug.count == 2)
    for block in release {
        #expect(!block.body.contains("DEBUG=1"))
        #expect(!block.body.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS"))
    }
    #expect(debug.contains { $0.body.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\"") })
    let packages = root.appendingPathComponent("ios/Packages")
    let entries = try FileManager.default.contentsOfDirectory(at: packages, includingPropertiesForKeys: nil)
    var packageFiles: [URL] = []
    for directory in entries {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            continue
        }
        let manifest = directory.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: manifest.path) {
            packageFiles.append(manifest)
        }
    }
    #expect(packageFiles.count >= 12)
    for manifest in packageFiles {
        let text = try String(contentsOf: manifest, encoding: .utf8)
        #expect(text.range(of: #"\.package\(\s*url\s*:"#, options: .regularExpression) == nil)
        #expect(!text.contains("github.com"))
    }
}

@Test func securityTestsAreOnDiskAndNotAPackageTarget() throws {
    let root = try RepositoryLayout.root()
    let manifest = try RepositoryLayout.text(root, "ios/Packages/NuumSecurity/Package.swift")
    #expect(!manifest.contains("testTarget"))
    let tests = root.appendingPathComponent("ios/Packages/NuumSecurity/Tests/NuumSecurityTests")
    #expect(FileManager.default.fileExists(atPath: tests.appendingPathComponent("KeychainSecretStoreTests.swift").path))
    #expect(FileManager.default.fileExists(atPath: tests.appendingPathComponent("SecretsCodecTests.swift").path))
}

@Test func contractTypesStillLackTheKnownFields() throws {
    let root = try RepositoryLayout.root()
    let events = try RepositoryLayout.text(root, "ios/Packages/NuumContracts/Sources/NuumContracts/HostEvent.swift")
    let transcript = try RepositoryLayout.text(root, "ios/Packages/NuumContracts/Sources/NuumContracts/Transcript.swift")
    let domain = try RepositoryLayout.text(root, "ios/Packages/NuumContracts/Sources/NuumContracts/Domain.swift")
    let pending = RepositoryLayout.storedProperties(events, type: "AgentToolPendingEvent")
    #expect(!pending.isEmpty)
    #expect(pending.allSatisfy { !$0.contains("workId") })
    let compact = RepositoryLayout.storedProperties(transcript, type: "CompactTranscript")
    #expect(compact.allSatisfy { !$0.contains("activeRequest") && !$0.contains("roomInputs") })
    let tool = RepositoryLayout.storedProperties(transcript, type: "ToolTranscript")
    #expect(tool.allSatisfy { !$0.contains("executionId") })
    let execution = RepositoryLayout.storedProperties(domain, type: "ExecutionPreferences")
    #expect(execution.allSatisfy { !$0.contains("externalGrants") })

    let protocolTranscript = try RepositoryLayout.text(root, "ios/Packages/NuumProtocol/Sources/NuumProtocol/Transcript.swift")
    #expect(protocolTranscript.contains("activeRequest: String?"))
    #expect(protocolTranscript.contains("roomInputs: [CompactRoomInput]?"))
    #expect(protocolTranscript.contains("executionId: String?"))
    let protocolDomain = try RepositoryLayout.text(root, "ios/Packages/NuumProtocol/Sources/NuumProtocol/Domain.swift")
    #expect(protocolDomain.contains("externalGrants: [ExternalGrant]?"))

    let bridge = try RepositoryLayout.text(root, "ios/Packages/NuumAgent/Sources/NuumAgent/Bridge.swift")
    #expect(bridge.contains("case .compact(let id, let seq, let createdAt, let epoch, let throughSeq, let tailFromSeq, let summary, _, _):"))
    #expect(bridge.contains("case .tool(let id, let seq, let createdAt, let assistantId, let toolCallId, _, _, let name, let content, let ok, let spillPath):"))
}

@Test func shellSelectionHasNoListReturnCallback() throws {
    let root = try RepositoryLayout.root()
    let ports = try RepositoryLayout.text(root, "ios/Packages/NuumFeatureShell/Sources/NuumFeatureShell/ShellPorts.swift")
    let selection = RepositoryLayout.storedProperties(ports, type: "ShellSelection")
    let names = selection.joined(separator: "\n")
    #expect(names.contains("dismissOverlay"))
    #expect(names.contains("openProfile"))
    #expect(!names.contains("selectWork"))
    #expect(!names.contains("onBack"))
    #expect(!names.contains("returnToList"))
    let shell = try RepositoryLayout.text(root, "ios/Packages/NuumFeatureShell/Sources/NuumFeatureShell/Views/NuumShell.swift")
    #expect(shell.contains("onBack: { session.back() }"))
    let rootView = try RepositoryLayout.text(root, "ios/App/RootView.swift")
    #expect(rootView.contains("ShellSelection does not expose ShellSession.back"))
    #expect(rootView.contains("onCreated: hopProfile { _ in selection.dismissOverlay() }"))
    #expect(rootView.contains("onBack: hop(selection.dismissOverlay)"))
}

@Test func sendMessageProjectionStillMatchesTheAndroidDefectShape() throws {
    let root = try RepositoryLayout.root()
    let turns = try RepositoryLayout.text(root, "ios/Packages/NuumAgent/Sources/NuumAgent/HostTurns.swift")
    #expect(turns.contains("Missing API key for \\(model.provider.rawValue)"))
    #expect(turns.contains("executionId: nil"))
    #expect(turns.contains("activeRequest: nil"))
    #expect(turns.contains("roomInputs: nil"))
    let finish = functionBody(turns, "private func finishRun")
    #expect(finish.contains("liveParts.removeValue(forKey: agentId)"))
    #expect(!finish.contains("appendTranscriptEvent"))
    let projection = try RepositoryLayout.text(root, "ios/Packages/NuumFeatureConversation/Sources/NuumFeatureConversation/Projection.swift")
    #expect(projection.contains("if call.name == \"SendMessage\" { return nil }"))
    let toolCase = functionSlice(projection, "case .tool(let tool):", until: "if let live")
    #expect(!toolCase.contains("SendMessage"))
    #expect(toolCase.contains("name: tool.name"))
}

private func functionBody(_ source: String, _ signature: String) -> String {
    guard let start = source.range(of: signature) else { return "" }
    let rest = source[start.upperBound...]
    guard let next = rest.range(of: "\n    private func ") ?? rest.range(of: "\n    func ") else {
        return String(rest)
    }
    return String(rest[..<next.lowerBound])
}

private func functionSlice(_ source: String, _ startMarker: String, until endMarker: String) -> String {
    guard let start = source.range(of: startMarker) else { return "" }
    let rest = source[start.upperBound...]
    guard let end = rest.range(of: endMarker) else { return String(rest) }
    return String(rest[..<end.lowerBound])
}
