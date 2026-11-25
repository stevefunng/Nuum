import Foundation

func matchesGlob(_ relativePath: String, pattern: String) -> Bool {
    let effective = pattern.hasPrefix("**/") ? pattern : "**/" + pattern
    return globRegex(effective).map { fullMatch($0, relativePath) } ?? false
}

/// A pattern with no slash matches the file name in any directory.
func matchesRgGlob(_ relativePath: String, pattern: String) -> Bool {
    let effective = pattern.contains("/") ? pattern : "**/" + pattern
    return globRegex(effective).map { fullMatch($0, relativePath) } ?? false
}

private func globRegex(_ pattern: String) -> NSRegularExpression? {
    var body = "^"
    var index = pattern.startIndex
    while index < pattern.endIndex {
        if pattern[index...].hasPrefix("**/") {
            body.append("(?:.*/)?")
            index = pattern.index(index, offsetBy: 3)
            continue
        }
        if pattern[index...].hasPrefix("**") {
            body.append(".*")
            index = pattern.index(index, offsetBy: 2)
            continue
        }
        let character = pattern[index]
        switch character {
        case "*":
            body.append("[^/]*")
        case "?":
            body.append("[^/]")
        default:
            if globLiteralEscape.contains(character) {
                body.append("\\")
            }
            body.append(character)
        }
        index = pattern.index(after: index)
    }
    body.append("$")
    return try? NSRegularExpression(pattern: body)
}

private let globLiteralEscape = Set("\\.[]{}()+-^$|")

private func fullMatch(_ regex: NSRegularExpression, _ text: String) -> Bool {
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range) else { return false }
    return match.range.location == 0 && match.range.length == range.length
}
