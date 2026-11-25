import Foundation
import NuumContracts

struct GlobTool: Tool {
    let definition = ToolDefinition(
        name: "glob",
        description: "Find files recursively with a glob pattern and return newest matches first.",
        inputSchema: JSONSchema.object(
            [
                "glob_pattern": JSONSchema.string(),
                "target_directory": JSONSchema.string(),
            ],
            required: ["glob_pattern"]
        ),
        mutating: false,
        action: .listDirectory
    )

    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult {
        let pattern = try stringField(input, "glob_pattern") ?? ""
        let target = try stringField(input, "target_directory", optional: true) ?? "."
        let root = try sandbox.requireAllowed(.listDirectory, target, withPeriod: true)
        var matches: [FoundFile] = []
        try collectFiles(sandbox, root: root, action: .listDirectory) { found in
            if matchesGlob(found.relative, pattern: pattern) {
                matches.append(found)
            }
        }
        if matches.isEmpty { return ToolExecutionResult(ok: true, output: "No files matched.") }
        matches.sort { lhs, rhs in
            if lhs.modifiedMillis != rhs.modifiedMillis { return lhs.modifiedMillis > rhs.modifiedMillis }
            return lhs.path < rhs.path
        }
        var shown = matches.prefix(ToolLimits.maxGlobResults).map(\.path)
        if matches.count > shown.count {
            shown.append("[\(matches.count - shown.count) more matches omitted.]")
        }
        return ToolExecutionResult(ok: true, output: shown.joined(separator: "\n"))
    }
}

struct GrepTool: Tool {
    let definition = ToolDefinition(
        name: "grep",
        description: "Search file contents recursively. Output is capped the same way as ripgrep; no external search program is launched.",
        inputSchema: JSONSchema.object(
            [
                "pattern": JSONSchema.string(),
                "path": JSONSchema.string(),
                "glob": JSONSchema.string(),
                "type": JSONSchema.string(),
                "output_mode": JSONSchema.enumeration(["content", "files_with_matches", "count"]),
                "-i": JSONSchema.boolean(),
                "-A": JSONSchema.integer(minimum: 0),
                "-B": JSONSchema.integer(minimum: 0),
                "-C": JSONSchema.integer(minimum: 0),
                "head_limit": JSONSchema.integer(minimum: 1),
                "offset": JSONSchema.integer(minimum: 0),
                "multiline": JSONSchema.boolean(),
            ],
            required: ["pattern"]
        ),
        mutating: false,
        action: .readFile
    )

    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult {
        let pattern = try stringField(input, "pattern") ?? ""
        let requested = try stringField(input, "path", optional: true) ?? "."
        let root = try sandbox.requireAllowed(.readFile, requested, withPeriod: true)
        let mode = try enumField(
            input,
            "output_mode",
            values: ["content", "files_with_matches", "count"],
            fallback: "content"
        )
        let ignoreCase = try booleanField(input, "-i") ?? false
        let multiline = try booleanField(input, "multiline") ?? false
        let glob = try stringField(input, "glob", optional: true)
        let type = try stringField(input, "type", optional: true)
        let typeExtensions = try type.map { try extensionsForType($0) }
        var beforeLines = try integerField(input, "-B", min: 0) ?? 0
        var afterLines = try integerField(input, "-A", min: 0) ?? 0
        if let context = try integerField(input, "-C", min: 0) {
            beforeLines = context
            afterLines = context
        }
        let regex = try compilePattern(pattern, ignoreCase: ignoreCase, multiline: multiline)
        let formatted: [String]
        switch mode {
        case "files_with_matches":
            formatted = try filesWithMatches(
                sandbox, root: root, regex: regex, multiline: multiline, glob: glob, typeExtensions: typeExtensions
            )
        case "count":
            formatted = try counts(
                sandbox, root: root, regex: regex, multiline: multiline, glob: glob, typeExtensions: typeExtensions
            )
        default:
            formatted = try contentLines(
                sandbox,
                root: root,
                regex: regex,
                multiline: multiline,
                glob: glob,
                typeExtensions: typeExtensions,
                beforeLines: beforeLines,
                afterLines: afterLines
            )
        }
        if formatted.isEmpty { return ToolExecutionResult(ok: true, output: "No matches found.") }
        return ToolExecutionResult(ok: true, output: try pageGrep(formatted, input: input))
    }
}

