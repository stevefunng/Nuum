import Foundation
import NuumContracts

enum MemoryTier: Sendable, Equatable {
    case profile
    case log
    case note
}

struct MemoryFact: Sendable, Equatable {
    var fact: String
    var tier: MemoryTier
    var day: String?
}

struct ExtractedMemory: Sendable {
    var writes: [(String, MemoryTier)]
    var removals: [String]
}

struct MemoryWrite: Sendable, Equatable {
    var written: Bool
}

struct MemoryForget: Sendable, Equatable {
    var removed: Int
}

/// Markdown memory. `profile.md` is standing facts. `log/YYYY-MM.md` is dated.
/// The files are the only source. There is no memory transcript event.
struct MemoryStore: Sendable {
    private let store: any AgentStore
    private let memoryDir: String
    private let clock: any Clock
    private var profilePath: String { "\(memoryDir)/profile.md" }

    init(store: any AgentStore, memoryDir: String, clock: any Clock) {
        self.store = store
        self.memoryDir = memoryDir
        self.clock = clock
    }

    func write(fact: String, tier: MemoryTier, nowMillis: Int64? = nil) async throws -> MemoryWrite {
        let text = normalizeMemory(fact)
        if text.isEmpty { return MemoryWrite(written: false) }
        let existing = try await all()
        if existing.contains(where: { dedupeKey($0.fact) == dedupeKey(text) }) {
            return MemoryWrite(written: false)
        }
        let now = nowMillis ?? clock.nowMillis()
        if tier == .profile {
            let standing = existing.filter { $0.tier == .profile }.count
            if standing >= profileFactLimit { return MemoryWrite(written: false) }
            var body = try await readLines(profilePath)
            if body.isEmpty { body = ["# Standing facts", ""] }
            body.append("- \(text)")
            try await store.writeTextAtomic(profilePath, text: body.joined(separator: "\n").trimmingTrailingWhitespace() + "\n")
            return MemoryWrite(written: true)
        }
        let file = logPath(now)
        var body = try await readLines(file)
        if body.isEmpty {
            body = ["# \(monthKey(now))", "", factsHeading, "", notesHeading, ""]
        }
        let heading = tier == .note ? notesHeading : factsHeading
        let entry = "- \(dayKey(now)) · \(text)"
        if let at = body.firstIndex(of: heading) {
            var insert = body.index(after: at)
            while insert < body.endIndex, !body[insert].hasPrefix("## ") {
                insert = body.index(after: insert)
            }
            body.insert(entry, at: insert)
        } else {
            body.append("")
            body.append(heading)
            body.append("")
            body.append(entry)
        }
        try await store.writeTextAtomic(file, text: body.joined(separator: "\n").trimmingTrailingWhitespace() + "\n")
        return MemoryWrite(written: true)
    }

    func forget(fact: String) async throws -> MemoryForget {
        let target = dedupeKey(normalizeMemory(fact))
        if target.isEmpty { return MemoryForget(removed: 0) }
        var removed = 0
        for file in try await files() {
            let lines = try await readLines(file)
            let kept = lines.filter { line in
                guard let parsed = parseLine(line) else { return true }
                if dedupeKey(parsed.fact) != target { return true }
                removed += 1
                return false
            }
            if kept.count != lines.count {
                try await store.writeTextAtomic(file, text: kept.joined(separator: "\n").trimmingTrailingWhitespace() + "\n")
            }
        }
        return MemoryForget(removed: removed)
    }

    func all() async throws -> [MemoryFact] {
        var out: [MemoryFact] = []
        for line in try await readLines(profilePath) {
            guard let parsed = parseLine(line) else { continue }
            out.append(MemoryFact(fact: parsed.fact, tier: .profile, day: nil))
        }
        let logDir = "\(memoryDir)/log"
        if try await store.exists(logDir) {
            let names = try await store.list(logDir).filter(isMonthFile).sorted()
            for name in names {
                var tier = MemoryTier.log
                for line in try await readLines("\(logDir)/\(name)") {
                    if line.hasPrefix("## ") {
                        tier = line.trimmingCharacters(in: .whitespaces) == notesHeading ? .note : .log
                        continue
                    }
                    guard let parsed = parseLine(line) else { continue }
                    out.append(MemoryFact(fact: parsed.fact, tier: tier, day: parsed.day))
                }
            }
        }
        return out
    }

