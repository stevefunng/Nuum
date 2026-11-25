struct FileMutation: Equatable {
    var path: String
    var before: String?
    var after: String
}

func formatMutation(_ mutation: FileMutation) -> String {
    let before = diffLines(mutation.before ?? "")
    let after = diffLines(mutation.after)
    var prefix = 0
    while prefix < before.count && prefix < after.count && before[prefix] == after[prefix] {
        prefix += 1
    }
    var suffix = 0
    while suffix < before.count - prefix &&
        suffix < after.count - prefix &&
        before[before.count - suffix - 1] == after[after.count - suffix - 1] {
        suffix += 1
    }
    let removed = Array(before[prefix..<(before.count - suffix)])
    let added = Array(after[prefix..<(after.count - suffix)])
    let verb: String
    if mutation.before == nil {
        verb = "Created"
    } else if removed.isEmpty && added.isEmpty {
        verb = "Unchanged"
    } else {
        verb = "Updated"
    }
    let headline = "\(verb) \(mutation.path) (+\(added.count)/-\(removed.count))"
    if removed.isEmpty && added.isEmpty { return headline }
    var preview: [String] = []
    preview.append("@@ -\(prefix + 1),\(removed.count) +\(prefix + 1),\(added.count) @@")
    if prefix > 0 {
        preview.append(" \(before[prefix - 1])")
    }
    removed.forEach { preview.append("-\($0)") }
    added.forEach { preview.append("+\($0)") }
    if suffix > 0 {
        preview.append(" \(before[before.count - suffix])")
    }
    let output = headline + "\n" + preview.joined(separator: "\n")
    if output.count <= ToolLimits.maxDiffChars { return output }
    return String(output.prefix(ToolLimits.maxDiffChars))
        + "\n[Diff truncated; read \(mutation.path) to inspect the complete result.]"
}

private func diffLines(_ content: String) -> [String] {
    if content.isEmpty { return [] }
    return content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}