private struct FoundFile {
    var path: String
    var relative: String
    var modifiedMillis: Int64
}

private func collectFiles(
    _ sandbox: RunSandbox,
    root: String,
    action: LocalToolAction,
    visit: (FoundFile) -> Void
) throws {
    if !sandbox.exists(root) {
        throw NuumError(code: KernelErrorCode.tool, message: "No such file: \(root)")
    }
    if !sandbox.isDirectory(root) {
        guard sandbox.permits(action, resolved: root) else { return }
        visit(FoundFile(
            path: root,
            relative: root.split(separator: "/").last.map(String.init) ?? root,
            modifiedMillis: sandbox.lastModifiedMillis(root)
        ))
        return
    }
    func walk(_ directory: String) throws {
        let entries: [ToolDirEntry]
        do {
            entries = try sandbox.list(directory)
        } catch is MissingPath {
            return
        }
        for entry in entries {
            if entry.isSymlink { continue }
            let child = joinPath(directory, entry.name)
            if !sandbox.permits(action, resolved: child) { continue }
            if entry.isDirectory {
                try walk(child)
            } else {
                visit(FoundFile(
                    path: child,
                    relative: relativePath(root, child),
                    modifiedMillis: sandbox.lastModifiedMillis(child)
                ))
            }
        }
    }
    try walk(root)
}

private func filesWithMatches(
    _ sandbox: RunSandbox,
    root: String,
    regex: NSRegularExpression,
    multiline: Bool,
    glob: String?,
    typeExtensions: Set<String>?
) throws -> [String] {
    var paths: [String] = []
    try collectFiles(sandbox, root: root, action: .readFile) { found in
        if acceptsFile(found.relative, glob: glob, typeExtensions: typeExtensions),
           let text = readSearchText(sandbox, path: found.path),
           hasMatch(text, regex: regex, multiline: multiline) {
            paths.append(found.path)
        }
    }
    paths.sort()
    return paths
}

private func counts(
    _ sandbox: RunSandbox,
    root: String,
    regex: NSRegularExpression,
    multiline: Bool,
    glob: String?,
    typeExtensions: Set<String>?
) throws -> [String] {
    var lines: [String] = []
    try collectFiles(sandbox, root: root, action: .readFile) { found in
        if acceptsFile(found.relative, glob: glob, typeExtensions: typeExtensions),
           let text = readSearchText(sandbox, path: found.path) {
            let count = matchLineNumbers(text, regex: regex, multiline: multiline).count
            if count > 0 {
                lines.append("\(found.path):\(count)")
            }
        }
    }
    lines.sort()
    return lines
}

private func contentLines(
    _ sandbox: RunSandbox,
    root: String,
    regex: NSRegularExpression,
    multiline: Bool,
    glob: String?,
    typeExtensions: Set<String>?,
    beforeLines: Int,
    afterLines: Int
) throws -> [String] {
    var files: [FoundFile] = []
    try collectFiles(sandbox, root: root, action: .readFile) { found in
        if acceptsFile(found.relative, glob: glob, typeExtensions: typeExtensions) {
            files.append(found)
        }
    }
    files.sort { $0.path < $1.path }
    var output: [String] = []
    for found in files {
        guard let text = readSearchText(sandbox, path: found.path) else { continue }
        let fileLines = searchLines(text)
        let matches = matchLineNumbers(text, regex: regex, multiline: multiline)
        if matches.isEmpty { continue }
        let selected = contextIndexes(matches, before: beforeLines, after: afterLines, lineCount: fileLines.count)
        var previous: Int?
        for index in selected {
            if let previous, index > previous + 1, beforeLines > 0 || afterLines > 0 {
                output.append("--")
            }
            let separator = matches.contains(index) ? ":" : "-"
            output.append("\(found.path)\(separator)\(index + 1)\(separator)\(fileLines[index])")
            previous = index
        }
    }
    return output
}