    private func files() async throws -> [String] {
        let logDir = "\(memoryDir)/log"
        let months: [String]
        if try await store.exists(logDir) {
            months = try await store.list(logDir).filter(isMonthFile).sorted()
        } else {
            months = []
        }
        return [profilePath] + months.map { "\(logDir)/\($0)" }
    }

    private func logPath(_ nowMillis: Int64) -> String { "\(memoryDir)/log/\(monthKey(nowMillis)).md" }

    private func readLines(_ path: String) async throws -> [String] {
        guard let raw = try await store.readText(path) else { return [] }
        return raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

func renderMemory(_ facts: [MemoryFact], memoryDir: String, nowMillis: Int64) -> String {
    let standing = facts.filter { $0.tier == .profile }.prefix(profileFactLimit)
    let dated = facts.filter { $0.tier != .profile }.sorted { recallRank($0, nowMillis) > recallRank($1, nowMillis) }
    var kept: [MemoryFact] = []
    var budget = recallBudget
    for entry in dated {
        let cost = entry.fact.count + 16
        if cost > budget { break }
        budget -= cost
        kept.append(entry)
    }
    kept.sort { ($0.day ?? "") < ($1.day ?? "") }
    var lines = ["## Memory", ""]
    if standing.isEmpty && kept.isEmpty {
        lines.append("You have not recorded anything about this user yet.")
    }
    if !standing.isEmpty {
        lines.append("What you know about this user and your work together:")
        lines.append("")
        standing.forEach { lines.append("- \($0.fact)") }
        lines.append("")
    }
    if !kept.isEmpty {
        lines.append("Recent:")
        lines.append("")
        kept.forEach { lines.append("- \($0.day ?? "") · \($0.fact)") }
        lines.append("")
    }
    let hidden = dated.count - kept.count
    if hidden > 0 {
        lines.append("\(hidden) older entries did not fit here. They are on disk — grep them.")
        lines.append("")
    }
    lines.append("Your memory lives in \(memoryDir) as Markdown: profile.md for standing")
    lines.append("facts, log/YYYY-MM.md for dated ones. Read or grep them directly when you")
    lines.append("need more than the above.")
    lines.append("")
    lines.append("Record something with update_state when it will still matter in a later")
    lines.append("conversation — a preference, a decision, a name, how this project works.")
    lines.append("Do not record what you can read off disk again.")
    return lines.joined(separator: "\n").trimmingTrailingWhitespace()
}

func recallRank(_ entry: MemoryFact, _ nowMillis: Int64) -> Double {
    let importance = entry.tier == .note ? 1.0 : 2.0
    let ageDays: Double
    if let day = entry.day, let then = utcDayMillis(day) {
        ageDays = Double(nowMillis - then) / 86_400_000.0
    } else {
        ageDays = 0
    }
    return log(importance) / log(2.0) - max(0.0, ageDays) / halfLifeDays
}

private let smallTalk: Set<String> = [
    "thanks", "thank you", "ok", "okay", "sure", "yes", "no", "got it", "nice", "cool",
    "谢谢", "好的", "好", "行", "嗯", "收到",
]

func isMemorableExchange(_ userText: String) -> Bool {
    let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return false }
    let stripped = text.lowercased().replacingOccurrences(of: #"[.!?。！？]+$"#, with: "", options: .regularExpression)
    if smallTalk.contains(stripped) { return false }
    return estimateSpeechTokens(text) > 10 || text.contains("?") || text.contains("？")
}

func estimateSpeechTokens(_ text: String) -> Int {
    let units = Array(text.utf16)
    var cjk = 0
    for unit in units {
        guard let scalar = Unicode.Scalar(unit) else { continue }
        if isCJKScalar(scalar) { cjk += 1 }
    }
    return cjk + ((units.count - cjk) + 3) / 4
}

let extractionPrompt = """
You extract durable facts from one exchange between a user and their agent.

Emit one line per fact, each prefixed by its tier:

  profile: <a standing fact — a preference, a name, how this project works>
  log: <a dated fact — a decision made, a thing done, a problem found>
  note: <a minor observation worth keeping but not important>
  remove: <a previously recorded fact that this exchange contradicts>

Rules:
- Each line must stand alone. A reader with no other context must understand
  it, so no pronouns pointing outside the line and no 'as discussed'.
- Only what will still matter in a later conversation. Nothing that can be
  read off disk again, nothing about this exchange's mechanics.
- Most exchanges yield nothing. Emitting no lines at all is the common and
  correct answer. Do not pad.
- No preamble, no explanation, no blank lines. Just the prefixed lines.
"""

func parseExtraction(_ raw: String) -> ExtractedMemory {
    var writes: [(String, MemoryTier)] = []
    var removals: [String] = []
    let pattern = #/^\s*(profile|log|note|remove)\s*:\s*(.+)$/#.ignoresCase()
    for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
        guard let match = try? pattern.wholeMatch(in: String(line)) else { continue }
        let kind = String(match.1).lowercased()
        let fact = normalizeMemory(String(match.2))
        if fact.isEmpty { continue }
        if kind == "remove" {
            removals.append(fact)
        } else {
            let tier: MemoryTier = switch kind {
            case "profile": .profile
            case "note": .note
            default: .log
            }
            writes.append((fact, tier))
        }
    }
    return ExtractedMemory(writes: writes, removals: removals)
}

func normalizeMemory(_ fact: String) -> String {
    var text = fact.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: #"^[-*•]\s*"#, with: "", options: .regularExpression)
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    text = text.replacingOccurrences(of: #"\s*[.。]$"#, with: "", options: .regularExpression)
    return text
}

func dedupeKey(_ fact: String) -> String {
    let normalized = normalizeMemory(fact).lowercased()
    let kept = normalized.unicodeScalars.filter { scalar in
        CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) || scalar == " "
    }
    return String(String.UnicodeScalarView(kept))
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct ParsedLine {
    var fact: String
    var day: String?
}

private func parseLine(_ line: String) -> ParsedLine? {
    guard let match = line.wholeMatch(of: #/^\s*-\s+(.*)$/#) else { return nil }
    let body = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
    if body.isEmpty { return nil }
    if let dated = body.wholeMatch(of: #/^(\d{4}-\d{2}-\d{2})\s+·\s+(.*)$/#) {
        return ParsedLine(fact: String(dated.2).trimmingCharacters(in: .whitespacesAndNewlines), day: String(dated.1))
    }
    return ParsedLine(fact: body, day: nil)
}

private func isMonthFile(_ name: String) -> Bool {
    name.range(of: #"^\d{4}-\d{2}\.md$"#, options: .regularExpression) != nil
}

private func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x1100...0x11FF, 0x3040...0x30FF, 0x3130...0x318F, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF:
        true
    default:
        false
    }
}

private let factsHeading = "## Facts"
private let notesHeading = "## Notes"

private func monthKey(_ millis: Int64) -> String {
    let parts = utcParts(millis)
    return String(format: "%04d-%02d", parts.year, parts.month)
}

private func dayKey(_ millis: Int64) -> String {
    let parts = utcParts(millis)
    return String(format: "%04d-%02d-%02d", parts.year, parts.month, parts.day)
}

private func utcParts(_ millis: Int64) -> (year: Int, month: Int, day: Int) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let date = Date(timeIntervalSince1970: Double(millis) / 1000)
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return (parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
}

private func utcDayMillis(_ day: String) -> Int64? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: day) else { return nil }
    return Int64(date.timeIntervalSince1970 * 1000)
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
    }
}
