import Foundation
import NuumContracts

struct LoadedWork {
    var entry: WorkListEntry
    var tasks: [TaskListEntry]
}

struct ListProjection {
    private var agentsByID: [String: AgentListEntry] = [:]
    private var worksByID: [String: WorkListEntry] = [:]
    private var tasksByWork: [String: [String: TaskListEntry]] = [:]
    private var sections: [SidebarSectionEntry] = []
    private var pins: [String] = []
    private var builtVersion: Int?

    mutating func discard() {
        agentsByID.removeAll()
        worksByID.removeAll()
        tasksByWork.removeAll()
        sections.removeAll()
        pins.removeAll()
        builtVersion = nil
    }

    func needsRebuild(root: URL) -> Bool {
        let version = readMigrationVersion(root: root)
        if builtVersion == nil || builtVersion != version { return true }
        if agentsByID.isEmpty && countProfiles(root: root, directory: "agents") > 0 { return true }
        if worksByID.isEmpty && countProfiles(root: root, directory: "works") > 0 { return true }
        return false
    }

    mutating func rebuild(root: URL) throws {
        let agents = try scanAgents(root: root)
        let works = try scanWorks(root: root)
        let sidebar = try readSidebar(root: root)
        let version = readMigrationVersion(root: root)
        agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        worksByID = Dictionary(uniqueKeysWithValues: works.map { ($0.entry.id, $0.entry) })
        tasksByWork = Dictionary(uniqueKeysWithValues: works.map { loaded in
            (loaded.entry.id, Dictionary(uniqueKeysWithValues: loaded.tasks.map { ($0.taskId, $0) }))
        })
        writeSidebar(sidebar)
        builtVersion = version
    }

    mutating func onWritten(root: URL, relativePath: String) throws {
        if relativePath == StoragePaths.settingsPath() {
            try refreshSidebar(root: root)
        } else if let id = PathMatch.id(in: relativePath, root: "agents", file: "profile.json") {
            try refreshAgent(root: root, id: id)
        } else if let id = PathMatch.id(in: relativePath, root: "agents", file: "settings.json") {
            try refreshAgent(root: root, id: id)
        } else if let id = PathMatch.id(in: relativePath, root: "agents", file: "transcript.jsonl") {
            try refreshAgent(root: root, id: id)
        } else if let id = PathMatch.id(in: relativePath, root: "works", file: "profile.json") {
            try refreshWork(root: root, id: id)
        } else if let id = PathMatch.id(in: relativePath, root: "works", file: "timeline.jsonl") {
            try refreshWork(root: root, id: id)
        }
    }

    mutating func onDeleted(root: URL, relativePath: String) throws {
        if relativePath == StoragePaths.settingsPath() {
            try refreshSidebar(root: root)
        } else if relativePath == "agents" || relativePath == "works" {
            try rebuild(root: root)
        } else if let id = PathMatch.id(in: relativePath, root: "agents") {
            agentsByID.removeValue(forKey: id)
        } else if let id = PathMatch.id(in: relativePath, root: "agents", file: "profile.json") {
            agentsByID.removeValue(forKey: id)
        } else if let id = PathMatch.id(in: relativePath, root: "works") {
            removeWork(id)
        } else if let id = PathMatch.id(in: relativePath, root: "works", file: "profile.json") {
            removeWork(id)
        } else if let id = PathMatch.id(in: relativePath, root: "agents", file: "settings.json") {
            try refreshAgent(root: root, id: id)
        } else if let id = PathMatch.id(in: relativePath, root: "agents", file: "transcript.jsonl") {
            try refreshAgent(root: root, id: id)
        } else if let id = PathMatch.id(in: relativePath, root: "works", file: "timeline.jsonl") {
            try refreshWork(root: root, id: id)
        }
    }

    func agents() -> [AgentListEntry] {
        agentsByID.values.sorted { lhs, rhs in
            if lhs.lastActivityAt != rhs.lastActivityAt { return lhs.lastActivityAt > rhs.lastActivityAt }
            return lhs.id < rhs.id
        }
    }

    func works() -> [WorkListEntry] {
        worksByID.values.sorted { lhs, rhs in
            if lhs.lastActivityAt != rhs.lastActivityAt { return lhs.lastActivityAt > rhs.lastActivityAt }
            return lhs.id < rhs.id
        }
    }