private func pageGrep(_ lines: [String], input: [String: JSONValue]) throws -> String {
    let joined = lines.joined(separator: "\n")
    let truncated = joined.count > ToolLimits.maxGrepOutput
    let capped = truncated ? String(joined.prefix(ToolLimits.maxGrepOutput)) : joined
    let withNote = truncated
        ? capped + "\n[rg output truncated; narrow the pattern, glob, or result range.]"
        : capped
    let outputLines = trimEnd(withNote).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let offset = try integerField(input, "offset", min: 0) ?? 0
    let headLimit = try integerField(input, "head_limit", min: 1)
    let end: Int
    if let headLimit {
        let sum = offset.addingReportingOverflow(headLimit)
        end = sum.overflow ? outputLines.count : min(sum.partialValue, outputLines.count)
    } else {
        end = outputLines.count
    }
    if offset >= outputLines.count || offset >= end {
        return "No matches in the requested result range."
    }
    return outputLines[offset..<end].joined(separator: "\n")
}

private func acceptsFile(_ relative: String, glob: String?, typeExtensions: Set<String>?) -> Bool {
    if let glob, !matchesRgGlob(relative, pattern: glob) { return false }
    if let typeExtensions, !typeExtensions.contains(String(fileExtension(relative).dropFirst())) { return false }
    return true
}

private func readSearchText(_ sandbox: RunSandbox, path: String) -> String? {
    guard let bytes = try? sandbox.readBytes(path) else { return nil }
    if bytes.contains(0) { return nil }
    return String(decoding: bytes, as: UTF8.self)
}

private func hasMatch(_ text: String, regex: NSRegularExpression, multiline: Bool) -> Bool {
    if multiline { return containsMatch(regex, in: text) }
    return searchLines(text).contains { containsMatch(regex, in: $0) }
}

private func matchLineNumbers(_ text: String, regex: NSRegularExpression, multiline: Bool) -> [Int] {
    if !multiline {
        return searchLines(text).enumerated().compactMap { index, line in
            containsMatch(regex, in: line) ? index : nil
        }
    }
    var found: [Int] = []
    let range = NSRange(text.startIndex..., in: text)
    for match in regex.matches(in: text, range: range) {
        guard let matchRange = Range(match.range, in: text) else { continue }
        let line = text[..<matchRange.lowerBound].reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        if found.last != line { found.append(line) }
    }
    return found
}

private func searchLines(_ text: String) -> [String] {
    if text.isEmpty { return [] }
    let parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if text.hasSuffix("\n"), parts.last?.isEmpty == true {
        return Array(parts.dropLast())
    }
    return parts
}

private func contextIndexes(_ matches: [Int], before: Int, after: Int, lineCount: Int) -> [Int] {
    var selected = Set<Int>()
    for match in matches {
        let start = max(0, match - before)
        let end = min(lineCount - 1, match + after)
        if start <= end {
            for index in start...end { selected.insert(index) }
        }
    }
    return selected.sorted()
}

private func compilePattern(_ pattern: String, ignoreCase: Bool, multiline: Bool) throws -> NSRegularExpression {
    var options: NSRegularExpression.Options = []
    if ignoreCase { options.insert(.caseInsensitive) }
    if multiline { options.insert(.dotMatchesLineSeparators) }
    do {
        return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
        throw NuumError(code: KernelErrorCode.tool, message: "Invalid regular expression: \(error.localizedDescription)")
    }
}

private func extensionsForType(_ type: String) throws -> Set<String> {
    guard let extensions = fileTypes[type] else {
        throw NuumError(code: KernelErrorCode.tool, message: "Unrecognized file type: \(type).")
    }
    return extensions
}

private func containsMatch(_ regex: NSRegularExpression, in text: String) -> Bool {
    let range = NSRange(text.startIndex..., in: text)
    return regex.firstMatch(in: text, range: range) != nil
}

private func trimEnd(_ text: String) -> String {
    var end = text.endIndex
    while end > text.startIndex {
        let previous = text.index(before: end)
        if !text[previous].isWhitespace { break }
        end = previous
    }
    return String(text[..<end])
}

/// Android's in-process type table, plus `swift` for this client.
private let fileTypes: [String: Set<String>] = [
    "kt": ["kt", "kts"],
    "kotlin": ["kt", "kts"],
    "java": ["java"],
    "js": ["js", "mjs", "cjs", "jsx"],
    "ts": ["ts", "tsx"],
    "py": ["py"],
    "swift": ["swift"],
    "md": ["md", "markdown"],
    "json": ["json"],
    "xml": ["xml"],
    "html": ["html", "htm"],
    "css": ["css"],
    "txt": ["txt"],
    "yaml": ["yaml", "yml"],
    "sh": ["sh", "bash"],
]
