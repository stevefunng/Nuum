import Foundation

/// A blank reply or `(pass)` spends no public message.
func isPass(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return true }
    return trimmed.range(of: #"^\(?\s*pass\s*\)?\.?$"#, options: [.regularExpression, .caseInsensitive]) != nil
}

func orderSpeakers<T>(_ members: [T], round: Int) -> [T] {
    if members.isEmpty { return [] }
    let offset = round % members.count
    return Array(members.dropFirst(offset)) + Array(members.prefix(offset))
}

struct MentionedMessage: Sendable, Equatable {
    var body: String
    var mentionedAgentIds: [String]
}

struct DiscussionMember: Sendable, Equatable {
    var id: String
    var name: String
}

func discussionResponders(
    _ members: [DiscussionMember],
    _ messages: [MentionedMessage],
    defaultAll: Bool = true
) throws -> [DiscussionMember] {
    var ids: [String] = []
    func insert(_ id: String) {
        if !ids.contains(id) { ids.append(id) }
    }
    for message in messages {
        let text = message.body.lowercased()
        if text.range(of: #"(?:^|[^a-z0-9])@(everyone|all)\b"#, options: .regularExpression) != nil {
            return members
        }
        message.mentionedAgentIds.forEach { insert($0) }
        if !message.mentionedAgentIds.isEmpty { continue }
        var aliases: [String: [String]] = [:]
        var aliasOrder: [String] = []
        for member in members {
            let name = member.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let first = name.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            var seen = Set<String>()
            for alias in [name, name.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression), first] {
                if alias.isEmpty || !seen.insert(alias).inserted { continue }
                if aliases[alias] == nil { aliasOrder.append(alias) }
                aliases[alias, default: []].append(member.id)
            }
        }
        for alias in aliasOrder {
            let targets = aliases[alias] ?? []
            if !mentioned(text, alias) { continue }
            if targets.count > 1 {
                let full = members.filter { member in
                    targets.contains(member.id)
                        && member.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != alias
                        && mentioned(text, member.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                }
                if full.count == 1 {
                    insert(full[0].id)
                    continue
                }
                throw DiscussionMentionError("Ambiguous @\(alias); use the member's full name or select a specific member")
            }
            if let target = targets.first { insert(target) }
        }
    }
    if ids.isEmpty && defaultAll { return members }
    return members.filter { ids.contains($0.id) }
}

struct DiscussionMentionError: Error, Sendable, Equatable, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

struct MemberTurn: Sendable, Equatable {
    var messages: Int
    var failed: Bool = false
}

/// The room owns this loop only. Each member's turn still goes through the scheduler.
/// Stops after the round, message, or per-turn limits, a silent round, or cancellation.
func runDiscussion(
    current: @Sendable () -> Bool,
    responders: @Sendable () async throws -> [String],
    runMember: @Sendable (String) async throws -> MemberTurn
) async throws {
    var total = 0
    var failed = Set<String>()
    for round in 0..<discussionLimits.rounds {
        if !current() { return }
        let order = orderSpeakers(try await responders().filter { !failed.contains($0) }, round: round)
        var spoken = 0
        for agentId in order {
            if !current() || total >= discussionLimits.messages { return }
            let result = try await runMember(agentId)
            total += result.messages
            spoken += result.messages
            if result.failed { failed.insert(agentId) }
        }
        if spoken == 0 { return }
    }
}

private func mentioned(_ text: String, _ handle: String) -> Bool {
    let needle = "@\(handle)"
    var search = text.startIndex
    while let range = text.range(of: needle, range: search..<text.endIndex) {
        let before = range.lowerBound == text.startIndex ? "" : String(text[text.index(before: range.lowerBound)])
        let after = range.upperBound == text.endIndex ? "" : String(text[range.upperBound])
        let beforeOK = before.range(of: #"[a-z0-9]"#, options: .regularExpression) == nil
        let afterOK = after.range(of: #"[a-z0-9]"#, options: .regularExpression) == nil
        if beforeOK && afterOK { return true }
        search = range.upperBound
    }
    return false
}
