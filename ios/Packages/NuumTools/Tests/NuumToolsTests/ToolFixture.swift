import NuumContracts
@testable import NuumTools

let runID = "run-1"

struct ToolFixture {
    var files: MemoryToolFileSystem
    var backend: LocalToolBackend
    var home: String
    var project: String
    var scratch: String
    var secret: String
    var memory: String

    func run(_ name: String, _ args: [String: JSONValue] = [:]) async throws -> ToolExecutionResult {
        try await backend.execute(runId: runID, call: ToolCall(id: "call-1", name: name, arguments: args))
    }

    func authorize(_ action: LocalToolAction, _ target: String) async throws -> PermissionVerdict {
        try await backend.authorize(runId: runID, action: action, target: target)
    }
}

func fixture(
    permission: ToolPermission = .never,
    project: String? = "/home/project",
    readOnly: [String] = [],
    approvals: [ToolApproval] = [],
    refused: [ToolApproval] = [],
    denied: [String]? = nil,
    files: MemoryToolFileSystem = MemoryToolFileSystem()
) -> ToolFixture {
    let home = "/home"
    let scratch = "/home/.nuum/agents/a1/scratch"
    let secret = "/home/.nuum/host-secrets.json"
    let memory = "/home/.nuum/agents/a1/memory/profile.md"
    files.mkdir("/home/project")
    files.mkdir(scratch)
    files.mkdir("/home/.nuum/agents/a1/memory")
    files.seed(secret, "top-secret-value")
    let backend = LocalToolBackend(files: files)
    backend.bind(
        runId: runID,
        roots: ToolRoots(
            home: home,
            project: project,
            scratch: scratch,
            terminals: "/home/.nuum/agents/a1/terminals",
            denied: denied ?? [secret],
            readOnly: readOnly
        ),
        permission: permission,
        approvals: approvals,
        refused: refused
    )
    return ToolFixture(
        files: files,
        backend: backend,
        home: home,
        project: project ?? scratch,
        scratch: scratch,
        secret: secret,
        memory: memory
    )
}
