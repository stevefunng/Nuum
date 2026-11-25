import Foundation
import NuumContracts
import Testing
@testable import NuumTools

@Test func alwaysStillCannotReadTheSecretsPath() async throws {
    let item = fixture(permission: .always)
    let verdict = try await item.authorize(.readFile, item.secret)
    #expect(verdict.decision == .deny)
    #expect(verdict.reason == protectedStore)
    let read = try await item.run("read", ["path": .string(item.secret)])
    #expect(read.ok == false)
    #expect(read.output == protectedStore)
    #expect(!read.output.contains("top-secret-value"))
}

@Test func aParentTraversalIntoSecretsIsStillDenied() async throws {
    let item = fixture(permission: .always)
    let verdict = try await item.authorize(.readFile, "/home/project/../.nuum/host-secrets.json")
    #expect(verdict.decision == .deny)
    #expect(verdict.reason?.contains("protected host-only") == true)
}

@Test func scratchIsWritableEvenWhenStandingPermissionIsNever() async throws {
    let item = fixture(permission: .never)
    let path = "\(item.scratch)/note.txt"
    let written = try await item.run("write", ["path": .string(path), "content": .string("draft")])
    #expect(written.ok)
    #expect(written.output.contains("Created"))
    #expect(item.files.text(path) == "draft")
    #expect(try await item.authorize(.writeFile, path).decision == .allow)
}

@Test func agentMemoryPathIsNotWritable() async throws {
    let item = fixture(permission: .always)
    let write = try await item.authorize(.writeFile, item.memory)
    #expect(write.decision == .deny)
    #expect(write.reason == "Agent stores are read-only; use update_state for your own state.")
    let result = try await item.run("write", ["path": .string(item.memory), "content": .string("nope")])
    #expect(result.ok == false)
    #expect(result.output.contains("read-only"))
    #expect(item.files.text(item.memory) == nil)
    #expect(try await item.authorize(.readFile, item.memory).decision == .allow)
}

@Test func projectPathsArePreApprovedAndPathsOutsideHomeAreDenied() async throws {
    let item = fixture(permission: .never)
    #expect(try await item.authorize(.writeFile, "\(item.project)/x").decision == .allow)
    let outside = try await item.authorize(.readFile, "/tmp/outside/x")
    #expect(outside.decision == .deny)
    #expect(outside.reason == outsideRoot)
}

@Test func knowledgeRootsAreReadableAndNotWritable() async throws {
    let knowledge = "/home/knowledge/guide.md"
    let item = fixture(permission: .always, readOnly: ["/home/knowledge"])
    #expect(try await item.authorize(.readFile, knowledge).decision == .allow)
    #expect(try await item.authorize(.listDirectory, "/home/knowledge").decision == .allow)
    let write = try await item.authorize(.writeFile, knowledge)
    #expect(write.decision == .deny)
    #expect(write.reason == "Path is a Work read-only knowledge root.")
}

@Test func approvalsAndRefusalsMatchTheExactActionAndPath() async throws {
    let asked = fixture(permission: .ask)
    let target = try await asked.authorize(.readFile, "/home/notes/one.txt").target
    #expect(try await asked.authorize(.readFile, target).decision == .ask)

    let approved = fixture(
        permission: .ask,
        approvals: [ToolApproval(action: .readFile, target: target)]
    )
    #expect(try await approved.authorize(.readFile, target).decision == .allow)
    #expect(try await approved.authorize(.readFile, "/home/notes").decision == .ask)
    #expect(try await approved.authorize(.writeFile, target).decision == .ask)

    approved.backend.grantOnce(runId: runID, action: .writeFile, target: target)
    #expect(try await approved.authorize(.writeFile, target).decision == .allow)

    let refused = fixture(
        permission: .ask,
        refused: [ToolApproval(action: .readFile, target: target)]
    )
    let verdict = try await refused.authorize(.readFile, "/home/notes/one.txt")
    #expect(verdict.decision == .deny)
    #expect(verdict.reason?.contains("previously refused") == true)
}

@Test func commandAuthorizationUsesTheExecutableTokenAndDoesNotLaunchAnything() async throws {
    let item = fixture(
        permission: .ask,
        approvals: [ToolApproval(action: .runCommand, target: "git")]
    )
    let git = try await item.authorize(.runCommand, "FOO=1 /usr/bin/git status")
    #expect(git.decision == .allow)
    #expect(git.target == "git")
    let npm = try await item.authorize(.runCommand, "npm test")
    #expect(npm.decision == .ask)
    #expect(npm.target == "npm")
    let empty = try await item.authorize(.runCommand, "   ")
    #expect(empty.decision == .deny)
    #expect(empty.target == "(empty)")
    #expect(empty.reason == "Command is empty.")
}

