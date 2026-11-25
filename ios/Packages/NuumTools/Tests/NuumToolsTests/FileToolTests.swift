import Foundation
import NuumContracts
import Testing
@testable import NuumTools

@Test func readSupportsRangesLineNumbersAndEmptyFiles() async throws {
    let item = fixture()
    let file = "\(item.project)/lines.txt"
    item.files.seed(file, "alpha\nbeta\ngamma\ndelta")
    let ranged = try await item.run("read", [
        "path": .string(file),
        "offset": .int(2),
        "limit": .int(2),
        "include_line_numbers": .bool(true),
    ])
    #expect(ranged.output == "2|beta\n3|gamma\n\n[Showing lines 2-3 of 4. 1 line remains.]")
    let one = try await item.run("read", [
        "path": .string(file),
        "offset": .int(2),
        "limit": .int(1),
    ])
    #expect(one.output == "beta\n\n[Showing line 2 of 4. 2 lines remain.]")
    let empty = "\(item.project)/empty.txt"
    item.files.seed(empty, "")
    #expect(try await item.run("read", ["path": .string(empty)]).output == "File is empty.")
    let rejected = try await item.run("read", ["path": .string(file), "offset": .int(0)])
    #expect(rejected.ok == false)
    #expect(rejected.output.contains("offset must be an integer >= 1"))
}

@Test func readTruncatesOversizedOutput() async throws {
    let item = fixture()
    let file = "\(item.project)/large.txt"
    let body = (1...5_000).map { index in "line-\(index)-\(String(repeating: "x", count: 20))" }.joined(separator: "\n")
    item.files.seed(file, body)
    let output = try await item.run("read", ["path": .string(file), "include_line_numbers": .bool(true)]).output
    #expect(output.count < 40_000)
    #expect(output.contains(/Output truncated at line \d+ of 5000/))
    #expect(output.contains("Call read again with offset="))
}

@Test func readReturnsSupportedImagesAndRejectsBinaryText() async throws {
    let item = fixture()
    let file = "\(item.project)/pixel.png"
    let bytes = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    item.files.seedBytes(file, bytes)
    let image = try await item.run("read", ["path": .string(file)])
    #expect(image.ok)
    #expect(image.output.hasSuffix("/pixel.png"))
    #expect(image.images.map(\.mimeType) == ["image/png"])
    #expect(image.images.map(\.data) == [bytes.base64EncodedString()])
    let ranged = try await item.run("read", ["path": .string(file), "offset": .int(1)])
    #expect(ranged.ok == false)
    #expect(ranged.output.contains("offset and limit are not supported for image files"))

    let binary = "\(item.project)/blob.bin"
    item.files.seedBytes(binary, Data([0x00, 0x01]))
    let rejected = try await item.run("read", ["path": .string(binary)])
    #expect(rejected.ok == false)
    #expect(rejected.output.contains("Cannot read binary file as UTF-8 text"))
}

@Test func writeReturnsACompactDiff() async throws {
    let item = fixture()
    let file = "\(item.project)/write.txt"
    let created = try await item.run("write", ["path": .string(file), "content": .string("one\ntwo")])
    #expect(created.output.contains("Created"))
    #expect(created.output.contains("(+2/-0)"))
    #expect(created.output.contains("+one\n+two"))
    let updated = try await item.run("write", ["path": .string(file), "content": .string("one\nthree\nfour")])
    #expect(updated.output.contains("Updated"))
    #expect(updated.output.contains("(+2/-1)"))
    #expect(updated.output.contains("-two"))
    #expect(updated.output.contains("+three"))
    #expect(item.files.text(file) == "one\nthree\nfour")
}

@Test func diffTruncationKeepsTheBudget() {
    let mutation = FileMutation(
        path: "/home/project/big.txt",
        before: nil,
        after: String(repeating: "x", count: ToolLimits.maxDiffChars)
    )
    let output = formatMutation(mutation)
    #expect(output.hasSuffix("[Diff truncated; read /home/project/big.txt to inspect the complete result.]"))
    #expect(output.count > ToolLimits.maxDiffChars)
}

