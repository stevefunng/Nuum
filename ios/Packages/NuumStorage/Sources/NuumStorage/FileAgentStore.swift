import Foundation
import NuumContracts

/// File layout under an application-support `nuum` directory.
/// JSON is replaced atomically. JSONL is append-only, and a truncated last line is dropped.
/// Agent, work, and task lists are an in-memory projection rebuilt from those files.
/// UserDefaults suite `nuum-ui` holds sidebar width and edited identities only.
/// Memory markdown is stored as bytes and is not interpreted.
public actor FileAgentStore: AgentStore {
    public nonisolated let root: URL
    public nonisolated let preferencesSuite: String
    private let beforeCommit: @Sendable () throws -> Void
    private var projection = ListProjection()

    public init(
        root: URL,
        preferencesSuite: String = NuumUIPreferences.suiteName,
        beforeCommit: @escaping @Sendable () throws -> Void = {}
    ) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let realURL = URL(fileURLWithPath: canonicalPath(root.path) ?? root.path, isDirectory: true)
        self.root = realURL
        self.preferencesSuite = preferencesSuite
        self.beforeCommit = beforeCommit
        DataDirectoryProtection.applyFileProtection(to: realURL)
        try DataDirectoryProtection.markExcludedFromBackup(realURL)
    }

    public nonisolated static func migrationsPath() -> String { StoragePaths.migrationsPath() }

    public nonisolated static func workSessionDir(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ) -> String {
        StoragePaths.workSessionDir(
            workId: workId,
            taskId: taskId,
            agentId: agentId,
            membershipRevision: membershipRevision
        )
    }

    public nonisolated static func workSessionRecordPath(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ) -> String {
        StoragePaths.workSessionRecordPath(
            workId: workId,
            taskId: taskId,
            agentId: agentId,
            membershipRevision: membershipRevision
        )
    }

    public nonisolated static func workSessionTranscriptPath(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ) -> String {
        StoragePaths.workSessionTranscriptPath(
            workId: workId,
            taskId: taskId,
            agentId: agentId,
            membershipRevision: membershipRevision
        )
    }

    public nonisolated static func cardSessionId(
        workId: String,
        taskId: String,
        agentId: String,
        membershipRevision: Int
    ) -> String {
        StoragePaths.cardSessionId(
            workId: workId,
            taskId: taskId,
            agentId: agentId,
            membershipRevision: membershipRevision
        )
    }

    public nonisolated static func workspaceIdForOwner(_ owner: String) -> String {
        StoragePaths.workspaceIdForOwner(owner)
    }

    /// Creates the directory layout and rebuilds the list projection when it is missing
    /// or `migrations.json` no longer matches the last build.
    public func open() async throws {
        try ensureLayout(root)
        try ensureMigrationMarker(root: root, beforeCommit: beforeCommit)
        if projection.needsRebuild(root: root) {
            try projection.rebuild(root: root)
        }
        DataDirectoryProtection.applyFileProtection(to: root)
        try DataDirectoryProtection.markExcludedFromBackup(root)
    }

    public func readSettings() async throws -> Settings {
        let url = try resolve(StoragePaths.settingsPath()).url
        guard isRegularFile(url) else { return defaultSettings }
        let data = try Data(contentsOf: url)
        return SettingsJSON.decode(String(decoding: data, as: UTF8.self))
    }

    public func writeSettings(_ settings: Settings) async throws {
        try writeBytes(StoragePaths.settingsPath(), bytes: Data(SettingsJSON.encode(settings).utf8))
    }

    public func agentList() -> [AgentListEntry] { projection.agents() }

    public func workList() -> [WorkListEntry] { projection.works() }

    public func taskList(_ workId: String) -> [TaskListEntry] { projection.tasks(workId: workId) }

    public func sidebarSections() -> [SidebarSectionEntry] { projection.sidebarSections() }

    public func sidebarPins() -> [String] { projection.sidebarPins() }

    /// Drops the in-memory rows. Files stay. `rebuildListProjection` or `open` fills them again.
    public func discardListProjection() {
        projection.discard()
    }

    public func rebuildListProjection() async throws {
        try ensureLayout(root)
        try projection.rebuild(root: root)
    }

    /// Complete JSONL lines. A truncated final line is removed from the file first.
    public func readJsonLines(_ relativePath: String) async throws -> [String] {
        try JsonlFiles.readLines(try resolve(relativePath).url)
    }

    public nonisolated func readSidebarLayout() -> SidebarLayout {
        UIPreferenceStore.readSidebarLayout(suite: preferencesSuite)
    }

    public nonisolated func writeSidebarLayout(_ layout: SidebarLayout) {
        UIPreferenceStore.writeSidebarLayout(suite: preferencesSuite, layout: layout)
    }

    public nonisolated func hasEditedIdentity(_ agentId: String) throws -> Bool {
        try UIPreferenceStore.hasEditedIdentity(suite: preferencesSuite, agentId: agentId)
    }

    public nonisolated func markIdentityEdited(_ agentId: String) throws {
        try UIPreferenceStore.markIdentityEdited(suite: preferencesSuite, agentId: agentId)
    }

    public nonisolated func preferenceKeys() -> Set<String> {
        UIPreferenceStore.storedKeys(suite: preferencesSuite)
    }

    public nonisolated func dataRootExcludedFromBackup() -> Bool {
        DataDirectoryProtection.isExcludedFromBackup(root)
    }

    public func readText(_ relativePath: String) async throws -> String? {
        guard let bytes = try readBytesSync(relativePath) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    public func writeTextAtomic(_ relativePath: String, text: String) async throws {
        try writeBytes(relativePath, bytes: Data(text.utf8))
    }

    public func appendLine(_ relativePath: String, line: String) async throws {
        let normalized = try normalizeRelative(relativePath)
        let clean = try normalizeJSONLLine(line)
        let url = try resolve(normalized).url
        try JsonlFiles.appendLine(url, line: clean)
        try updateProjection(normalized)
    }

    public func readBytes(_ relativePath: String) async throws -> Data? {
        try readBytesSync(relativePath)
    }

    public func writeBytesAtomic(_ relativePath: String, bytes: Data) async throws {
        try writeBytes(relativePath, bytes: bytes)
    }

    public func readTail(_ relativePath: String, maxBytes: Int) async throws -> String {
        try JsonlFiles.readTail(try resolve(relativePath).url, maxBytes: maxBytes)
    }

    public func list(_ relativePath: String) async throws -> [String] {
        let url = try resolve(relativePath).url
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    public func delete(_ relativePath: String) async throws {
        let resolved = try resolve(relativePath)
        guard FileManager.default.fileExists(atPath: resolved.url.path) else { return }
        do {
            try FileManager.default.removeItem(at: resolved.url)
        } catch {
            throw StorageIOError(message: "could not delete \(resolved.relative)")
        }
        try updateProjectionDeleted(resolved.relative)
    }

    public func exists(_ relativePath: String) async throws -> Bool {
        FileManager.default.fileExists(atPath: try resolve(relativePath).url.path)
    }

    private func readBytesSync(_ relativePath: String) throws -> Data? {
        let url = try resolve(relativePath).url
        guard isRegularFile(url) else { return nil }
        return try Data(contentsOf: url)
    }

    private func writeBytes(_ relativePath: String, bytes: Data) throws {
        let normalized = try normalizeRelative(relativePath)
        let payload = try payloadFor(normalized, bytes)
        try AtomicFiles.write(try resolve(normalized).url, bytes: payload, beforeCommit: beforeCommit)
        try updateProjection(normalized)
    }

    private func payloadFor(_ relativePath: String, _ bytes: Data) throws -> Data {
        guard relativePath == StoragePaths.settingsPath() || relativePath.hasSuffix("/settings.json") else {
            return bytes
        }
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw invalid(JSONDocument.settingsMustBeObject)
        }
        if relativePath == StoragePaths.settingsPath() {
            return Data(try SettingsJSON.canonical(text).utf8)
        }
        return Data(try SettingsJSON.stripSecretFields(text).utf8)
    }

    private func updateProjection(_ relativePath: String) throws {
        do {
            try projection.onWritten(root: root, relativePath: relativePath)
        } catch {
            projection.discard()
            throw error
        }
    }

    private func updateProjectionDeleted(_ relativePath: String) throws {
        do {
            try projection.onDeleted(root: root, relativePath: relativePath)
        } catch {
            projection.discard()
            throw error
        }
    }

    private func resolve(_ relativePath: String) throws -> (relative: String, url: URL) {
        try resolveInside(root: root, relativePath: relativePath)
    }
}
