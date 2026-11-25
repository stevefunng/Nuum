import NuumContracts

/// Applies the denied-root carve at `bind` time.
/// Scratch, the current project, and read-only knowledge stay usable.
/// Secret filenames stay denied even if a caller lists them as exceptions.
final class CarvingToolBackend: ToolBackend, Sendable {
    private let delegate: any ToolBackend
    private let sealed: [String]

    init(delegate: any ToolBackend, sealed: [String]) {
        self.delegate = delegate
        self.sealed = sealed
    }

    func definitions() -> [ToolDefinition] {
        delegate.definitions()
    }

    func bind(
        runId: String,
        roots: ToolRoots,
        permission: ToolPermission,
        approvals: [ToolApproval],
        refused: [ToolApproval]
    ) {
        var exceptions = [roots.scratch]
        if let project = roots.project {
            exceptions.append(project)
        }
        exceptions.append(contentsOf: roots.readOnly)
        var carved = roots
        carved.denied = carveDeniedRoots(denied: roots.denied, exceptions: exceptions, sealed: sealed)
        delegate.bind(
            runId: runId,
            roots: carved,
            permission: permission,
            approvals: approvals,
            refused: refused
        )
    }

    func authorize(runId: String, action: LocalToolAction, target: String) async throws -> PermissionVerdict {
        try await delegate.authorize(runId: runId, action: action, target: target)
    }

    func grantOnce(runId: String, action: LocalToolAction, target: String) {
        delegate.grantOnce(runId: runId, action: action, target: target)
    }

    func refuse(runId: String, action: LocalToolAction, target: String) {
        delegate.refuse(runId: runId, action: action, target: target)
    }

    func setPermission(runId: String, permission: ToolPermission) {
        delegate.setPermission(runId: runId, permission: permission)
    }

    func execute(runId: String, call: ToolCall) async throws -> ToolExecutionResult {
        try await delegate.execute(runId: runId, call: call)
    }

    func release(runId: String) {
        delegate.release(runId: runId)
    }
}
