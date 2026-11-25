import Foundation
import NuumContracts

enum Phase: Equatable, Sendable {
    case loading
    case ready
}

enum Banner: Equatable, Sendable {
    case localized(CopyKey, alert: Bool)
    case raw(String, alert: Bool)

    var alert: Bool {
        switch self {
        case .localized(_, let alert), .raw(_, let alert): alert
        }
    }

    func text(language: Language) -> String {
        switch self {
        case .localized(let key, _):
            ConversationCopy.text(key, language: language)
        case .raw(let text, _):
            text
        }
    }
}

func banner(from error: Error) -> Banner {
    let message: String
    if let nuum = error as? NuumError {
        message = nuum.message
    } else {
        message = error.localizedDescription
    }
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .localized(.hostError, alert: true) }
    return .raw(trimmed, alert: true)
}

struct ToolResult: Equatable, Sendable {
    var content: String
    var ok: Bool?
}

struct ComposerAttachment: Equatable, Sendable {
    var name: String
    var mimeType: String
    var bytes: Data
}

enum AttachmentDecision: Equatable, Sendable {
    case accept([ComposerAttachment])
    case reject(CopyKey)
}

/// Count, then a single file, then the total. Oversized adds do not call send.
func validateAttachments(current: [ComposerAttachment], incoming: [PickedFile]) -> AttachmentDecision {
    if incoming.isEmpty { return .accept(current) }
    let decision = attachmentDecision(
        currentBytes: current.map(\.bytes.count),
        incomingBytes: incoming.map(\.bytes.count)
    )
    if case .reject(let reason) = decision { return .reject(reason) }
    let added = incoming.map { file in
        ComposerAttachment(
            name: file.name,
            mimeType: file.mimeType.isEmpty ? "application/octet-stream" : file.mimeType,
            bytes: file.bytes
        )
    }
    return .accept(current + added)
}

enum AttachmentSizeDecision: Equatable, Sendable {
    case accept
    case reject(CopyKey)
}

func attachmentDecision(currentBytes: [Int], incomingBytes: [Int]) -> AttachmentSizeDecision {
    if incomingBytes.isEmpty { return .accept }
    if currentBytes.count + incomingBytes.count > AttachmentLimits.maxCount {
        return .reject(.atMost5)
    }
    if incomingBytes.contains(where: { $0 > AttachmentLimits.maxBytes }) {
        return .reject(.tooLarge)
    }
    let total = currentBytes.reduce(Int64(0)) { $0 + Int64($1) } + incomingBytes.reduce(Int64(0)) { $0 + Int64($1) }
    if total > Int64(AttachmentLimits.maxTotalBytes) { return .reject(.totalTooLarge) }
    return .accept
}

func isImageMime(_ mimeType: String) -> Bool {
    imageMIMETypes.contains(mimeType.lowercased())
}

func mimeType(forFileName name: String) -> String {
    switch (name as NSString).pathExtension.lowercased() {
    case "png": "image/png"
    case "jpg", "jpeg": "image/jpeg"
    case "gif": "image/gif"
    case "webp": "image/webp"
    case "txt", "md": "text/plain"
    case "json": "application/json"
    case "pdf": "application/pdf"
    default: "application/octet-stream"
    }
}

func isImagePath(_ path: String) -> Bool {
    isImageMime(mimeType(forFileName: path))
}

/// Mac shows `max(1, ceil(bytes / 1024)) KB`.
func attachmentKilobytes(_ bytes: Int) -> Int {
    max(1, Int((Double(max(bytes, 0)) / 1024).rounded(.up)))
}

func fileName(of path: String) -> String {
    let name = (path as NSString).lastPathComponent
    return name.isEmpty ? path : name
}

enum NunuActivity: Equatable, Sendable {
    case idle
    case thinking
    case working
    case waiting
    case error
    case sending
    case receiving
}

func nunuActivityState(status: AgentStatus?, awaitingApproval: Bool, executingTool: Bool) -> NunuActivity {
    if awaitingApproval { return .waiting }
    if status == .error { return .error }
    if status != .running { return .idle }
    return executingTool ? .working : .thinking
}

func appendAssistantDelta(_ parts: [AssistantPart], kind: MessagePart, delta: String) -> [AssistantPart] {
    var next = parts
    if kind == .text, let last = next.last, case .text(let part) = last {
        next[next.count - 1] = .text(TextPart(text: part.text + delta))
        return next
    }
    if kind == .thinking, let last = next.last, case .thinking(let part) = last {
        next[next.count - 1] = .thinking(ThinkingPart(text: part.text + delta))
        return next
    }
    switch kind {
    case .thinking:
        next.append(.thinking(ThinkingPart(text: delta)))
    case .text:
        next.append(.text(TextPart(text: delta)))
    }
    return next
}