@Test func sealedFilenamesStayUnreadableEvenWhenAlwaysAndNotDenied() async throws {
    let item = fixture(permission: .always, denied: [])
    let marker = "top-secret-value"
    for name in SealedSecretFilename.all {
        let path = "\(item.project)/\(name)"
        item.files.seed(path, marker)
        let verdict = try await item.authorize(.readFile, path)
        #expect(verdict.decision == .deny)
        #expect(verdict.reason == protectedStore)
        let read = try await item.run("read", ["path": .string(path)])
        #expect(read.ok == false)
        #expect(!read.output.contains(marker))
        let scratchPath = "\(item.scratch)/\(name)"
        item.files.seed(scratchPath, marker)
        let scratchWrite = try await item.run("write", ["path": .string(scratchPath), "content": .string("nope")])
        #expect(scratchWrite.ok == false)
        #expect(item.files.text(scratchPath) == marker)
    }
    let alias = "\(item.project)/\(SealedSecretFilename.secretsBin.uppercased())"
    item.files.seed(alias, marker)
    let aliasRead = try await item.run("read", ["path": .string(alias)])
    #expect(aliasRead.ok == false)
    #expect(!aliasRead.output.contains(marker))

    item.files.seed("\(item.project)/notes.txt", "visible hit")
    let searched = try await item.run("grep", ["pattern": .string(marker), "path": .string(item.project)])
    #expect(searched.ok)
    #expect(searched.output == "No matches found.")
    let visible = try await item.run("grep", ["pattern": .string("visible"), "path": .string(item.project)])
    #expect(visible.output.contains("notes.txt"))
    #expect(!visible.output.contains(marker))
}

@Test func aGrantedBookmarkOutsideHomeIsWritable() async throws {
    let picked = "/picked/docs"
    let item = fixture(permission: .never, project: picked)
    let path = "\(picked)/notes/a.txt"
    let written = try await item.run("write", ["path": .string(path), "content": .string("hello")])
    #expect(written.ok)
    #expect(item.files.text(path) == "hello")
    let read = try await item.run("read", ["path": .string(path)])
    #expect(read.output == "hello")
    #expect(try await item.authorize(.writeFile, path).decision == .allow)
    let escaped = try await item.authorize(.readFile, "\(picked)/../../etc/passwd")
    #expect(escaped.decision == .deny)
    #expect(escaped.reason == outsideRoot)
}

@Test func anUnauthorizedBookmarkIsOutsideTheAllowedRoot() async throws {
    let picked = "/picked/docs"
    let files = MemoryToolFileSystem()
    files.unauthorizedRoots = ["/picked"]
    let item = fixture(permission: .always, project: picked, files: files)
    let path = "\(picked)/notes.md"
    files.seed(path, "bookmark-secret")
    let verdict = try await item.authorize(.readFile, path)
    #expect(verdict.decision == .deny)
    #expect(verdict.reason == outsideRoot)
    let read = try await item.run("read", ["path": .string(path)])
    #expect(read.ok == false)
    #expect(read.output == outsideRoot)
    #expect(!read.output.contains("bookmark-secret"))
    #expect(files.text(path) == "bookmark-secret")
}

@Test func aSymlinkCannotEscapeTheHomeRoot() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuum-tools-\(UUID().uuidString)")
    let outside = FileManager.default.temporaryDirectory.appendingPathComponent("nuum-outside-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }
    let home = root.appendingPathComponent("home")
    let project = home.appendingPathComponent("project")
    let scratch = home.appendingPathComponent(".nuum/agents/a1/scratch")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let secretFile = outside.appendingPathComponent("secret.txt")
    try Data("outside-secret".utf8).write(to: secretFile)
    try FileManager.default.createSymbolicLink(
        atPath: project.appendingPathComponent("escape").path,
        withDestinationPath: outside.path
    )
    let backend = LocalToolBackend()
    backend.bind(
        runId: runID,
        roots: ToolRoots(
            home: home.path,
            project: project.path,
            scratch: scratch.path,
            terminals: scratch.deletingLastPathComponent().appendingPathComponent("terminals").path,
            denied: []
        ),
        permission: .always,
        approvals: [],
        refused: []
    )
    let target = project.appendingPathComponent("escape").appendingPathComponent("x.txt").path
    let verdict = try await backend.authorize(runId: runID, action: .writeFile, target: target)
    #expect(verdict.decision == .deny)
    #expect(verdict.reason?.contains("outside the allowed local execution root") == true)
    let written = try await backend.execute(
        runId: runID,
        call: ToolCall(id: "call-1", name: "write", arguments: [
            "path": .string(target),
            "content": .string("escaped"),
        ])
    )
    #expect(written.ok == false)
    #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("x.txt").path))
    let read = try await backend.execute(
        runId: runID,
        call: ToolCall(id: "call-2", name: "read", arguments: [
            "path": .string(project.appendingPathComponent("escape/secret.txt").path),
        ])
    )
    #expect(read.ok == false)
    #expect(!read.output.contains("outside-secret"))

    let inside = project.appendingPathComponent("note.txt").path
    let saved = try await backend.execute(
        runId: runID,
        call: ToolCall(id: "call-3", name: "write", arguments: [
            "path": .string(inside),
            "content": .string("kept"),
        ])
    )
    #expect(saved.ok)
    let loaded = try await backend.execute(
        runId: runID,
        call: ToolCall(id: "call-4", name: "read", arguments: ["path": .string(inside)])
    )
    #expect(loaded.output == "kept")
}
