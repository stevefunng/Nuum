import Foundation
import NuumContracts
import NuumStorage
import Testing

@Test func deletedProjectionRebuildsTheAgentListFromProfileJson() async throws {
    try await withStore { store in
        try await store.writeTextAtomic(
            NuumPaths.profilePath("a1"),
            text: #"{"id":"a1","name":"One","description":"hello","createdAt":1000,"tags":[" Research ","Research"],"avatarColor":"blue"}"#
        )
        try await store.writeTextAtomic(
            NuumPaths.agentSettingsPath("a1"),
            text: #"{"model":{"provider":"deepseek","model":"deepseek-chat"},"hiddenFromSidebar":true}"#
        )
        try await store.appendLine(
            NuumPaths.transcriptPath("a1"),
            line: #"{"type":"user","id":"u1","seq":1,"createdAt":9000,"text":"hi"}"#
        )
        try await store.writeTextAtomic(
            NuumPaths.profilePath("a2"),
            text: #"{"id":"a2","name":"Two","description":"","createdAt":2000}"#
        )

        let listed = await store.agentList()
        #expect(listed.map(\.id) == ["a1", "a2"])
        let first = try #require(listed.first)
        #expect(first.name == "One")
        #expect(first.description == "hello")
        #expect(first.tags == ["Research"])
        #expect(first.avatarColor == "blue")
        #expect(first.hiddenFromSidebar)
        #expect(first.lastActivityAt == 9000)

        await store.discardListProjection()
        #expect(await store.agentList().isEmpty)
        #expect(try await store.readText(NuumPaths.profilePath("a1")) != nil)

        try await store.rebuildListProjection()
        let rebuilt = await store.agentList()
        #expect(rebuilt.map(\.id) == ["a1", "a2"])
        #expect(rebuilt.first?.name == "One")
        #expect(rebuilt.first?.lastActivityAt == 9000)
        #expect(rebuilt.dropFirst().first?.lastActivityAt == 2000)
        #expect(rebuilt.first?.hiddenFromSidebar == true)

        await store.discardListProjection()
        try await store.open()
        #expect(await store.agentList().map(\.id) == ["a1", "a2"])
    }
}

@Test func workTasksRebuildFromTheTimelineAndATornLineIsNotATask() async throws {
    try await withStore { store in
        try await store.writeTextAtomic(
            NuumPaths.workProfilePath("w1"),
            text: #"{"id":"w1","name":"Room","description":"d","projectRoot":null,"createdAt":10,"kind":"room"}"#
        )
        let created = #"{"type":"task.created","id":"e1","workId":"w1","seq":1,"createdAt":50,"actor":{"kind":"agent","id":"a1"},"task":{"id":"t1","title":"Write spec","description":"","state":"proposed","assigneeIds":[],"revision":1,"updatedAt":50}}"#
        let transitioned = #"{"type":"task.transitioned","id":"e2","workId":"w1","seq":2,"createdAt":80,"actor":{"kind":"user","id":"u"},"taskId":"t1","from":"proposed","to":"ready","revision":2}"#
        let chat = #"{"type":"chat.posted","id":"e3","workId":"w1","seq":3,"createdAt":90,"actor":{"kind":"user","id":"u"},"messageId":"m1","body":"hello   room","mentionedAgentIds":[]}"#
        try await store.writeTextAtomic(
            NuumPaths.workTimelinePath("w1"),
            text: "\(created)\n\(transitioned)\n\(chat)\n"
        )
        try appendRaw(
            root: store.root,
            relative: NuumPaths.workTimelinePath("w1"),
            text: #"{"type":"task.created","id":"e4","task":{"id":"t-torn""#
        )

        await store.discardListProjection()
        try await store.rebuildListProjection()

        let work = try #require(await store.workList().first)
        #expect(await store.workList().count == 1)
        #expect(work.name == "Room")
        #expect(work.kind == "room")
        #expect(work.lastActivityAt == 90)
        #expect(work.preview == "hello room")
        let task = try #require(await store.taskList("w1").first)
        #expect(await store.taskList("w1").count == 1)
        #expect(task.taskId == "t1")
        #expect(task.title == "Write spec")
        #expect(task.state == "ready")
        #expect(task.revision == 2)
        #expect(task.ownerAgentId == "a1")
        #expect(task.updatedAt == 80)
        let timeline = try #require(await store.readText(NuumPaths.workTimelinePath("w1")))
        #expect(!timeline.contains("t-torn"))
    }
}