func ensureToolCall(
    _ live: LiveAssistant?,
    toolCallId: String,
    name: String,
    arguments: [String: JSONValue]
) -> LiveAssistant {
    let messageId = live?.messageId ?? toolCallId
    var parts = live?.parts ?? []
    let exists = parts.contains { part in
        if case .toolCall(let call) = part { return call.id == toolCallId }
        return false
    }
    if !exists {
        parts.append(.toolCall(ToolCallPart(id: toolCallId, name: name, arguments: arguments)))
    }
    return LiveAssistant(messageId: messageId, parts: parts)
}

/// UI grouping only. Transcript identities stay in order. Empty settled activity is dropped.
func groupToolActivity(_ blocks: [ViewBlock]) -> [ViewBlock] {
    var result: [ViewBlock] = []
    for block in blocks {
        guard case .assistant(let assistant) = block else {
            result.append(block)
            continue
        }
        if !assistant.live && assistant.tools.isEmpty { continue }
        if case .assistant(let previous) = result.last {
            result[result.count - 1] = .assistant(AssistantBlock(
                id: previous.id,
                thinking: previous.thinking,
                tools: previous.tools + assistant.tools,
                live: assistant.live
            ))
        } else {
            result.append(block)
        }
    }
    return result
}

func hasExecutingTool(_ blocks: [ViewBlock]) -> Bool {
    blocks.contains { block in
        guard case .assistant(let assistant) = block else { return false }
        return assistant.live && assistant.tools.contains { $0.status == "pending" }
    }
}

func widgetAnswers(_ blocks: [ViewBlock]) -> [String: String] {
    var answers: [String: String] = [:]
    for block in blocks {
        guard case .user(let user) = block, let target = user.widgetAnswerTo else { continue }
        answers[target] = user.text
    }
    return answers
}

extension ViewBlock {
    var blockID: String {
        switch self {
        case .user(let block): block.id
        case .assistant(let block): block.id
        case .message(let block): block.id
        case .peer(let block): block.id
        case .notice(let block): block.id
        }
    }
}

func projectAgent(
    _ events: [TranscriptEvent],
    live: LiveAssistant? = nil,
    extraResults: [String: ToolResult] = [:]
) -> [ViewBlock] {
    var blocks: [ViewBlock] = []
    var results: [String: ToolResult] = [:]
    for (id, result) in extraResults {
        if results[id] == nil { results[id] = result }
    }
    var knownCalls: Set<String> = []
    for event in events {
        if case .assistant(let assistant) = event {
            for part in assistant.parts {
                if case .toolCall(let call) = part {
                    knownCalls.insert(call.id)
                    knownCalls.insert("\(assistant.id)\u{0000}\(call.id)")
                }
            }
        }
        if case .tool(let tool) = event {
            let result = ToolResult(content: tool.content, ok: tool.ok)
            if results[tool.toolCallId] == nil { results[tool.toolCallId] = result }
            if let assistantId = tool.assistantId, results["\(assistantId)\u{0000}\(tool.toolCallId)"] == nil {
                results["\(assistantId)\u{0000}\(tool.toolCallId)"] = result
            }
        }
    }
    for event in events {
        switch event {
        case .user(let user):
            blocks.append(.user(UserBlock(
                id: user.id,
                text: user.text,
                attachments: user.attachments,
                widgetAnswerTo: user.widgetAnswerTo
            )))
        case .wake(let wake):
            blocks.append(wakeBlock(wake))
        case .message(let message):
            blocks.append(.message(MessageBlock(id: message.id, payload: message.payload)))
        case .compact(let compact):
            blocks.append(.notice(NoticeBlock(
                id: compact.id,
                kind: "compact",
                text: "Earlier messages were summarized to fit the context window. The originals are still on disk."
            )))
        case .profile(let profile):
            blocks.append(.notice(NoticeBlock(id: profile.id, kind: "profile", text: describeProfile(profile))))
        case .assistant(let assistant):
            let causal = causalResults(assistant, results)
            let block = assistantBlock(id: assistant.id, parts: assistant.parts, results: causal, live: false)
            if !block.thinking.isEmpty || !block.tools.isEmpty { blocks.append(.assistant(block)) }
            blocks.append(contentsOf: outboundPeerBlocks(assistant.parts, causal))
        case .tool(let tool):
            let scoped = "\(tool.assistantId ?? "")\u{0000}\(tool.toolCallId)"
            if knownCalls.contains(scoped) || knownCalls.contains(tool.toolCallId) { continue }
            blocks.append(.assistant(AssistantBlock(
                id: tool.id,
                thinking: "",
                tools: [ToolView(
                    id: tool.toolCallId,
                    name: tool.name,
                    arguments: [:],
                    output: tool.content,
                    status: tool.ok == false ? "error" : "ok"
                )]
            )))
        }
    }
    if let live, !blocks.contains(where: { block in
        if case .assistant(let assistant) = block { return assistant.id == live.messageId }
        return false
    }) {
        let block = assistantBlock(id: live.messageId, parts: live.parts, results: extraResults, live: true)
        if block.live || !block.thinking.isEmpty || !block.tools.isEmpty {
            blocks.append(.assistant(block))
        }
        blocks.append(contentsOf: outboundPeerBlocks(live.parts, extraResults))
    }
    return blocks
}

