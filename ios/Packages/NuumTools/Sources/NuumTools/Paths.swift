import Foundation

func parentPath(_ path: String) -> String {
    let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    guard let slash = trimmed.lastIndex(of: "/") else {
        return trimmed.hasPrefix("/") ? "/" : ""
    }
    if slash == trimmed.startIndex {
        return "/"
    }
    return String(trimmed[..<slash])
}

func pathContains(_ root: String, _ target: String) -> Bool {
    if root.isEmpty || target.isEmpty { return false }
    if root == "/" { return target.hasPrefix("/") }
    let normalizedRoot = root.count > 1 && root.hasSuffix("/") ? String(root.dropLast()) : root
    let normalizedTarget = target.count > 1 && target.hasSuffix("/") ? String(target.dropLast()) : target
    return normalizedTarget == normalizedRoot || normalizedTarget.hasPrefix(normalizedRoot + "/")
}

func joinPath(_ parent: String, _ name: String) -> String {
    if name.isEmpty { return parent }
    if parent == "/" || parent.isEmpty { return "/" + name }
    let base = parent.hasSuffix("/") ? String(parent.dropLast()) : parent
    return base + "/" + name
}

func relativePath(_ root: String, _ full: String) -> String {
    if full == root { return "" }
    let prefix = root.hasSuffix("/") ? root : root + "/"
    if full.hasPrefix(prefix) {
        return String(full.dropFirst(prefix.count))
    }
    return full
}

/// Extension including the leading dot, or empty when there is none.
func fileExtension(_ path: String) -> String {
    let name = path.split(separator: "/").last.map(String.init) ?? path
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
    return name[dot...].lowercased()
}

func lexicalNormalize(_ path: String) -> String {
    let absolute = path.hasPrefix("/") ? path : "/" + path
    var parts: [String] = []
    for part in absolute.split(separator: "/", omittingEmptySubsequences: true) {
        if part == "." { continue }
        if part == ".." {
            if !parts.isEmpty { parts.removeLast() }
            continue
        }
        parts.append(String(part))
    }
    if parts.isEmpty { return "/" }
    return "/" + parts.joined(separator: "/")
}

func replaceLiteral(_ content: String, needle: String, replacement: String, all: Bool) -> String {
    if needle.isEmpty { return content }
    guard let first = content.range(of: needle) else { return content }
    if !all {
        return content.replacingCharacters(in: first, with: replacement)
    }
    var output = ""
    var cursor = content.startIndex
    while cursor <= content.endIndex {
        let rest = content[cursor...]
        guard let found = rest.range(of: needle) else {
            output.append(contentsOf: content[cursor...])
            break
        }
        output.append(contentsOf: content[cursor..<found.lowerBound])
        output.append(replacement)
        cursor = found.upperBound
        if needle.isEmpty { break }
    }
    return output
}

func occurrenceCount(_ content: String, _ needle: String) -> Int {
    if needle.isEmpty { return 0 }
    var count = 0
    var cursor = content.startIndex
    while cursor < content.endIndex {
        let rest = content[cursor...]
        guard let found = rest.range(of: needle) else { return count }
        count += 1
        cursor = found.upperBound
    }
    return count
}

/// First executable token, skipping `env` and leading `NAME=value` assignments.
/// Nothing is executed. The token is only the approval target.
func commandToken(_ command: String) -> String {
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        let tokenRegex = try? NSRegularExpression(pattern: #"(?:[^\s"']+|"[^"]*"|'[^']*')+"#),
        let assignment = try? NSRegularExpression(pattern: #"^[A-Za-z_][A-Za-z0-9_]*="#)
    else { return "" }
    let range = NSRange(trimmed.startIndex..., in: trimmed)
    for match in tokenRegex.matches(in: trimmed, range: range) {
        guard let slice = Range(match.range, in: trimmed) else { continue }
        let token = String(trimmed[slice])
        if token == "env" { continue }
        let tokenRange = NSRange(token.startIndex..., in: token)
        if assignment.firstMatch(in: token, range: tokenRange) != nil { continue }
        return commandBasename(stripOneMatchingQuote(token))
    }
    return ""
}

private func stripOneMatchingQuote(_ token: String) -> String {
    var result = token
    if let first = result.first, first == "\"" || first == "'" {
        result.removeFirst()
    }
    if let last = result.last, last == "\"" || last == "'" {
        result.removeLast()
    }
    return result
}

private func commandBasename(_ token: String) -> String {
    guard let slash = token.lastIndex(of: "/") else {
        guard let backslash = token.lastIndex(of: "\\") else { return token }
        return String(token[token.index(after: backslash)...])
    }
    let afterSlash = String(token[token.index(after: slash)...])
    guard let backslash = afterSlash.lastIndex(of: "\\") else { return afterSlash }
    return String(afterSlash[afterSlash.index(after: backslash)...])
}