@Test func laterTaskEventsUpdateTheRowAndADeletedWorkDropsIt() async throws {
    try await withStore { store in
        try await store.writeTextAtomic(
            NuumPaths.workProfilePath("w1"),
            text: #"{"id":"w1","name":"Room","description":"","projectRoot":null,"createdAt":10,"kind":"room"}"#
        )
        let timeline = NuumPaths.workTimelinePath("w1")
        try await store.appendLine(
            timeline,
            line: #"{"type":"task.created","id":"e1","workId":"w1","seq":1,"createdAt":20,"actor":{"kind":"user","id":"u"},"task":{"id":"t1","title":"Write spec","description":"","state":"proposed","assigneeIds":[],"revision":1,"updatedAt":20}}"#
        )
        try await store.appendLine(
            timeline,
            line: #"{"type":"task.transitioned","id":"e2","workId":"w1","seq":2,"createdAt":30,"actor":{"kind":"user","id":"u"},"taskId":"t1","from":"proposed","to":"ready","revision":2}"#
        )
        try await store.appendLine(
            timeline,
            line: #"{"type":"task.claimed","id":"e3","workId":"w1","seq":3,"createdAt":40,"actor":{"kind":"agent","id":"a2"},"taskId":"t1","assigneeIds":["a2"],"revision":3,"messageId":"m","body":"mine"}"#
        )
        try await store.appendLine(
            timeline,
            line: #"{"type":"task.assigned","id":"e4","workId":"w1","seq":4,"createdAt":41,"actor":{"kind":"user","id":"u"},"taskId":"t1","assigneeIds":["stale"],"revision":2}"#
        )
        try await store.appendLine(
            timeline,
            line: #"{"type":"task.delegated","id":"e5","workId":"w1","seq":5,"createdAt":50,"actor":{"kind":"agent","id":"a1"},"taskId":"t1","agentId":"a3","instruction":"take it","revision":4,"messageId":"m2","membershipRevision":1}"#
        )
        try await store.appendLine(
            timeline,
            line: #"{"type":"task.handed_off","id":"e6","workId":"w1","seq":6,"createdAt":60,"actor":{"kind":"agent","id":"a3"},"taskId":"t1","summary":"ready for review","deliverables":[],"nextStatus":"review","revision":5,"messageId":"m3"}"#
        )
        try await store.appendLine(
            timeline,
            line: #"{"type":"task.transitioned","id":"e7","workId":"w1","seq":7,"createdAt":70,"actor":{"kind":"user","id":"u"},"taskId":"t1","from":"ready","to":"done","revision":6}"#
        )

        let task = try #require(await store.taskList("w1").first)
        #expect(await store.taskList("w1").count == 1)
        #expect(task.state == "review")
        #expect(task.assigneeIds == ["a2", "a3"])
        #expect(task.revision == 5)
        #expect(task.updatedAt == 60)
        #expect(await store.workList().first?.preview == "ready for review")

        try await store.delete(NuumPaths.workDir("w1"))
        #expect(!(try await store.exists(NuumPaths.workProfilePath("w1"))))
        #expect(await store.workList().isEmpty)
        #expect(await store.taskList("w1").isEmpty)
    }
}

@Test func markdownMemoryIsNotInterpreted() async throws {
    try await withStore { store in
        try await store.writeTextAtomic(
            NuumPaths.profilePath("a1"),
            text: #"{"id":"a1","name":"One","description":"","createdAt":1000}"#
        )
        let memory = NuumPaths.memoryDir("a1") + "/profile.md"
        let markdown = "# Secret Name\n\nnot the profile name\n"
        try await store.writeTextAtomic(memory, text: markdown)
        #expect(try await store.readText(memory) == markdown)
        #expect(await store.agentList().first?.name == "One")
        #expect(try await store.list(NuumPaths.memoryDir("a1")) == ["profile.md"])
        try await store.delete(memory)
        #expect(!(try await store.exists(memory)))
        #expect(await store.agentList().first?.name == "One")
        try await store.delete(NuumPaths.agentDir("a1"))
        #expect(!(try await store.exists(NuumPaths.profilePath("a1"))))
        #expect(await store.agentList().isEmpty)
    }
}

@Test func openCreatesTheMacDirectoryLayout() async throws {
    try await withStore { store in
        try await store.open()
        for name in StoragePaths.topLevelDirectories {
            var isDirectory: ObjCBool = false
            let url = store.root.appendingPathComponent(name, isDirectory: true)
            #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: store.root.path).sorted()
        #expect(names == ["agents", "migrations.json", "work-sessions", "works", "workspaces"])
        let marker = try Data(contentsOf: store.root.appendingPathComponent("migrations.json"))
        let json = try #require(JSONSerialization.jsonObject(with: marker) as? [String: Any])
        #expect((json["version"] as? NSNumber)?.intValue == 3)
        #expect(!String(decoding: marker, as: UTF8.self).contains("key"))
    }
}

@Test func legacySessionsDirectorySkipsTheMigrationMarker() async throws {
    try await withStore { store in
        try FileManager.default.createDirectory(
            at: store.root.appendingPathComponent("sessions", isDirectory: true),
            withIntermediateDirectories: true
        )
        try await store.open()
        #expect(!FileManager.default.fileExists(atPath: store.root.appendingPathComponent("migrations.json").path))
        #expect(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("sessions").path))
    }
}

@Test func pathsCannotEscapeTheNuumRoot() async throws {
    try await withStore { store in
        try await store.writeTextAtomic("inside.txt", text: "safe")
        for path in ["../outside.txt", "/etc/passwd", "agents/../../outside.txt"] {
            do {
                try await store.writeTextAtomic(path, text: "nope")
                Issue.record("expected \(path) to be rejected")
            } catch let error as NuumError {
                #expect(error.code == KernelErrorCode.invalid)
                #expect(!error.message.contains("nope"))
            }
        }
        #expect(try await store.readText("inside.txt") == "safe")
        #expect(store.profilePath("a1") == "agents/a1/profile.json")
        #expect(store.transcriptPath("a1") == NuumPaths.transcriptPath("a1"))
    }
}

@Test func symlinkCannotEscapeTheDataRoot() async throws {
    try await withStore { store in
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("nuum-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: store.root.appendingPathComponent("linked"),
            withDestinationURL: outside
        )
        do {
            try await store.writeTextAtomic("linked/escape.txt", text: "nope")
            Issue.record("expected the symlink to be rejected")
        } catch let error as NuumError {
            #expect(error.code == KernelErrorCode.invalid)
            #expect(!error.message.contains("nope"))
        }
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("escape.txt").path))
    }
}