@Test func strReplaceIsUniqueUnlessReplaceAllIsSet() async throws {
    let item = fixture()
    let file = "\(item.project)/replace.txt"
    item.files.seed(file, "red blue red")
    let ambiguous = try await item.run("str_replace", [
        "path": .string(file),
        "old_string": .string("red"),
        "new_string": .string("green"),
    ])
    #expect(ambiguous.ok == false)
    #expect(ambiguous.output.contains("matched 2 times"))
    #expect(ambiguous.output.contains("replace_all"))
    #expect(item.files.text(file) == "red blue red")
    let replaced = try await item.run("str_replace", [
        "path": .string(file),
        "old_string": .string("red"),
        "new_string": .string("green"),
        "replace_all": .bool(true),
    ])
    #expect(replaced.output.contains("Replaced 2 occurrences"))
    #expect(item.files.text(file) == "green blue green")
    let missing = try await item.run("str_replace", [
        "path": .string(file),
        "old_string": .string("purple"),
        "new_string": .string(""),
    ])
    #expect(missing.ok == false)
    #expect(missing.output.contains("matched 0 times"))
    #expect(item.files.text(file) == "green blue green")
}

@Test func multiStrReplaceIsAtomic() async throws {
    let item = fixture()
    let file = "\(item.project)/multi.txt"
    item.files.seed(file, "alpha beta gamma")
    let applied = try await item.run("multi_str_replace", [
        "path": .string(file),
        "edits": .array([
            .object(["old_string": .string("alpha"), "new_string": .string("A")]),
            .object(["old_string": .string("gamma"), "new_string": .string("G")]),
        ]),
    ])
    #expect(applied.output.contains("Applied 2 edits"))
    #expect(item.files.text(file) == "A beta G")
    let failed = try await item.run("multi_str_replace", [
        "path": .string(file),
        "edits": .array([
            .object(["old_string": .string("A"), "new_string": .string("changed")]),
            .object(["old_string": .string("missing"), "new_string": .string("nope")]),
        ]),
    ])
    #expect(failed.ok == false)
    #expect(failed.output.contains("Edit 2:"))
    #expect(failed.output.contains("matched 0 times"))
    #expect(item.files.text(file) == "A beta G")
}

@Test func deleteRemovesADirectoryTree() async throws {
    let item = fixture()
    let directory = "\(item.project)/obsolete"
    item.files.mkdir(directory)
    item.files.seed("\(directory)/old.txt", "old")
    let deleted = try await item.run("delete", ["path": .string(directory)])
    #expect(deleted.output.contains("Deleted directory"))
    #expect(item.files.text("\(directory)/old.txt") == nil)
    #expect(item.files.exists(directory) == false)
}

@Test func lsRendersDirectoriesBeforeFiles() async throws {
    let item = fixture()
    item.files.mkdir("\(item.project)/src/nested")
    item.files.seed("\(item.project)/README.md", "readme")
    item.files.seed("\(item.project)/src/index.ts", "code")
    let output = try await item.run("ls", ["path": .string(item.project)]).output
    #expect(output.contains("project/"))
    #expect(output.contains("├── src/"))
    #expect(output.contains("│   ├── nested/"))
    #expect(output.contains("└── README.md"))
}

@Test func globSortsNewestMatchesFirstAndCapsTheList() async throws {
    let item = fixture()
    item.files.mkdir("\(item.project)/src")
    let oldFile = "\(item.project)/old.ts"
    let newFile = "\(item.project)/src/new.ts"
    item.files.seed(oldFile, "old", modifiedAt: 1_000)
    item.files.seed(newFile, "new", modifiedAt: 2_000)
    item.files.seed("\(item.project)/README.md", "readme", modifiedAt: 3_000)
    let output = try await item.run("glob", [
        "glob_pattern": .string("*.ts"),
        "target_directory": .string(item.project),
    ]).output
    let newIndex = output.range(of: newFile)?.lowerBound
    let oldIndex = output.range(of: oldFile)?.lowerBound
    #expect(newIndex != nil && oldIndex != nil && newIndex! < oldIndex!)
    #expect(!output.contains("README"))

    for index in 0..<(ToolLimits.maxGlobResults + 1) {
        item.files.seed("\(item.project)/extra/f\(index).txt", "x", modifiedAt: Int64(index))
    }
    let capped = try await item.run("glob", [
        "glob_pattern": .string("*.txt"),
        "target_directory": .string("\(item.project)/extra"),
    ]).output
    #expect(capped.contains("[1 more matches omitted.]"))
}

@Test func unknownToolAndUnboundSessionFailClosed() async throws {
    let item = fixture()
    do {
        _ = try await item.run("missing")
        Issue.record("expected an unknown-tool failure")
    } catch let error as NuumError {
        #expect(error.code == KernelErrorCode.tool)
        #expect(error.message == "Unknown tool: missing")
    }
    item.backend.release(runId: runID)
    do {
        _ = try await item.run("read", ["path": .string("\(item.project)/lines.txt")])
        Issue.record("expected an unbound session")
    } catch let error as NuumError {
        #expect(error.code == KernelErrorCode.invalid)
        #expect(error.message == "No tool session is bound for run \(runID).")
    }
}
