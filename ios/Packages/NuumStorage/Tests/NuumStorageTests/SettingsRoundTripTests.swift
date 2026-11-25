import Foundation
import NuumContracts
import NuumStorage
import Testing

@Test func settingsRoundTripHasNoKeyFields() async throws {
    try await withStore { store in
        #expect(try await store.readSettings() == defaultSettings)
        #expect(!(try await store.exists(NuumPaths.settingsPath())))

        let settings = Settings(
            defaultToolPermission: .always,
            defaultModel: ModelRef(provider: .openai, model: "gpt-4o"),
            theme: .light,
            language: .en,
            sidebar: SidebarOrganization(
                pinnedAgentIds: ["a1"],
                sections: [
                    SidebarSection(id: "g1", name: "Research", agentIds: ["a1", "a2"], isCollapsed: true),
                ]
            )
        )
        try await store.writeSettings(settings)
        let raw = try #require(await store.readText(NuumPaths.settingsPath()))
        try assertNoKeyFields(raw)
        #expect(!raw.contains("openaiApiKey"))
        #expect(!raw.contains("anthropicApiKey"))
        #expect(!raw.contains("deepseekApiKey"))
        #expect(!raw.contains("hasOpenaiKey"))
        #expect(!raw.contains("sk-"))
        #expect(try await store.readSettings() == settings)
        try await store.writeSettings(try await store.readSettings())
        #expect(try await store.readSettings() == settings)
        #expect(await store.sidebarPins() == ["a1"])
        let section = try #require(await store.sidebarSections().first)
        #expect(await store.sidebarSections().count == 1)
        #expect(section.id == "g1")
        #expect(section.name == "Research")
        #expect(section.agentIds == ["a1", "a2"])
        #expect(section.isCollapsed)

        await store.discardListProjection()
        try await store.rebuildListProjection()
        #expect(await store.sidebarPins() == ["a1"])
        #expect(await store.sidebarSections().first?.name == "Research")
    }
}

@Test func aKeyFieldInTheDocumentIsStrippedOnWrite() async throws {
    try await withStore { store in
        try await store.writeTextAtomic(
            NuumPaths.settingsPath(),
            text: #"{"theme":"light","openaiApiKey":"sk-test-secret","hasOpenaiKey":true,"defaultModel":{"provider":"openai","model":"gpt-4o","apiKey":"sk-nested"}}"#
        )
        let raw = try #require(await store.readText(NuumPaths.settingsPath()))
        try assertNoKeyFields(raw)
        #expect(!raw.contains("sk-test-secret"))
        #expect(!raw.contains("sk-nested"))
        #expect(!raw.contains("openaiApiKey"))
        #expect(!raw.contains("hasOpenaiKey"))
        #expect(!raw.contains("apiKey"))
        let read = try await store.readSettings()
        #expect(read.theme == .light)
        #expect(read.defaultModel.provider == .openai)
        #expect(read.defaultModel.model == "gpt-4o")
        #expect(read.defaultToolPermission == .ask)
        #expect(read.language == .zhCN)
        #expect(read.sidebar == nil)
        try await store.writeSettings(read)
        #expect(try await store.readSettings() == read)
        try assertNoKeyFields(try #require(await store.readText(NuumPaths.settingsPath())))
    }
}

@Test func invalidSettingsJsonIsRejectedWithoutEchoingTheBody() async throws {
    try await withStore { store in
        do {
            try await store.writeTextAtomic(NuumPaths.settingsPath(), text: "not-json sk-secret-value")
            Issue.record("expected invalid settings to be rejected")
        } catch let error as NuumError {
            #expect(error.code == KernelErrorCode.invalid)
            #expect(!error.message.contains("sk-secret-value"))
            #expect(!error.message.contains("not-json"))
        }
        #expect(!(try await store.exists(NuumPaths.settingsPath())))
    }
}

@Test func agentSettingsDropNestedKeysAndKeepTheRest() async throws {
    try await withStore { store in
        try await store.writeTextAtomic(
            NuumPaths.profilePath("a1"),
            text: #"{"id":"a1","name":"One","description":"","createdAt":5}"#
        )
        try await store.writeTextAtomic(
            NuumPaths.agentSettingsPath("a1"),
            text: #"{"model":{"provider":"deepseek","model":"deepseek-chat","apiKey":"sk-agent"},"hiddenFromSidebar":true}"#
        )
        let raw = try #require(await store.readText(NuumPaths.agentSettingsPath("a1")))
        #expect(!raw.contains("sk-agent"))
        #expect(!raw.contains("apiKey"))
        #expect(raw.contains("hiddenFromSidebar"))
        #expect(raw.contains("deepseek-chat"))
        #expect(await store.agentList().first?.hiddenFromSidebar == true)
    }
}

@Test func uiPreferencesStayOutOfSettingsAndTheNuumTree() async throws {
    try await withStore { store in
        store.writeSidebarLayout(SidebarLayout(expandedWidth: 320, isCollapsed: true))
        try store.markIdentityEdited("a1")
        try await store.writeSettings(defaultSettings)
        let raw = try #require(await store.readText(NuumPaths.settingsPath()))
        #expect(!raw.contains("expandedWidth"))
        #expect(!raw.contains("nuum-identity-edited"))
        #expect(!raw.contains("isCollapsed"))
        let names = descendantNames(under: store.root)
        #expect(!names.contains { $0.contains("preferences") || $0.contains("nuum-ui") })
        let allowed: Set<String> = [
            UiPreferenceKeys.expandedWidth,
            UiPreferenceKeys.isCollapsed,
            UiPreferenceKeys.identityEdited,
        ]
        #expect(store.preferenceKeys().isSubset(of: allowed))
    }
}
