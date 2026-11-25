import Foundation
import NuumContracts
import NuumStorage
import Testing

@Test func truncatedLastLineIsDroppedAndEarlierLinesStay() async throws {
    try await withStore { store in
        let relative = NuumPaths.transcriptPath("a1")
        let kept = #"{"id":"u1","createdAt":1}"#
        let alsoKept = #"{"id":"u2","createdAt":2}"#
        try await store.writeTextAtomic(relative, text: "\(kept)\n\(alsoKept)\n")
        let seeded = try String(contentsOf: fileURL(store.root, relative), encoding: .utf8)
        #expect(seeded.contains("u1"))
        try appendRaw(root: store.root, relative: relative, text: #"{"id":"u3","createdAt":3,"te"#)

        let lines = try await store.readJsonLines(relative)
        #expect(lines == [kept, alsoKept])
        let raw = try #require(await store.readText(relative))
        #expect(!raw.contains("u3"))
        #expect(raw.hasSuffix("\n"))

        try await store.appendLine(relative, line: #"{"id":"u4","createdAt":4}"#)
        let after = try #require(await store.readText(relative))
        #expect(
            after.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                == [kept, alsoKept, #"{"id":"u4","createdAt":4}"#]
        )
        #expect(!after.contains("u3"))
        #expect(after.hasSuffix("\n"))
    }
}

@Test func aCompleteCorruptMiddleLineIsKept() async throws {
    try await withStore { store in
        let relative = "notes.jsonl"
        try await store.writeTextAtomic(relative, text: "one\n{not-json\nthree\n")
        #expect(try await store.readJsonLines(relative) == ["one", "{not-json", "three"])
    }
}

@Test func aFileThatIsOnlyAPartialLineBecomesEmpty() async throws {
    try await withStore { store in
        let relative = "notes.jsonl"
        try await store.writeTextAtomic(relative, text: #"{"id":"torn""#)
        #expect(try await store.readJsonLines(relative).isEmpty)
        #expect(try await store.readText(relative) == "")
        try await store.appendLine(relative, line: #"{"id":"fresh","createdAt":1}"#)
        #expect(try await store.readJsonLines(relative) == [#"{"id":"fresh","createdAt":1}"#])
    }
}

@Test func readTailStartsOnALineBoundary() async throws {
    try await withStore { store in
        let relative = "notes.jsonl"
        try await store.writeTextAtomic(relative, text: "aaaa\nbbbb\ncccc\n")
        #expect(try await store.readTail(relative, maxBytes: 10) == "bbbb\ncccc\n")
        #expect(try await store.readTail(relative, maxBytes: 100) == "aaaa\nbbbb\ncccc\n")
        #expect(try await store.readTail(relative, maxBytes: 0) == "")
    }
}

@Test func embeddedNewlinesAreRejected() async throws {
    try await withStore { store in
        do {
            try await store.appendLine("notes.jsonl", line: "one\ntwo")
            Issue.record("expected a newline to be rejected")
        } catch let error as NuumError {
            #expect(error.code == KernelErrorCode.invalid)
            #expect(!error.message.contains("one"))
            #expect(!(try await store.exists("notes.jsonl")))
        }
    }
}
