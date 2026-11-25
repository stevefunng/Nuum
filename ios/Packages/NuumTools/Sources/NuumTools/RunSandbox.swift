import Foundation
import NuumContracts
import Synchronization

struct BinaryFile {
    var path: String
    var data: Data
}

struct DeletedPath: Equatable {
    var path: String
    var kind: String
}

/// Path decision order, matching `create-sandbox.ts` and the Android tools package:
/// unauthorized bookmark, sealed filename or denied root, read-only knowledge,
/// must sit under home, scratch, or the granted project, scratch and project are
/// pre-approved, agent stores are read-only, then always / ask / never.
///
/// A user-picked directory is a real filesystem `project` root. It stays allowed
/// when it lives outside the app container. A bookmark that has not been started
/// is reported by `ToolFileSystem.lacksAccess` and rejected as outside the root.
final class RunSandbox: Sendable {
    private struct State: Sendable {
        var permission: ToolPermission
        var approvals: Set<String>
        var refused: Set<String>
    }

    private let files: any ToolFileSystem
    private let state: Mutex<State>
    let cwd: String
    private let home: String
    private let scratch: String
    private let project: String?
    private let denied: [String]
    private let readOnly: [String]
    private let agentsRoot: String

    init(
        files: any ToolFileSystem,
        roots: ToolRoots,
        permission: ToolPermission,
        approvals: [ToolApproval],
        refused: [ToolApproval]
    ) {
        self.files = files
        self.cwd = roots.project ?? roots.scratch
        self.home = files.canonicalize(cwd: roots.home, input: roots.home)
        self.scratch = files.canonicalize(cwd: roots.scratch, input: roots.scratch)
        self.project = roots.project.map { files.canonicalize(cwd: $0, input: $0) }
        self.denied = roots.denied.map { files.canonicalize(cwd: $0, input: $0) }
        self.readOnly = roots.readOnly.map { files.canonicalize(cwd: $0, input: $0) }
        self.agentsRoot = parentPath(parentPath(self.scratch))
        self.state = Mutex(State(
            permission: permission,
            approvals: Set(approvals.map(approvalKey)),
            refused: Set(refused.map(approvalKey))
        ))
    }

    func authorize(_ action: LocalToolAction, _ input: String) -> PermissionVerdict {
        state.withLock { state in
            if action == .runCommand { return authorizeCommand(input, state: &state) }
            if action == .network {
                let target = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(empty)" : input
                return standingDecision(action, target, state: &state)
            }
            return authorizePath(action, input, state: &state)
        }
    }

    func grantOnce(_ action: LocalToolAction, _ target: String) {
        let key = approvalKey(ToolApproval(action: action, target: target))
        state.withLock { state in
            state.approvals.insert(key)
            return ()
        }
    }

    func refuse(_ action: LocalToolAction, _ target: String) {
        let key = approvalKey(ToolApproval(action: action, target: target))
        state.withLock { state in
            state.refused.insert(key)
            return ()
        }
    }

    func setPermission(_ permission: ToolPermission) {
        state.withLock { state in
            state.permission = permission
            return ()
        }
    }

    func requireAllowed(_ action: LocalToolAction, _ input: String, withPeriod: Bool = false) throws -> String {
        let verdict = authorize(action, input)
        if verdict.decision == .allow { return verdict.target }
        let fallback = if withPeriod {
            "Approval is required for \(action.rawValue) \(verdict.target)."
        } else {
            "Approval is required for \(action.rawValue) \(verdict.target)"
        }
        throw NuumError(code: KernelErrorCode.sandbox, message: verdict.reason ?? fallback)
    }

    func readText(_ inputPath: String) throws -> String {
        let resolved = try requireAllowed(.readFile, inputPath)
        return String(decoding: try readResolved(resolved), as: UTF8.self)
    }

    func readBinary(_ inputPath: String) throws -> BinaryFile {
        let resolved = try requireAllowed(.readFile, inputPath)
        return BinaryFile(path: resolved, data: try readResolved(resolved))
    }

    func writeText(_ inputPath: String, _ content: String) throws -> FileMutation {
        let resolved = try requireAllowed(.writeFile, inputPath)
        let before = try existingText(resolved)
        try files.writeBytes(resolved, Data(content.utf8))
        return FileMutation(path: resolved, before: before, after: content)
    }

    func mutateText(_ inputPath: String, _ transform: (String) throws -> String) throws -> FileMutation {
        let resolved = try requireAllowed(.writeFile, inputPath)
        let current: String
        do {
            current = String(decoding: try readResolved(resolved), as: UTF8.self)
        } catch let error as NuumError where error.message.hasPrefix("No such file:") {
            throw NuumError(code: KernelErrorCode.tool, message: "No such file: \(inputPath)")
        }
        let next = try transform(current)
        try files.writeBytes(resolved, Data(next.utf8))
        return FileMutation(path: resolved, before: current, after: next)
    }

