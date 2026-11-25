import NuumStorage
import Testing

@Test func dataRootIsExcludedFromBackup() async throws {
    try await withStore { store in
        #expect(store.dataRootExcludedFromBackup())
        #expect(DataDirectoryProtection.isExcludedFromBackup(store.root))
        try await store.open()
        #expect(store.dataRootExcludedFromBackup())
    }
}