private func wakeBlock(_ event: WakeTranscript) -> ViewBlock {
    switch event.source {
    case .agent(let source):
        return .peer(PeerBlock(
            id: event.id,
            direction: "inbound",
            agentId: source.fromId,
            agentName: source.fromName,
            text: event.text,
            priority: source.priority
        ))
    case .work(let source):
        return .notice(NoticeBlock(id: event.id, kind: "wake", text: "Participated in room: \(source.workName)"))
    case .routine:
        return .notice(NoticeBlock(id: event.id, kind: "wake", text: describeWake(event)))
    }
}

func describeWake(_ event: WakeTranscript) -> String {
    switch event.source {
    case .agent(let source):
        let marker = source.priority ? " (priority)" : ""
        return "From \(source.fromName)\(marker): \(event.text)"
    case .work(let source):
        let task = source.taskId.map { " task \($0)" } ?? ""
        return "From Work \(source.workName)\(task): \(event.text)"
    case .routine(let source):
        return "Routine \(source.routineName): \(event.text)"
    }
}

func describeProfile(_ event: ProfileTranscript) -> String {
    var parts: [String] = []
    if let name = event.name { parts.append("name to \"\(name)\"") }
    if event.description != nil { parts.append("its description") }
    if event.tags != nil { parts.append("its tags") }
    if parts.isEmpty { return "This agent changed its profile." }
    return "This agent changed \(parts.joined(separator: " and "))."
}

private func causalResults(_ event: AssistantTranscript, _ results: [String: ToolResult]) -> [String: ToolResult] {
    var causal: [String: ToolResult] = [:]
    for part in event.parts {
        guard case .toolCall(let call) = part else { continue }
        if let result = results["\(event.id)\u{0000}\(call.id)"] ?? results[call.id] {
            causal[call.id] = result
        }
    }
    return causal
}

func assistantBlock(
    id: String,
    parts: [AssistantPart],
    results: [String: ToolResult],
    live: Bool
) -> AssistantBlock {
    let tools: [ToolView] = parts.compactMap { part in
        guard case .toolCall(let call) = part else { return nil }
        if call.name == "SendMessage" { return nil }
        let result = results[call.id]
        if call.name == "SendToAgent", let result, result.ok != false { return nil }
        let status: String
        if result == nil {
            status = "pending"
        } else if result?.ok == false {
            status = "error"
        } else {
            status = "ok"
        }
        return ToolView(
            id: call.id,
            name: call.name,
            arguments: call.arguments,
            output: result?.content,
            status: status
        )
    }
    let thinking = parts.compactMap { part -> String? in
        if case .thinking(let part) = part { return part.text }
        return nil
    }.joined()
    return AssistantBlock(id: id, thinking: thinking, tools: tools, live: live)
}

private func outboundPeerBlocks(_ parts: [AssistantPart], _ results: [String: ToolResult]) -> [ViewBlock] {
    parts.compactMap { part in
        guard case .toolCall(let call) = part, call.name == "SendToAgent" else { return nil }
        guard let agentId = stringArgument(call.arguments, "agent_id"),
              let text = stringArgument(call.arguments, "message") else { return nil }
        guard let result = results[call.id], result.ok != false else { return nil }
        return .peer(PeerBlock(
            id: call.id,
            direction: "outbound",
            agentId: agentId,
            agentName: agentNameFromDelivery(result.content) ?? agentId,
            text: text,
            priority: boolArgument(call.arguments, "priority")
        ))
    }
}