    func deletePath(_ inputPath: String) throws -> DeletedPath {
        let resolved = try requireAllowed(.writeFile, inputPath)
        if !files.exists(resolved) {
            throw NuumError(code: KernelErrorCode.tool, message: "No such file: \(inputPath)")
        }
        let kind = files.isDirectory(resolved) ? "directory" : "file"
        try files.delete(resolved)
        return DeletedPath(path: resolved, kind: kind)
    }

    func list(_ resolved: String) throws -> [ToolDirEntry] {
        if !files.exists(resolved) {
            throw NuumError(code: KernelErrorCode.tool, message: "No such file: \(resolved)")
        }
        if !files.isDirectory(resolved) {
            throw NuumError(code: KernelErrorCode.tool, message: "Not a directory: \(resolved)")
        }
        return try files.list(resolved)
    }

    func exists(_ resolved: String) -> Bool { files.exists(resolved) }

    func isDirectory(_ resolved: String) -> Bool { files.isDirectory(resolved) }

    func lastModifiedMillis(_ resolved: String) -> Int64 {
        (try? files.lastModifiedMillis(resolved)) ?? 0
    }

    /// Already-authorized path. Callers must not follow a symlink the policy did not check.
    func readBytes(_ resolved: String) throws -> Data {
        try readResolved(resolved)
    }

    func permits(_ action: LocalToolAction, resolved path: String) -> Bool {
        authorize(action, path).decision == .allow
    }

    private func readResolved(_ resolved: String) throws -> Data {
        do {
            return try files.readBytes(resolved)
        } catch is MissingPath {
            throw NuumError(code: KernelErrorCode.tool, message: "No such file: \(resolved)")
        }
    }

    private func existingText(_ resolved: String) throws -> String? {
        do {
            return String(decoding: try files.readBytes(resolved), as: UTF8.self)
        } catch is MissingPath {
            return nil
        }
    }

    private func authorizePath(
        _ action: LocalToolAction,
        _ input: String,
        state: inout State
    ) -> PermissionVerdict {
        let target = files.canonicalize(cwd: cwd, input: input)
        if files.lacksAccess(target) {
            return deny(action, target, outsideRoot)
        }
        if isSealedSecretPath(target) || denied.contains(where: { pathContains($0, target) }) {
            return deny(action, target, protectedStore)
        }
        if readOnly.contains(where: { pathContains($0, target) }) {
            if action == .readFile || action == .listDirectory {
                return allow(action, target)
            }
            return deny(action, target, "Path is a Work read-only knowledge root.")
        }
        let underHome = pathContains(home, target)
        let underScratch = pathContains(scratch, target)
        let underProject = project.map { pathContains($0, target) } ?? false
        if !underHome && !underScratch && !underProject {
            return deny(action, target, outsideRoot)
        }
        if underScratch || underProject {
            return allow(action, target)
        }
        if pathContains(agentsRoot, target) {
            if action == .readFile || action == .listDirectory {
                return allow(action, target)
            }
            return deny(action, target, "Agent stores are read-only; use update_state for your own state.")
        }
        return standingDecision(action, target, state: &state)
    }

    private func authorizeCommand(_ command: String, state: inout State) -> PermissionVerdict {
        let target = commandToken(command)
        if target.isEmpty {
            return deny(.runCommand, "(empty)", "Command is empty.")
        }
        return standingDecision(.runCommand, target, state: &state)
    }

    private func standingDecision(
        _ action: LocalToolAction,
        _ target: String,
        state: inout State
    ) -> PermissionVerdict {
        let key = approvalKey(ToolApproval(action: action, target: target))
        if state.approvals.contains(key) { return allow(action, target) }
        if state.refused.contains(key) {
            return deny(action, target, "The same action was previously refused.")
        }
        switch state.permission {
        case .always:
            return allow(action, target)
        case .never:
            return deny(action, target, "Local tools are disabled for this agent.")
        case .ask:
            return PermissionVerdict(decision: .ask, target: target)
        }
    }

    private func allow(_ action: LocalToolAction, _ target: String) -> PermissionVerdict {
        _ = action
        return PermissionVerdict(decision: .allow, target: target)
    }

    private func deny(_ action: LocalToolAction, _ target: String, _ reason: String) -> PermissionVerdict {
        _ = action
        return PermissionVerdict(decision: .deny, target: target, reason: reason)
    }
}

func isSealedSecretPath(_ path: String) -> Bool {
    let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    guard let name = trimmed.split(separator: "/").last else { return false }
    let folded = name.lowercased()
    return SealedSecretFilename.all.contains { $0.lowercased() == folded }
}

private func approvalKey(_ approval: ToolApproval) -> String {
    "\(approval.action.rawValue)\u{0000}\(approval.target)"
}
