import Foundation

enum InlineSpan: Equatable, Sendable {
    case text(String)
    case code(String)
    case link(text: String, url: String)
}

enum MarkdownBlock: Equatable, Sendable {
    case paragraph([InlineSpan])
    case bullets([[InlineSpan]])
    case numbers([[InlineSpan]])
    case code(String)
}

/// Paragraphs, lists, fenced code, inline code, and links. No mermaid or KaTeX.
func parseMarkdown(_ source: String) -> [MarkdownBlock] {
    let lines = source.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var blocks: [MarkdownBlock] = []
    var index = 0
    while index < lines.count {
        let line = lines[index]
        if line.hasPrefix("```") {
            index += 1
            var body: [String] = []
            while index < lines.count, !lines[index].hasPrefix("```") {
                body.append(lines[index])
                index += 1
            }
            if index < lines.count { index += 1 }
            blocks.append(.code(body.joined(separator: "\n")))
            continue
        }
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
            continue
        }
        if let marker = listMarker(line) {
            var items: [[InlineSpan]] = []
            let ordered = marker.ordered
            while index < lines.count, let next = listMarker(lines[index]), next.ordered == ordered {
                items.append(parseInline(next.body))
                index += 1
            }
            blocks.append(ordered ? .numbers(items) : .bullets(items))
            continue
        }
        var paragraph: [String] = []
        while index < lines.count {
            let current = lines[index]
            if current.trimmingCharacters(in: .whitespaces).isEmpty || current.hasPrefix("```") || listMarker(current) != nil {
                break
            }
            paragraph.append(current)
            index += 1
        }
        let joined = paragraph.joined(separator: " ")
        if !joined.isEmpty { blocks.append(.paragraph(parseInline(joined))) }
    }
    return blocks
}

private struct ListMarker {
    var ordered: Bool
    var body: String
}

private func listMarker(_ line: String) -> ListMarker? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("- ") { return ListMarker(ordered: false, body: String(trimmed.dropFirst(2))) }
    if trimmed.hasPrefix("* ") { return ListMarker(ordered: false, body: String(trimmed.dropFirst(2))) }
    var digits = ""
    var rest = trimmed[...]
    while let first = rest.first, first.isNumber {
        digits.append(first)
        rest = rest.dropFirst()
    }
    if !digits.isEmpty, rest.hasPrefix(". ") {
        return ListMarker(ordered: true, body: String(rest.dropFirst(2)))
    }
    return nil
}

func parseInline(_ source: String) -> [InlineSpan] {
    var spans: [InlineSpan] = []
    var buffer = ""
    var index = source.startIndex
    func flush() {
        if !buffer.isEmpty {
            spans.append(.text(buffer))
            buffer = ""
        }
    }
    while index < source.endIndex {
        let character = source[index]
        if character == "`" {
            let next = source.index(after: index)
            if let end = source[next...].firstIndex(of: "`"), end > next {
                flush()
                spans.append(.code(String(source[next..<end])))
                index = source.index(after: end)
                continue
            }
        }
        if character == "[" {
            if let link = parseLink(source, from: index) {
                flush()
                spans.append(.link(text: link.text, url: link.url))
                index = link.next
                continue
            }
        }
        buffer.append(character)
        index = source.index(after: index)
    }
    flush()
    return spans
}

private func parseLink(_ source: String, from start: String.Index) -> (text: String, url: String, next: String.Index)? {
    guard let close = source[start...].firstIndex(of: "]") else { return nil }
    let textStart = source.index(after: start)
    guard textStart <= close else { return nil }
    let after = source.index(after: close)
    guard after < source.endIndex, source[after] == "(" else { return nil }
    let urlStart = source.index(after: after)
    guard let urlEnd = source[urlStart...].firstIndex(of: ")") else { return nil }
    let text = String(source[textStart..<close])
    let url = String(source[urlStart..<urlEnd])
    guard !text.isEmpty, !url.isEmpty else { return nil }
    return (text, url, source.index(after: urlEnd))
}

func isOpenableURL(_ url: String) -> Bool {
    guard let components = URL(string: url), let scheme = components.scheme?.lowercased() else { return false }
    return scheme == "https" || scheme == "http"
}