func stringArgument(_ arguments: [String: JSONValue], _ key: String) -> String? {
    guard case .string(let value) = arguments[key], !value.isEmpty else { return nil }
    return value
}

func boolArgument(_ arguments: [String: JSONValue], _ key: String) -> Bool {
    if case .bool(let value) = arguments[key] { return value }
    return false
}

func agentNameFromDelivery(_ content: String) -> String? {
    guard !content.isEmpty else { return nil }
    let pattern = #"^(?:Sent|Delivered) to (.+?)(?: as priority|,|\.|$)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(content.startIndex..., in: content)
    guard let match = regex.firstMatch(in: content, range: range), match.numberOfRanges > 1,
          let nameRange = Range(match.range(at: 1), in: content) else { return nil }
    let name = content[nameRange].trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}

func mergeEvents(_ current: [TranscriptEvent], _ event: TranscriptEvent) -> [TranscriptEvent] {
    (current.filter { $0.id != event.id } + [event]).sorted { lhs, rhs in
        if lhs.seq != rhs.seq { return lhs.seq < rhs.seq }
        return lhs.id < rhs.id
    }
}

func transcriptTimestamps(_ events: [TranscriptEvent]) -> [String: Int64] {
    var timestamps: [String: Int64] = [:]
    for event in events {
        timestamps[event.id] = event.createdAt
        if case .assistant(let assistant) = event {
            for part in assistant.parts {
                if case .toolCall(let call) = part { timestamps[call.id] = assistant.createdAt }
            }
        }
    }
    return timestamps
}

func showTimeSeparator(previous: Int64?, current: Int64, calendar: Calendar = .current) -> Bool {
    guard let previous else { return true }
    if current - previous >= 5 * 60 * 1000 { return true }
    let previousDate = Date(timeIntervalSince1970: Double(previous) / 1000)
    let currentDate = Date(timeIntervalSince1970: Double(current) / 1000)
    let left = calendar.dateComponents([.year, .month, .day], from: previousDate)
    let right = calendar.dateComponents([.year, .month, .day], from: currentDate)
    return left.year != right.year || left.month != right.month || left.day != right.day
}

func transcriptStamp(millis: Int64, now: Date = Date(), calendar: Calendar = .current, language: Language) -> String {
    let date = Date(timeIntervalSince1970: Double(millis) / 1000)
    let time = timeText(date, calendar: calendar, language: language)
    if calendar.isDate(date, inSameDayAs: now) {
        return ConversationCopy.text(.today, language: language, values: ["time": time])
    }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
        return ConversationCopy.text(.yesterday, language: language, values: ["time": time])
    }
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = locale(for: language)
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

func locale(for language: Language) -> Locale {
    switch language {
    case .zhCN: Locale(identifier: "zh_CN")
    case .en: Locale(identifier: "en_US")
    }
}

private func timeText(_ date: Date, calendar: Calendar, language: Language) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = locale(for: language)
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

enum TranscriptRow: Equatable, Identifiable, Sendable {
    case time(id: String, text: String)
    case block(ViewBlock)

    var id: String {
        switch self {
        case .time(let id, _): "time-\(id)"
        case .block(let block): block.blockID
        }
    }
}

func transcriptRows(
    _ blocks: [ViewBlock],
    timestamps: [String: Int64],
    now: Date = Date(),
    calendar: Calendar = .current,
    language: Language
) -> [TranscriptRow] {
    var rows: [TranscriptRow] = []
    for (index, block) in blocks.enumerated() {
        guard let timestamp = timestamps[block.blockID] else {
            rows.append(.block(block))
            continue
        }
        let previous = index > 0 ? timestamps[blocks[index - 1].blockID] : nil
        if showTimeSeparator(previous: previous, current: timestamp, calendar: calendar) {
            rows.append(.time(
                id: block.blockID,
                text: transcriptStamp(millis: timestamp, now: now, calendar: calendar, language: language)
            ))
        }
        rows.append(.block(block))
    }
    return rows
}

func localizedNotice(_ block: NoticeBlock, language: Language) -> String {
    if block.kind == "profile" {
        if let name = renamedAgent(block.text) {
            return ConversationCopy.text(.profileRenamed, language: language, values: ["name": name])
        }
        return ConversationCopy.text(.profileChanged, language: language)
    }
    let prefix = "Participated in room: "
    if block.kind == "wake", block.text.hasPrefix(prefix) {
        let name = String(block.text.dropFirst(prefix.count))
        return ConversationCopy.text(.participated, language: language, values: ["name": name])
    }
    return ConversationCopy.text(block.text, language: language)
}

