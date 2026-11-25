import Foundation
import NuumContracts
import NuumStorage
import Testing

@Test func sharedPathsMatchTheMacRelativeLayout() {
    #expect(StoragePaths.settingsPath() == "settings.json")
    #expect(StoragePaths.migrationsPath() == "migrations.json")
    #expect(StoragePaths.profilePath("nunu") == "agents/nunu/profile.json")
    #expect(StoragePaths.agentSettingsPath("nunu") == "agents/nunu/settings.json")
    #expect(StoragePaths.transcriptPath("nunu") == "agents/nunu/transcript.jsonl")
    #expect(StoragePaths.readCursorPath("nunu") == "agents/nunu/read-cursor.json")
    #expect(StoragePaths.toolApprovalsPath("nunu") == "agents/nunu/tool-approvals.json")
    #expect(StoragePaths.promptCachePath("nunu") == "agents/nunu/prompt-cache.json")
    #expect(StoragePaths.memoryDir("nunu") == "agents/nunu/memory")
    #expect(StoragePaths.scratchDir("nunu") == "agents/nunu/scratch")
    #expect(StoragePaths.terminalsDir("nunu") == "agents/nunu/terminals")
    #expect(StoragePaths.workProfilePath("room") == "works/room/profile.json")
    #expect(StoragePaths.workCatalogPath("room") == "works/room/catalog.json")
    #expect(StoragePaths.workTimelinePath("room") == "works/room/timeline.jsonl")
    #expect(StoragePaths.workspaceRecordPath("abc") == "workspaces/abc.json")
    #expect(StoragePaths.managedWorkspaceDir("abc") == "workspaces/abc")
    #expect(StoragePaths.secretsFileName() == "secrets.bin")
    #expect(StoragePaths.secretsFileName() == NuumPaths.secretsFileName())
    #expect(StoragePaths.profilePath("nunu") == NuumPaths.profilePath("nunu"))
    #expect(StoragePaths.transcriptPath("nunu") == NuumPaths.transcriptPath("nunu"))
    #expect(StoragePaths.memoryDir("nunu") == NuumPaths.memoryDir("nunu"))
    #expect(StoragePaths.workTimelinePath("room") == NuumPaths.workTimelinePath("room"))
    #expect(!StoragePaths.profilePath("nunu").hasPrefix("/"))
    #expect(!StoragePaths.workTimelinePath("room").contains("\\"))
    #expect(StoragePaths.migrationVersion == 3)
    #expect(StoragePaths.tailWindowBytes == 64 * 1024)
    #expect(StoragePaths.uiPreferencesName == NuumUIPreferences.suiteName)
    #expect(StoragePaths.topLevelDirectories == ["agents", "works", "work-sessions", "workspaces"])
}

@Test func workSessionPathsUseTheMacSha256Rules() {
    #expect(StoragePaths.sha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(StoragePaths.sha256Hex("hello") == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    #expect(
        StoragePaths.cardSessionPayload(workId: "room-1", taskId: "task-1", agentId: "agent-1", membershipRevision: 2)
            == "[\"room-1\",\"task-1\",\"agent-1\",2]"
    )
    #expect(
        StoragePaths.cardSessionPayload(workId: "a\"b", taskId: "c\\d", agentId: "e", membershipRevision: 4)
            == "[\"a\\\"b\",\"c\\\\d\",\"e\",4]"
    )
    #expect(StoragePaths.workspaceIdForOwner("hello") == StoragePaths.sha256Hex("hello"))
    #expect(
        StoragePaths.workspaceRecordPathForOwner("hello")
            == "workspaces/2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824.json"
    )
    let room = "2cb5ddf410150fdff33e0d2840a0481f82a53303884c6f616df48103e67bc74b"
    let session = "082a03f3b2161cb9b2458ce6d5c42251c3d4a57a242d581d33f83308adc4fd4e"
    #expect(
        StoragePaths.workSessionDir(workId: "room-1", taskId: "task-1", agentId: "agent-1", membershipRevision: 2)
            == "work-sessions/\(room)/\(session)"
    )
    #expect(
        StoragePaths.workSessionRecordPath(workId: "room-1", taskId: "task-1", agentId: "agent-1", membershipRevision: 2)
            == "work-sessions/\(room)/\(session)/session.json"
    )
    #expect(
        StoragePaths.workSessionTranscriptPath(workId: "room-1", taskId: "task-1", agentId: "agent-1", membershipRevision: 2)
            == "work-sessions/\(room)/\(session)/transcript.jsonl"
    )
    #expect(
        FileAgentStore.workSessionDir(workId: "room-1", taskId: "task-1", agentId: "agent-1", membershipRevision: 2)
            == StoragePaths.workSessionDir(workId: "room-1", taskId: "task-1", agentId: "agent-1", membershipRevision: 2)
    )
    #expect(
        FileAgentStore.workSessionRecordPath(workId: "room-1", taskId: "task-1", agentId: "agent-1", membershipRevision: 2)
            == StoragePaths.workSessionRecordPath(workId: "room-1", taskId: "task-1", agentId: "agent-1", membershipRevision: 2)
    )
    #expect(
        FileAgentStore.workSessionTranscriptPath(workId: "room-1", taskId: "task-1", agentId: "agent-1", membershipRevision: 2)
            == StoragePaths.workSessionTranscriptPath(workId: "room-1", taskId: "task-1", agentId: "agent-1", membershipRevision: 2)
    )
    #expect(
        FileAgentStore.cardSessionId(workId: "room-1", taskId: "task-1", agentId: "agent-1", membershipRevision: 2)
            == session
    )
    #expect(FileAgentStore.workspaceIdForOwner("hello") == StoragePaths.workspaceIdForOwner("hello"))
    #expect(FileAgentStore.migrationsPath() == "migrations.json")
    #expect(FileAgentStore.migrationsPath() == NuumPaths.migrationsPath())
}
