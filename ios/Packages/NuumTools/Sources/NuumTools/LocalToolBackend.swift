import NuumContracts
import Synchronization

/// File tools and `grep` for one run, plus the three tools this client does not execute.
/// `shell`, `request_network`, and `external_operation` stay in the table and return
/// `UnimplementedToolMessage.iosClient`. Nothing is spawned and no request is opened.
///
/// `unauthorizedRoots` are bookmark directories whose access has not been started.
/// Paths inside them are rejected as outside the allowed root even when `project` names them.
public final class LocalToolBackend: ToolBackend, Sendable {
    private let files: any ToolFileSystem
    private let registry: ToolRegistry
    private let sessions: Mutex<[String: RunSandbox]>

    public convenience init(unauthorizedRoots: [String] = []) {
        self.init(files: FoundationToolFileSystem(unauthorizedRoots: unauthorizedRoots))
    }

    init(files: any ToolFileSystem, registry: ToolRegistry = .builtin()) {
        self.files = files
        self.registry = registry
        self.sessions = Mutex([:])
    }

    public func definitions() -> [ToolDefinition] {
        registry.list()
    }

    public func list(names: [String]? = nil) -> [ToolDefinition] {
        registry.list(names: names)
    }

    public func bind(
        runId: String,
        roots: ToolRoots,
        permission: ToolPermission,
        approvals: [ToolApproval],
        refused: [ToolApproval]
    ) {
        let sandbox = RunSandbox(
            files: files,
            roots: roots,
            permission: permission,
            approvals: approvals,
            refused: refused
        )
        sessions.withLock { sessions in
            sessions[runId] = sandbox
            return ()
        }
    }

    public func authorize(runId: String, action: LocalToolAction, target: String) async throws -> PermissionVerdict {
        try sandbox(runId).authorize(action, target)
    }

    public func grantOnce(runId: String, action: LocalToolAction, target: String) {
        sandboxIfBound(runId)?.grantOnce(action, target)
    }

    public func refuse(runId: String, action: LocalToolAction, target: String) {
        sandboxIfBound(runId)?.refuse(action, target)
    }

    public func setPermission(runId: String, permission: ToolPermission) {
        sandboxIfBound(runId)?.setPermission(permission)
    }

    public func execute(runId: String, call: ToolCall) async throws -> ToolExecutionResult {
        guard let tool = registry.tool(named: call.name) else {
            throw NuumError(code: KernelErrorCode.tool, message: "Unknown tool: \(call.name)")
        }
        let sandbox = try sandbox(runId)
        do {
            return try tool.execute(call.arguments, sandbox: sandbox)
        } catch let error as NuumError {
            return ToolExecutionResult(ok: false, output: error.message)
        }
    }

    public func release(runId: String) {
        sessions.withLock { sessions in
            sessions.removeValue(forKey: runId)
            return ()
        }
    }

    private func sandbox(_ runId: String) throws -> RunSandbox {
        guard let sandbox = sandboxIfBound(runId) else {
            throw NuumError(
                code: KernelErrorCode.invalid,
                message: "No tool session is bound for run \(runId)."
            )
        }
        return sandbox
    }

    private func sandboxIfBound(_ runId: String) -> RunSandbox? {
        sessions.withLock { sessions in
            sessions[runId]
        }
    }
}