func renamedAgent(_ text: String) -> String? {
    let pattern = #"^This agent changed name to "(.*)"\.$"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
          let nameRange = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[nameRange])
}

func toolLabel(_ name: String, language: Language) -> String {
    switch name.lowercased() {
    case "bash", "shell":
        return ConversationCopy.text(.bash, language: language)
    case "external_operation":
        return ConversationCopy.text(.localOperation, language: language)
    case "request_network":
        return ConversationCopy.text(.networkAccess, language: language)
    case "read":
        return ConversationCopy.text(.read, language: language)
    case "ls":
        return ConversationCopy.text(.list, language: language)
    case "write":
        return ConversationCopy.text(.write, language: language)
    default:
        return splitCamel(name)
    }
}

func splitCamel(_ name: String) -> String {
    var result = ""
    var previous: Character?
    for character in name {
        if let previous, previous.isLowercase, character.isUppercase {
            result.append(" ")
        }
        result.append(character)
        previous = character
    }
    return result
}

func toolStatusKey(_ status: String) -> CopyKey {
    switch status {
    case "pending": .executing
    case "error": .failed
    default: .completed
    }
}

func groupToolStatus(_ tools: [ToolView]) -> String {
    if tools.contains(where: { $0.status == "pending" }) { return "pending" }
    if tools.contains(where: { $0.status == "error" }) { return "error" }
    return "ok"
}

func prettyJSON(_ value: JSONValue) -> String {
    switch value {
    case .null:
        "null"
    case .bool(let flag):
        flag ? "true" : "false"
    case .int(let number):
        String(number)
    case .double(let number):
        if number.isFinite, number.rounded() == number, number <= Double(Int64.max), number >= Double(Int64.min) {
            String(Int64(number))
        } else {
            String(number)
        }
    case .string(let text):
        encodeJSONString(text)
    case .array(let values):
        if values.isEmpty { "[]" } else {
            "[\n" + values.map { "  " + indent(prettyJSON($0)) }.joined(separator: ",\n") + "\n]"
        }
    case .object(let object):
        prettyJSONObject(object)
    }
}

func prettyJSONObject(_ object: [String: JSONValue]) -> String {
    if object.isEmpty { return "{}" }
    let lines = object.keys.sorted().map { key in
        "  \(encodeJSONString(key)): \(indent(prettyJSON(object[key] ?? .null)))"
    }
    return "{\n" + lines.joined(separator: ",\n") + "\n}"
}

private func indent(_ text: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard lines.count > 1 else { return text }
    return lines.enumerated().map { index, line in
        index == 0 ? line : "  " + line
    }.joined(separator: "\n")
}

func encodeJSONString(_ text: String) -> String {
    var result = "\""
    for character in text {
        switch character {
        case "\\": result += "\\\\"
        case "\"": result += "\\\""
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        default: result.append(character)
        }
    }
    result += "\""
    return result
}

func firstLine(_ text: String) -> String {
    text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
}

func actionCopy(_ action: LocalToolAction) -> CopyKey {
    switch action {
    case .readFile: .readFile
    case .listDirectory: .listDirectory
    case .writeFile: .writeFile
    case .runCommand: .runCommand
    case .network: .network
    }
}

enum ActivityLine: Equatable, Sendable {
    case thinking
    case tools
}

func activityLine(for block: AssistantBlock) -> ActivityLine? {
    if block.tools.isEmpty { return block.live ? .thinking : nil }
    return .tools
}

/// One-to-one approval. Mac puts `workId` on `agent.tool.pending` when the run
/// belongs to a work, and this surface drops that pending. The contract event
/// has no `workId` yet, so contract events keep it nil. A non-empty id hides the bar.
struct PendingTool: Equatable, Sendable {
    var toolCallId: String
    var name: String
    var arguments: [String: JSONValue]
    var action: LocalToolAction
    var target: String
    var justification: String?
    var allowAlways: Bool?
    var details: String?
    var workId: String?

    var alwaysEnabled: Bool { allowAlways != false }
}

func oneToOneApproval(_ pending: PendingTool?) -> PendingTool? {
    guard let pending else { return nil }
    if let workId = pending.workId, !workId.isEmpty { return nil }
    return pending
}

func pendingTool(from event: AgentToolPendingEvent, workId: String? = nil) -> PendingTool {
    PendingTool(
        toolCallId: event.toolCallId,
        name: event.toolName,
        arguments: event.arguments,
        action: event.action,
        target: event.target,
        justification: event.justification,
        allowAlways: event.allowAlways,
        details: event.details,
        workId: workId
    )
}