    func tasks(workId: String) -> [TaskListEntry] {
        (tasksByWork[workId] ?? [:]).values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.taskId < rhs.taskId
        }
    }

    func sidebarSections() -> [SidebarSectionEntry] { sections }

    func sidebarPins() -> [String] { pins }

    private mutating func refreshAgent(root: URL, id: String) throws {
        if let entry = try readAgent(root: root, id: id) {
            agentsByID[id] = entry
        } else {
            agentsByID.removeValue(forKey: id)
        }
    }

    private mutating func refreshWork(root: URL, id: String) throws {
        if let loaded = try readWork(root: root, id: id) {
            worksByID[id] = loaded.entry
            tasksByWork[id] = Dictionary(uniqueKeysWithValues: loaded.tasks.map { ($0.taskId, $0) })
        } else {
            removeWork(id)
        }
    }

    private mutating func removeWork(_ id: String) {
        worksByID.removeValue(forKey: id)
        tasksByWork.removeValue(forKey: id)
    }

    private mutating func refreshSidebar(root: URL) throws {
        writeSidebar(try readSidebar(root: root))
    }

    private mutating func writeSidebar(_ sidebar: SidebarOrganization?) {
        pins = sidebar?.pinnedAgentIds ?? []
        sections = sidebar?.sections.map { section in
            SidebarSectionEntry(
                id: section.id,
                name: section.name,
                agentIds: section.agentIds,
                isCollapsed: section.isCollapsed
            )
        } ?? []
    }

    private func readSidebar(root: URL) throws -> SidebarOrganization? {
        let url = fileURL(root, StoragePaths.settingsPath())
        guard isRegularFile(url) else { return nil }
        let data = try Data(contentsOf: url)
        return SettingsJSON.decode(String(decoding: data, as: UTF8.self)).sidebar
    }
}

enum PathMatch {
    static func id(in path: String, root: String, file: String? = nil) -> String? {
        let prefix = root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let rest = path.dropFirst(prefix.count)
        if let file {
            let suffix = "/" + file
            guard rest.hasSuffix(suffix) else { return nil }
            let id = rest.dropLast(suffix.count)
            guard !id.isEmpty, !id.contains("/") else { return nil }
            return String(id)
        }
        guard !rest.isEmpty, !rest.contains("/") else { return nil }
        return String(rest)
    }
}

private func countProfiles(root: URL, directory: String) -> Int {
    let dir = root.appendingPathComponent(directory, isDirectory: true)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue else { return 0 }
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return 0 }
    return names.reduce(into: 0) { count, name in
        let child = dir.appendingPathComponent(name, isDirectory: true)
        var childIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: child.path, isDirectory: &childIsDirectory), childIsDirectory.boolValue else { return }
        if isRegularFile(child.appendingPathComponent("profile.json")) {
            count += 1
        }
    }
}

private func scanAgents(root: URL) throws -> [AgentListEntry] {
    let dir = root.appendingPathComponent("agents", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    var entries: [AgentListEntry] = []
    for name in names {
        let child = dir.appendingPathComponent(name, isDirectory: true)
        var childIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: child.path, isDirectory: &childIsDirectory), childIsDirectory.boolValue else { continue }
        if let entry = try readAgent(root: root, id: name) {
            entries.append(entry)
        }
    }
    return entries
}

private func scanWorks(root: URL) throws -> [LoadedWork] {
    let dir = root.appendingPathComponent("works", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    var entries: [LoadedWork] = []
    for name in names {
        let child = dir.appendingPathComponent(name, isDirectory: true)
        var childIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: child.path, isDirectory: &childIsDirectory), childIsDirectory.boolValue else { continue }
        if let loaded = try readWork(root: root, id: name) {
            entries.append(loaded)
        }
    }
    return entries
}

private func readAgent(root: URL, id: String) throws -> AgentListEntry? {
    let profile = fileURL(root, StoragePaths.profilePath(id))
    guard isRegularFile(profile) else { return nil }
    let text = String(decoding: try Data(contentsOf: profile), as: UTF8.self)
    guard var parsed = parseAgentProfile(directoryName: id, text: text) else { return nil }
    let settings = fileURL(root, StoragePaths.agentSettingsPath(id))
    let hidden = isRegularFile(settings)
        ? parseHiddenFromSidebar(String(decoding: try Data(contentsOf: settings), as: UTF8.self))
        : false
    let activity = try JsonlFiles.lastCreatedAt(fileURL(root, StoragePaths.transcriptPath(id)))
    parsed.hiddenFromSidebar = hidden
    parsed.lastActivityAt = max(parsed.createdAt, activity)
    return parsed
}

private func readWork(root: URL, id: String) throws -> LoadedWork? {
    let profile = fileURL(root, StoragePaths.workProfilePath(id))
    guard isRegularFile(profile) else { return nil }
    let text = String(decoding: try Data(contentsOf: profile), as: UTF8.self)
    guard let parsed = parseWorkProfile(directoryName: id, text: text) else { return nil }
    let lines = try JsonlFiles.readLines(fileURL(root, StoragePaths.workTimelinePath(id)))
    let fold = foldTimeline(workId: id, lines: lines)
    let entry = WorkListEntry(
        id: parsed.id,
        name: parsed.name,
        description: parsed.description,
        projectRoot: parsed.projectRoot,
        createdAt: parsed.createdAt,
        kind: parsed.kind,
        avatar: parsed.avatar,
        workspaceId: parsed.workspaceId,
        lastActivityAt: max(parsed.createdAt, fold.lastActivityAt),
        preview: fold.preview
    )
    return LoadedWork(entry: entry, tasks: Array(fold.tasks.values))
}
