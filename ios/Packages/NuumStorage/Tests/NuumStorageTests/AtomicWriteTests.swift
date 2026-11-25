import Foundation
import NuumStorage
import Testing

@Test func failureBeforeReplaceKeepsThePreviousFile() async throws {
    let gate = CommitGate()
    try await withStore(beforeCommit: gate.checkpoint) { store in
        let relative = "agents/a1/profile.json"
        let original = #"{"id":"a1","name":"Old","description":"","createdAt":1}"#
        let replacement = #"{"id":"a1","name":"New","description":"","createdAt":1}"#
        try await store.writeTextAtomic(relative, text: original)
        let listed = await store.agentList()
        #expect(listed.map(\.name) == ["Old"])

        gate.arm()
        do {
            try await store.writeTextAtomic(relative, text: replacement)
            Issue.record("expected the replace to fail")
        } catch {
            #expect(String(describing: error).contains("before replace"))
        }

        #expect(try await store.readText(relative) == original)
        let bytes = try #require(await store.readBytes(relative))
        #expect(String(decoding: bytes, as: UTF8.self) == original)
        #expect(await store.agentList().map(\.name) == ["Old"])
        #expect(!descendantNames(under: store.root).contains { $0.contains(".tmp") })
    }
}
