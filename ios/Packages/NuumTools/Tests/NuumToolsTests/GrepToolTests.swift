import NuumContracts
import Testing
@testable import NuumTools

@Test func grepMapsModesCaseAndResultWindows() async throws {
    let item = fixture()
    item.files.mkdir("\(item.project)/src")
    item.files.seed("\(item.project)/src/one.ts", "Alpha\nsecond\nalpha")
    item.files.seed("\(item.project)/src/two.txt", "alpha")

    let content = try await item.run("grep", [
        "pattern": .string("alpha"),
        "path": .string(item.project),
        "glob": .string("*.ts"),
        "-i": .bool(true),
        "output_mode": .string("content"),
        "head_limit": .int(2),
        "offset": .int(1),
    ])
    #expect(content.ok)
    #expect(content.output.contains("one.ts"))
    #expect(content.output.contains("alpha"))
    #expect(content.output.split(separator: "\n", omittingEmptySubsequences: false).count == 1)

    let files = try await item.run("grep", [
        "pattern": .string("alpha"),
        "path": .string(item.project),
        "output_mode": .string("files_with_matches"),
    ])
    #expect(files.output.contains("one.ts"))
    #expect(files.output.contains("two.txt"))

    let counts = try await item.run("grep", [
        "pattern": .string("alpha"),
        "path": .string(item.project),
        "output_mode": .string("count"),
        "-i": .bool(true),
    ])
    #expect(counts.output.contains("one.ts:2"))
    #expect(counts.output.contains("two.txt:1"))

    let none = try await item.run("grep", [
        "pattern": .string("does-not-exist"),
        "path": .string(item.project),
    ])
    #expect(none.output == "No matches found.")
    let rejected = try await item.run("grep", [
        "pattern": .string("x"),
        "output_mode": .string("everything"),
    ])
    #expect(rejected.ok == false)
    #expect(rejected.output.contains("output_mode must be one of"))
    let missing = try await item.run("grep", [
        "pattern": .string("x"),
        "path": .string("\(item.project)/missing"),
    ])
    #expect(missing.ok == false)
    #expect(missing.output.contains("No such file"))
}

@Test func grepContextAndTypeStayInsideTheFileTree() async throws {
    let item = fixture()
    item.files.seed("\(item.project)/src/Main.kt", "before\nhit\nafter\n")
    item.files.seed("\(item.project)/src/Main.java", "hit")
    let output = try await item.run("grep", [
        "pattern": .string("hit"),
        "path": .string(item.project),
        "type": .string("kt"),
        "-A": .int(1),
        "-B": .int(1),
    ]).output
    #expect(output.contains("before"))
    #expect(output.contains("hit"))
    #expect(output.contains("after"))
    #expect(!output.contains(".java"))
}

@Test func grepCapsOutputWithoutCallingAnExternalProgram() async throws {
    let item = fixture()
    let line = "hit " + String(repeating: "x", count: 200)
    let body = Array(repeating: line, count: 4_000).joined(separator: "\n") + "\n"
    item.files.seed("\(item.project)/wide.txt", body)
    let output = try await item.run("grep", [
        "pattern": .string("hit"),
        "path": .string(item.project),
    ]).output
    let marker = "[rg output truncated; narrow the pattern, glob, or result range.]"
    #expect(output.contains(marker))
    #expect(output.count > ToolLimits.maxGrepOutput)
    #expect(output.count <= ToolLimits.maxGrepOutput + marker.count + 1)
    #expect(!output.contains("ripgrep failed"))
}

@Test func grepMultilineDoesNotCrossLinesUnlessAsked() async throws {
    let item = fixture()
    item.files.seed("\(item.project)/span.txt", "a\nb")
    let plain = try await item.run("grep", [
        "pattern": .string("a.b"),
        "path": .string(item.project),
    ])
    #expect(plain.output == "No matches found.")
    let spanned = try await item.run("grep", [
        "pattern": .string("a.b"),
        "path": .string(item.project),
        "multiline": .bool(true),
    ])
    #expect(spanned.ok)
    #expect(spanned.output.contains("span.txt"))
}

@Test func grepSwiftTypeMatchesSwiftSources() async throws {
    let item = fixture()
    item.files.seed("\(item.project)/App.swift", "let hit = 1")
    item.files.seed("\(item.project)/App.kt", "val hit = 1")
    let output = try await item.run("grep", [
        "pattern": .string("hit"),
        "path": .string(item.project),
        "type": .string("swift"),
    ]).output
    #expect(output.contains("App.swift"))
    #expect(!output.contains(".kt"))
}
