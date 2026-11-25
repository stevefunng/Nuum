import Foundation

/// One Keychain generic-password item. This device only, not synchronized, not a file.
public enum KeychainSecretItem {
    public static let service = "nuum.secrets"
    public static let account = "api-keys"
}

/// Filenames tools must not read. They are not storage locations on iOS.
public enum SealedSecretFilename {
    public static let secretsBin = "secrets.bin"
    public static let hostSecrets = "host-secrets.json"
    public static let credentials = "credentials.json"
    public static let secretsJSON = "secrets.json"
    public static let all: Set<String> = [secretsBin, hostSecrets, credentials, secretsJSON]
}

/// Application Support subdirectory for the file tree. Documents stays unused.
public enum NuumDataDirectory {
    public static let name = "nuum"
}

/// UserDefaults suite for non-secret UI preferences.
public enum NuumUIPreferences {
    public static let suiteName = "nuum-ui"
}

/// Paths relative to Application Support/`nuum`, matching `NuumPaths`.
/// `secretsFileName()` is the denied filename. iOS does not write that file.
public enum NuumPaths {
    public static func settingsPath() -> String { "settings.json" }
    public static func migrationsPath() -> String { "migrations.json" }

    public static func agentDir(_ agentId: String) -> String { "agents/\(agentId)" }
    public static func profilePath(_ agentId: String) -> String { "agents/\(agentId)/profile.json" }
    public static func agentSettingsPath(_ agentId: String) -> String { "agents/\(agentId)/settings.json" }
    public static func transcriptPath(_ agentId: String) -> String { "agents/\(agentId)/transcript.jsonl" }
    public static func readCursorPath(_ agentId: String) -> String { "agents/\(agentId)/read-cursor.json" }
    public static func toolApprovalsPath(_ agentId: String) -> String { "agents/\(agentId)/tool-approvals.json" }
    public static func promptCachePath(_ agentId: String) -> String { "agents/\(agentId)/prompt-cache.json" }
    public static func memoryDir(_ agentId: String) -> String { "agents/\(agentId)/memory" }
    public static func scratchDir(_ agentId: String) -> String { "agents/\(agentId)/scratch" }
    public static func terminalsDir(_ agentId: String) -> String { "agents/\(agentId)/terminals" }

    public static func workDir(_ workId: String) -> String { "works/\(workId)" }
    public static func workProfilePath(_ workId: String) -> String { "works/\(workId)/profile.json" }
    public static func workCatalogPath(_ workId: String) -> String { "works/\(workId)/catalog.json" }
    public static func workTimelinePath(_ workId: String) -> String { "works/\(workId)/timeline.jsonl" }

    public static func workspaceRecordPath(_ workspaceId: String) -> String { "workspaces/\(workspaceId).json" }
    public static func managedWorkspaceDir(_ workspaceId: String) -> String { "workspaces/\(workspaceId)" }

    public static func secretsFileName() -> String { SealedSecretFilename.secretsBin }
}

/// Byte and text port for the nuum data directory. Not a database.
/// Implementations create missing parents. `appendLine` writes one newline-terminated line.
/// `readText` and `readBytes` return nil when the path is absent.
public protocol AgentStore: Sendable {
    func readText(_ relativePath: String) async throws -> String?
    func writeTextAtomic(_ relativePath: String, text: String) async throws
    func appendLine(_ relativePath: String, line: String) async throws
    func readBytes(_ relativePath: String) async throws -> Data?
    func writeBytesAtomic(_ relativePath: String, bytes: Data) async throws
    func readTail(_ relativePath: String, maxBytes: Int) async throws -> String
    func list(_ relativePath: String) async throws -> [String]
    func delete(_ relativePath: String) async throws
    func exists(_ relativePath: String) async throws -> Bool
}

extension AgentStore {
    public func settingsPath() -> String { NuumPaths.settingsPath() }
    public func agentDir(_ agentId: String) -> String { NuumPaths.agentDir(agentId) }
    public func profilePath(_ agentId: String) -> String { NuumPaths.profilePath(agentId) }
    public func agentSettingsPath(_ agentId: String) -> String { NuumPaths.agentSettingsPath(agentId) }
    public func transcriptPath(_ agentId: String) -> String { NuumPaths.transcriptPath(agentId) }
    public func readCursorPath(_ agentId: String) -> String { NuumPaths.readCursorPath(agentId) }
    public func toolApprovalsPath(_ agentId: String) -> String { NuumPaths.toolApprovalsPath(agentId) }
    public func promptCachePath(_ agentId: String) -> String { NuumPaths.promptCachePath(agentId) }
    public func memoryDir(_ agentId: String) -> String { NuumPaths.memoryDir(agentId) }
    public func scratchDir(_ agentId: String) -> String { NuumPaths.scratchDir(agentId) }
    public func workDir(_ workId: String) -> String { NuumPaths.workDir(workId) }
    public func workTimelinePath(_ workId: String) -> String { NuumPaths.workTimelinePath(workId) }
}
