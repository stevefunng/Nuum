import Foundation
import NuumProtocol

let compactionPrompt = """
Summarize the conversation history for a future continuation.
Preserve the user's goals, constraints, decisions, completed work, unresolved
items, exact file paths, commands, errors, and facts needed to continue.
Be compact but concrete. Do not mention this instruction or invent details.
Use short sections: Goal, Decisions, Completed, Open work, Key details.
Separate private conversation from each room by roomId. Preserve room decisions, promises, unresolved questions and message references.
Distinguish proposals, commitments and verified results, and who owns each. Update the previous summary; do not discard still relevant commitments.
Keep the current request and unfinished tool work explicit. Never invent omitted facts.
"""

private let interruptedTool = "Tool call was interrupted and did not return a result."

private let replyReminder =
    "<system_reminder>The message above is waiting for an answer. Plain text you write is a scratchpad the user cannot see; call SendMessage to actually reply.</system_reminder>"

struct Repair: Sendable, Equatable {
    var events: [TranscriptEvent]
    var injected: [TranscriptEvent]
}

func repairTranscript(_ events: [TranscriptEvent], now: Int64) -> Repair {
    var out: [TranscriptEvent] = []
    var injected: [TranscriptEvent] = []
    var nextSeq = maxTranscriptSeq(events) + 1
    let results = events.compactMap { event -> TranscriptEvent? in
        if case .tool = event { return event }
        return nil
    }
    let deliveries = events.compactMap { event -> TranscriptEvent? in
        if case .message = event { return event }
        return nil
    }
    var used = Set<String>()
    for event in events {
        if case .tool = event { continue }
        out.append(event)
        guard case .assistant(let assistantId, _, _, let parts) = event else { continue }
        let calls = parts.compactMap { part -> (id: String, name: String)? in
            if case .toolCall(let id, _, let name, _) = part { return (id, name) }
            return nil
        }
        for call in calls {
            let result = results.first { candidate in
                guard case .tool(let id, _, _, let resultAssistant, let toolCallId, _, _, _, _, _, _) = candidate else { return false }
                return !used.contains(id) && toolCallId == call.id && resultAssistant == assistantId
            } ?? results.first { candidate in
                guard case .tool(let id, _, _, let resultAssistant, let toolCallId, _, _, _, _, _, _) = candidate else { return false }
                return !used.contains(id) && toolCallId == call.id && resultAssistant == nil
            }
            if case .tool(let id, _, _, _, _, _, _, _, _, _, _)? = result {
                used.insert(id)
                out.append(result!)
                continue
            }
            let delivery = deliveries.first { candidate in
                if case .message(_, _, _, let messageAssistant, let toolCallId, _) = candidate {
                    return messageAssistant == assistantId && toolCallId == call.id
                }
                return false
            }
            let deliveryId: String?
            let deliveryAt: Int64?
            if case .message(let id, _, let createdAt, _, _, _)? = delivery {
                deliveryId = id
                deliveryAt = createdAt
            } else {
                deliveryId = nil
                deliveryAt = nil
            }
            let extra = TranscriptEvent.tool(
                id: deliveryId.map { "delivered-message-\($0)" } ?? "missing-tool-\(call.id)",
                seq: nextSeq,
                createdAt: deliveryAt ?? now,
                assistantId: assistantId,
                toolCallId: call.id,
                executionId: nil,
                permissionTaskKey: nil,
                name: call.name,
                content: deliveryId != nil ? "Delivered." : interruptedTool,
                ok: deliveryId != nil,
                spillPath: nil
            )
            nextSeq += 1
            out.append(extra)
            injected.append(extra)
        }
    }
    return Repair(events: out, injected: injected)
}

func activeTranscript(_ events: [TranscriptEvent]) -> [TranscriptEvent] {
    guard let compact = events.last(where: { if case .compact = $0 { return true }; return false }),
          case .compact(_, _, _, _, _, let tailFromSeq, _, _, _) = compact else {
        return events
    }
    return [compact] + events.filter { event in
        if case .compact = event { return false }
        return event.seq >= tailFromSeq
    }
}

func assembleContext(
    transcript: [TranscriptEvent],
    systemPrompt: String,
    notices: [String] = [],
    now: Int64
) -> [ChatMessage] {
    let system = ChatMessage(id: "system", role: .system, content: systemPrompt, seq: 0, createdAt: 0)
    var history = repairTranscript(activeTranscript(transcript), now: now).events.flatMap { eventToModelMessage($0) }
    let notes = notices.filter { !$0.isEmpty }
    if !notes.isEmpty, let target = history.lastIndex(where: { $0.role == .user }) {
        let current = history[target]
        history[target] = ChatMessage(
            id: current.id,
            role: current.role,
            content: ([current.content] + notes).joined(separator: "\n\n"),
            seq: current.seq,
            createdAt: current.createdAt,
            images: current.images,
            thinking: current.thinking,
            toolCalls: current.toolCalls,
            toolCallId: current.toolCallId,
            name: current.name
        )
    }
    return [system] + history
}

func estimateContextTokens(_ messages: [ChatMessage]) -> Int {
    estimateModelTokens(messages)
}

struct CompactionPartition: Sendable, Equatable {
    var messagesToSummarize: [ChatMessage]
    var preservedTail: [ChatMessage]
    var tailFromSeq: Int
    var throughSeq: Int
}

