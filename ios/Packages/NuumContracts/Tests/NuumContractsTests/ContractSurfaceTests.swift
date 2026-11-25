import Foundation
import NuumContracts
import Testing

@Test func dependencyDirectionHolds() throws {
    let violations = try DependencyDirection.violations(at: iosRoot())
    #expect(violations.isEmpty)
    if !violations.isEmpty {
        Issue.record(Comment(rawValue: violations.joined(separator: "\n")))
    }
}

@Test func errorCarriesCodeAndMessage() {
    let error = NuumError(code: HostErrorCode.noAPIKey, message: "Add an API key in Settings")
    #expect(error.code == 2004)
    #expect(error.code == HostErrorCode.noAPIKey)
    #expect(error.message == "Add an API key in Settings")
    #expect(DesktopErrorCode.secretStore == 3001)
    #expect(KernelErrorCode.model == 1004)
    #expect(KernelErrorCode.internal == 1000)
    #expect(DesktopErrorCode.window == 3003)
    #expect(NuumError.secretReadFailed == NuumError(code: 3001, message: "Couldn't read secrets because decryption failed."))
    #expect(NuumError.secretWriteFailed.message == "Couldn't store secrets because encryption failed.")
    #expect(!error.message.contains("sk-"))
}

@Test func hostEventNamesMatchTheMacContract() {
    #expect(
        HostEvents.all == [
            "agent.updated",
            "agent.message.delta",
            "agent.message.completed",
            "agent.tool.pending",
            "agent.tool.started",
            "agent.tool.completed",
            "agent.error",
            "agent.ended",
            "work.updated",
            "work.event.appended",
            "work.catalog.updated",
            "proactive.updated",
            "settings.updated",
        ]
    )
    #expect(!HostEvents.all.contains("host.kernel.down"))
    let event = HostEvent.agentError(
        AgentErrorEvent(agentId: "a", runId: "r", code: HostErrorCode.noAPIKey, message: "missing")
    )
    #expect(event.name == HostEvents.agentError)
    #expect(KernelEvents.all.contains("turn.context"))
    #expect(KernelEvents.all.count == 8)
}

@Test func pathsStayRelativeToTheNuumRoot() {
    #expect(NuumPaths.profilePath("nunu") == "agents/nunu/profile.json")
    #expect(NuumPaths.transcriptPath("nunu") == "agents/nunu/transcript.jsonl")
    #expect(NuumPaths.memoryDir("nunu") == "agents/nunu/memory")
    #expect(NuumPaths.workTimelinePath("room") == "works/room/timeline.jsonl")
    #expect(NuumPaths.migrationsPath() == "migrations.json")
    #expect(NuumPaths.secretsFileName() == "secrets.bin")
    #expect(NuumPaths.secretsFileName() == SealedSecretFilename.secretsBin)
    #expect(!NuumPaths.profilePath("nunu").hasPrefix("/"))
    #expect(!NuumPaths.profilePath("nunu").contains("secrets.bin"))
    #expect(KeychainSecretItem.service == "nuum.secrets")
    #expect(KeychainSecretItem.account == "api-keys")
    #expect(NuumDataDirectory.name == "nuum")
    #expect(NuumUIPreferences.suiteName == "nuum-ui")
    #expect(SealedSecretFilename.all.count == 4)
}

@Test func defaultModelIDsMatchTheMacTable() {
    #expect(defaultModelID(for: .deepseek) == "deepseek-chat")
    #expect(defaultModelID(for: .openai) == "gpt-4o")
    #expect(defaultModelID(for: .anthropic) == "claude-sonnet-4-20250514")
    #expect(defaultModelIDs[.deepseek] == DeepSeekModelID.chat)
    #expect(DeepSeekModelID.reasoner == "deepseek-reasoner")
    #expect(providerFallback == [.deepseek, .openai, .anthropic])
    #expect(AttachmentLimits.maxCount == 5)
    #expect(AttachmentLimits.maxBytes == 10 * 1024 * 1024)
    #expect(AttachmentLimits.maxTotalBytes == 20 * 1024 * 1024)
    #expect(defaultSettings.defaultToolPermission == .ask)
    #expect(defaultSettings.defaultModel == ModelRef(provider: .deepseek, model: "deepseek-chat"))
    #expect(ProactiveSnapshot(defaultAgentId: nil, agents: [], availableSourceIds: []).actionsAvailable == false)
    #expect(UnimplementedToolMessage.iosClient == "This iOS client does not implement this tool.")
    #expect(UnimplementedToolMessage.runWorkCLI == "This version of Nuum has no local executable. RunWorkCLI is not implemented.")
    #expect(IOSEnvironmentPrompt.sentence.contains("local iOS app"))
    #expect(!IOSEnvironmentPrompt.sentence.contains("real shell"))
}

@Test func secretDescriptionsDoNotPrintKeys() {
    let secret = "sk-test-secret"
    let secrets = Secrets(openaiApiKey: secret)
    #expect(!String(describing: secrets).contains(secret))
    #expect(!String(reflecting: secrets).contains(secret))
    let request = NormalizedChatRequest(
        model: ModelRef(provider: .openai, model: "gpt-4o"),
        messages: [],
        tools: [],
        apiKey: secret
    )
    #expect(!String(describing: request).contains(secret))
    #expect(!String(reflecting: request).contains(secret))
}

private func iosRoot() throws -> URL {
    var url = URL(filePath: #filePath)
    let manager = FileManager.default
    for _ in 0..<10 {
        url.deleteLastPathComponent()
        if manager.fileExists(atPath: url.appendingPathComponent("Nuum.xcodeproj").path) {
            return url
        }
    }
    throw CocoaError(.fileNoSuchFile)
}
