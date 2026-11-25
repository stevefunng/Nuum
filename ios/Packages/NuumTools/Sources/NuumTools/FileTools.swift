import Foundation
import NuumContracts

private let imageMIMETypes: [String: String] = [
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".gif": "image/gif",
    ".webp": "image/webp",
]

struct ReadTool: Tool {
    let definition = ToolDefinition(
        name: "read",
        description: "Read a UTF-8 file, optionally by one-based line range and with line numbers.",
        inputSchema: JSONSchema.object(
            [
                "path": JSONSchema.string(),
                "offset": JSONSchema.integer(minimum: 1),
                "limit": JSONSchema.integer(minimum: 1),
                "include_line_numbers": JSONSchema.boolean(),
            ],
            required: ["path"]
        ),
        mutating: false,
        action: .readFile
    )

    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult {
        let filePath = try stringField(input, "path") ?? ""
        if let mimeType = imageMIMETypes[fileExtension(filePath)] {
            if present(input, "offset") != nil || present(input, "limit") != nil {
                throw NuumError(
                    code: KernelErrorCode.invalid,
                    message: "offset and limit are not supported for image files."
                )
            }
            let image = try sandbox.readBinary(filePath)
            return ToolExecutionResult(
                ok: true,
                output: "Read image file: \(image.path)",
                images: [ModelImage(mimeType: mimeType, data: image.data.base64EncodedString())]
            )
        }
        let offset = try integerField(input, "offset", min: 1) ?? 1
        let limit = try integerField(input, "limit", min: 1)
        let includeLineNumbers = try booleanField(input, "include_line_numbers") ?? false
        let content = try sandbox.readText(filePath)
        return ToolExecutionResult(
            ok: true,
            output: try renderRead(
                filePath: filePath,
                content: content,
                offset: offset,
                limit: limit,
                includeLineNumbers: includeLineNumbers
            )
        )
    }
}

func renderRead(
    filePath: String,
    content: String,
    offset: Int,
    limit: Int?,
    includeLineNumbers: Bool
) throws -> String {
    if content.isEmpty { return "File is empty." }
    if content.contains("\u{0000}") {
        throw NuumError(code: KernelErrorCode.tool, message: "Cannot read binary file as UTF-8 text: \(filePath)")
    }
    let all = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if offset > all.count {
        return "[Offset \(offset) is beyond the end of \(filePath) (\(all.count) lines).]"
    }
    let start = offset - 1
    let requestedEnd: Int
    if let limit {
        let sum = start.addingReportingOverflow(limit)
        requestedEnd = sum.overflow ? all.count : min(all.count, sum.partialValue)
    } else {
        requestedEnd = all.count
    }
    let selected = all[start..<requestedEnd]
    let rendered = selected.enumerated().map { index, line in
        includeLineNumbers ? "\(offset + index)|\(line)" : line
    }
    var kept: [String] = []
    var characters = 0
    for line in rendered {
        let next = line.count + (kept.isEmpty ? 0 : 1)
        if characters + next > ToolLimits.maxReadChars { break }
        kept.append(line)
        characters += next
    }
    if kept.isEmpty {
        let slice = String(rendered[0].prefix(ToolLimits.maxReadChars))
        return "\(slice)\n\n[Line \(offset) was truncated because it alone exceeds the read budget. Use grep to narrow the content.]"
    }
    let actualEnd = offset + kept.count - 1
    if kept.count < rendered.count {
        return kept.joined(separator: "\n")
            + "\n\n[Output truncated at line \(actualEnd) of \(all.count). Call read again with offset=\(actualEnd + 1).]"
    }
    if offset != 1 || requestedEnd != all.count {
        let remaining = all.count - requestedEnd
        let shown = offset == requestedEnd ? "line \(offset)" : "lines \(offset)-\(requestedEnd)"
        let remainder = remaining == 1 ? "1 line remains" : "\(remaining) lines remain"
        return kept.joined(separator: "\n") + "\n\n[Showing \(shown) of \(all.count). \(remainder).]"
    }
    return kept.joined(separator: "\n")
}

struct WriteTool: Tool {
    let definition = ToolDefinition(
        name: "write",
        description: "Create or overwrite a UTF-8 file and return a compact diff.",
        inputSchema: JSONSchema.object(
            [
                "path": JSONSchema.string(),
                "content": JSONSchema.string(),
            ],
            required: ["path", "content"]
        ),
        mutating: true,
        action: .writeFile
    )

    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult {
        let mutation = try sandbox.writeText(
            try stringField(input, "path") ?? "",
            try stringField(input, "content", allowEmpty: true) ?? ""
        )
        return ToolExecutionResult(ok: true, output: formatMutation(mutation))
    }
}

struct StrReplaceTool: Tool {
    let definition = ToolDefinition(
        name: "str_replace",
        description: "Replace exact text in a file; the match must be unique unless replace_all is true.",
        inputSchema: JSONSchema.object(
            [
                "path": JSONSchema.string(),
                "old_string": JSONSchema.string(),
                "new_string": JSONSchema.string(),
                "replace_all": JSONSchema.boolean(),
            ],
            required: ["path", "old_string", "new_string"]
        ),
        mutating: true,
        action: .writeFile
    )

    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult {
        let filePath = try stringField(input, "path") ?? ""
        let oldString = try stringField(input, "old_string") ?? ""
        let newString = try stringField(input, "new_string", allowEmpty: true) ?? ""
        let replaceAll = try booleanField(input, "replace_all") ?? false
        var replaced = 0
        let mutation = try sandbox.mutateText(filePath) { current in
            replaced = occurrenceCount(current, oldString)
            try assertReplaceable(filePath, matches: replaced, replaceAll: replaceAll)
            return replaceLiteral(current, needle: oldString, replacement: newString, all: replaceAll)
        }
        let noun = replaced == 1 ? "occurrence" : "occurrences"
        return ToolExecutionResult(
            ok: true,
            output: "Replaced \(replaced) \(noun).\n\(formatMutation(mutation))"
        )
    }
}