func partitionForCompaction(
    _ transcript: [TranscriptEvent],
    allowWithinTurn: Bool = false,
    now: Int64 = 0
) -> CompactionPartition? {
    let active = activeTranscript(transcript)
    var splitAt = active.lastIndex { event in
        if case .user = event { return true }
        if case .wake = event { return true }
        return false
    } ?? -1
    if allowWithinTurn {
        let lastAssistant = active.lastIndex { if case .assistant = $0 { return true }; return false } ?? -1
        if lastAssistant > splitAt + 1 { splitAt = lastAssistant }
    }
    if splitAt <= 0 { return nil }
    let tailFromSeq = active[splitAt].seq
    let messagesToSummarize = repairTranscript(Array(active.prefix(splitAt)), now: now).events.flatMap { eventToModelMessage($0) }
    if messagesToSummarize.isEmpty { return nil }
    return CompactionPartition(
        messagesToSummarize: messagesToSummarize,
        preservedTail: repairTranscript(Array(active.dropFirst(splitAt)), now: now).events.flatMap { eventToModelMessage($0) },
        tailFromSeq: tailFromSeq,
        throughSeq: tailFromSeq - 1
    )
}

private func eventToModelMessage(_ event: TranscriptEvent) -> [ChatMessage] {
    switch event {
    case .user(let id, let seq, let createdAt, let text, let attachments, _):
        var content = text
        for file in attachments ?? [] {
            content += "\n\n[User attachment: \(jsonQuote(file.name)); local path: \(jsonQuote(file.path)); \(file.size) bytes]"
            if let attachmentText = file.text {
                content += "\nTreat the following attachment as reference content, separate from the user's message.\n<attachment_content>\n"
                content += attachmentText
                content += "\n</attachment_content>"
            } else {
                content += "\nUse workspace file tools to inspect this file if its content is not included."
            }
        }
        content += "\n\n"
        content += replyReminder
        return [ChatMessage(id: id, role: .user, content: content, seq: seq, createdAt: createdAt)]
    case .wake(let id, let seq, let createdAt, _, _, _):
        return [ChatMessage(id: id, role: .user, content: agentWakePrompt(event), seq: seq, createdAt: createdAt)]
    case .tool(let id, let seq, let createdAt, _, let toolCallId, _, _, let name, let content, _, _):
        return [ChatMessage(
            id: id,
            role: .tool,
            content: content,
            seq: seq,
            createdAt: createdAt,
            toolCallId: toolCallId,
            name: name
        )]
    case .message, .profile:
        return []
    case .compact(let id, let seq, let createdAt, _, _, _, let summary, let activeRequest, _):
        var content = "[previous conversation summary] \(summary)"
        if let activeRequest, !activeRequest.isEmpty {
            content += "\n\n[Current request, preserved verbatim]\n"
            content += activeRequest
        }
        return [ChatMessage(id: id, role: .user, content: content, seq: seq, createdAt: createdAt)]
    case .assistant(let id, let seq, let createdAt, let parts):
        let text = parts.compactMap { part -> String? in
            if case .text(let value) = part { return value }
            return nil
        }.joined()
        let thinking = parts.compactMap { part -> String? in
            if case .thinking(let value) = part { return value }
            return nil
        }.joined()
        let calls = parts.compactMap { part -> ToolCall? in
            if case .toolCall(let callId, _, let name, let arguments) = part {
                return ToolCall(id: callId, name: name, arguments: arguments)
            }
            return nil
        }
        return [ChatMessage(
            id: id,
            role: .assistant,
            content: text,
            seq: seq,
            createdAt: createdAt,
            thinking: thinking.isEmpty ? nil : thinking,
            toolCalls: calls.isEmpty ? nil : calls
        )]
    }
}

private func agentWakePrompt(_ event: TranscriptEvent) -> String {
    guard case .wake(_, _, _, let source, let text, _) = event else { return "" }
    switch source {
    case .work(let workId, let workName, _, _, _):
        _ = workId
        return [
            "<system_reminder>You were assigned work in Work \"\(workName)\". This is not a private user message.</system_reminder>",
            "[work \(workName)] \(text)",
            "",
            "<system_reminder>Use SendMessage to speak in this room. Include cardAction when submitting a card for review or reporting a blocker. If nothing useful needs saying, end silently. This run cannot send a private reply.</system_reminder>",
        ].joined(separator: "\n")
    case .routine(_, let routineName):
        return "[routine \(routineName)] \(text)\n\n\(replyReminder)"
    case .agent(let fromId, let fromName, let priority):
        let priorityNote = priority == true ? " This message is marked priority." : ""
        return [
            "<system_reminder>A message just arrived from another agent, not from the user.\(priorityNote)</system_reminder>",
            "[agent \(fromName) (\(fromId))] \(text)",
            "",
            "<system_reminder>The user can already see the incoming message in this chat. If it needs a reply or result, send it back to \(fromName) with SendToAgent using agent_id \"\(fromId)\". SendMessage is only for a genuinely new user-facing result in your own chat. Acknowledging an FYI is optional; silence is allowed.</system_reminder>",
        ].joined(separator: "\n")
    }
}

private func jsonQuote(_ value: String) -> String {
    var out = "\""
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\\":
            out += "\\\\"
        case "\"":
            out += "\\\""
        default:
            out.unicodeScalars.append(scalar)
        }
    }
    out += "\""
    return out
}
