import Foundation
import NuumContracts
import NuumStorage
import Testing

@Test func sidebarWidthAndIdentityEditedRoundTrip() async throws {
    try await withStore { store in
        #expect(
            store.readSidebarLayout()
                == SidebarLayout(expandedWidth: SidebarLayoutLimits.defaultExpandedWidth, isCollapsed: false)
        )
        #expect(!(try store.hasEditedIdentity("a1")))

        store.writeSidebarLayout(SidebarLayout(expandedWidth: 300, isCollapsed: true))
        #expect(store.readSidebarLayout() == SidebarLayout(expandedWidth: 300, isCollapsed: true))

        store.writeSidebarLayout(SidebarLayout(expandedWidth: 10, isCollapsed: false))
        #expect(store.readSidebarLayout().expandedWidth == SidebarLayoutLimits.minExpandedWidth)
        #expect(!store.readSidebarLayout().isCollapsed)

        store.writeSidebarLayout(SidebarLayout(expandedWidth: 900, isCollapsed: false))
        #expect(store.readSidebarLayout().expandedWidth == SidebarLayoutLimits.maxExpandedWidth)

        try store.markIdentityEdited("a1")
        try store.markIdentityEdited("a1")
        #expect(try store.hasEditedIdentity("a1"))
        #expect(!(try store.hasEditedIdentity("a2")))
    }
}

@Test func anEmptyIdentityIdIsRejected() async throws {
    try await withStore { store in
        do {
            try store.markIdentityEdited("")
            Issue.record("expected an empty agent id to be rejected")
        } catch let error as NuumError {
            #expect(error.code == KernelErrorCode.invalid)
        }
    }
}

@Test func preferencesSuiteDefaultsToNuumUI() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nuum-suite-\(UUID().uuidString)", isDirectory: true)
    let store = try FileAgentStore(root: root)
    defer { try? FileManager.default.removeItem(at: store.root) }
    #expect(store.preferencesSuite == "nuum-ui")
    #expect(store.preferencesSuite == NuumUIPreferences.suiteName)
    #expect(DataDirectoryProtection.fileProtectionName == "completeUntilFirstUserAuthentication")
    #expect(store.dataRootExcludedFromBackup())
}