struct MultiStrReplaceTool: Tool {
    let definition = ToolDefinition(
        name: "multi_str_replace",
        description: "Apply several exact replacements to one file in a single atomic write.",
        inputSchema: JSONSchema.object(
            [
                "path": JSONSchema.string(),
                "edits": JSONSchema.array(
                    items: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "old_string": JSONSchema.string(),
                            "new_string": JSONSchema.string(),
                            "replace_all": JSONSchema.boolean(),
                        ]),
                        "required": .array([.string("old_string"), .string("new_string")]),
                    ]),
                    minItems: 1
                ),
            ],
            required: ["path", "edits"]
        ),
        mutating: true,
        action: .writeFile
    )

    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult {
        let filePath = try stringField(input, "path") ?? ""
        let edits = try parseEdits(present(input, "edits"))
        let mutation = try sandbox.mutateText(filePath) { original in
            var next = original
            for (index, edit) in edits.enumerated() {
                let matches = occurrenceCount(next, edit.oldString)
                do {
                    try assertReplaceable(filePath, matches: matches, replaceAll: edit.replaceAll)
                } catch let error as NuumError {
                    throw NuumError(code: error.code, message: "Edit \(index + 1): \(error.message)")
                }
                next = replaceLiteral(next, needle: edit.oldString, replacement: edit.newString, all: edit.replaceAll)
            }
            return next
        }
        return ToolExecutionResult(ok: true, output: "Applied \(edits.count) edits.\n\(formatMutation(mutation))")
    }
}

struct DeleteTool: Tool {
    let definition = ToolDefinition(
        name: "delete",
        description: "Delete a file or directory tree.",
        inputSchema: JSONSchema.object(
            ["path": JSONSchema.string()],
            required: ["path"]
        ),
        mutating: true,
        action: .writeFile
    )

    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult {
        let result = try sandbox.deletePath(try stringField(input, "path") ?? "")
        return ToolExecutionResult(ok: true, output: "Deleted \(result.kind): \(result.path)")
    }
}

struct LsTool: Tool {
    let definition = ToolDefinition(
        name: "ls",
        description: "Render a directory tree within a bounded output budget.",
        inputSchema: JSONSchema.object(["path": JSONSchema.string()]),
        mutating: false,
        action: .listDirectory
    )

    func execute(_ input: [String: JSONValue], sandbox: RunSandbox) throws -> ToolExecutionResult {
        let requested = try stringField(input, "path", optional: true) ?? "."
        let root = try sandbox.requireAllowed(.listDirectory, requested, withPeriod: true)
        let label = root.split(separator: "/").last.map(String.init) ?? root
        var output = ["\(label)/"]
        var used = output[0].count
        var truncated = false

        func visit(_ directory: String, prefix: String) throws {
            if truncated { return }
            let entries = try sandbox.list(directory)
                .filter { sandbox.permits(.listDirectory, resolved: joinPath(directory, $0.name)) }
                .sorted(by: directoryOrder)
            for (index, entry) in entries.enumerated() {
                let child = joinPath(directory, entry.name)
                let last = index == entries.count - 1
                let suffix = entry.isDirectory ? "/" : (entry.isSymlink ? "@" : "")
                let connector = last ? "└── " : "├── "
                let line = "\(prefix)\(connector)\(entry.name)\(suffix)"
                if used + line.count + 1 > ToolLimits.maxTreeChars {
                    truncated = true
                    return
                }
                output.append(line)
                used += line.count + 1
                if entry.isDirectory {
                    let nextPrefix = prefix + (last ? "    " : "│   ")
                    try visit(child, prefix: nextPrefix)
                }
            }
        }

        try visit(root, prefix: "")
        if truncated {
            output.append("[Directory tree truncated at \(ToolLimits.maxTreeChars) characters.]")
        }
        return ToolExecutionResult(ok: true, output: output.joined(separator: "\n"))
    }
}

private func directoryOrder(_ lhs: ToolDirEntry, _ rhs: ToolDirEntry) -> Bool {
    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
    return lhs.name < rhs.name
}

private func assertReplaceable(_ filePath: String, matches: Int, replaceAll: Bool) throws {
    if matches == 0 {
        throw NuumError(
            code: KernelErrorCode.tool,
            message: "old_string matched 0 times in \(filePath). Read the file again and copy the exact text before retrying."
        )
    }
    if !replaceAll && matches != 1 {
        throw NuumError(
            code: KernelErrorCode.tool,
            message: "old_string matched \(matches) times in \(filePath). Include more surrounding context to make it unique, or set replace_all=true."
        )
    }
}

private struct TextEdit {
    var oldString: String
    var newString: String
    var replaceAll: Bool
}

private func parseEdits(_ raw: JSONValue?) throws -> [TextEdit] {
    guard let raw, case .array(let items) = raw, !items.isEmpty else {
        throw NuumError(code: KernelErrorCode.invalid, message: "edits must be a non-empty array.")
    }
    return try items.enumerated().map { index, value in
        guard case .object(let edit) = value else {
            throw NuumError(code: KernelErrorCode.invalid, message: "edits[\(index)] must be an object.")
        }
        return TextEdit(
            oldString: try stringField(edit, "old_string") ?? "",
            newString: try stringField(edit, "new_string", allowEmpty: true) ?? "",
            replaceAll: try booleanField(edit, "replace_all") ?? false
        )
    }
}
