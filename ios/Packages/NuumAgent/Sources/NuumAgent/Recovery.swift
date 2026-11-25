import Foundation
import NuumProtocol

/// Claiming appends the missing tool event. It does not re-run the tool.
func claimExecutionResult(
    events: [TranscriptEvent],
    record: ExecutionReceipt,
    now: Int64,
    newId: () -> String
) throws -> [TranscriptEvent] {
    guard record.requestId.hasPrefix("\(record.runId):") else {
        throw RecoveryError("Execution result does not match its Host-owned run")
    }
    let toolCallId = String(record.requestId.dropFirst("\(record.runId):".count))
    if events.contains(where: { event in
        if case .tool(_, _, _, _, _, let executionId, _, _, _, _, _) = event {
            return executionId == record.requestId
        }
        return false
    }) {
        return []
    }
    let call: TranscriptEvent? = events.last { event in
        guard case .assistant(_, _, _, let parts) = event else { return false }
        return parts.contains { part in
            guard case .toolCall(let id, let executionId, _, _) = part else { return false }
            return executionId == record.requestId || (executionId == nil && id == toolCallId)
        }
    }
    if let call, case .assistant(let assistantId, _, _, _) = call,
       events.contains(where: { event in
           if case .tool(_, _, _, let eventAssistant, let eventCall, let executionId, _, _, _, _, _) = event {
               return executionId == nil && eventAssistant == assistantId && eventCall == toolCallId
           }
           return false
       }) {
        return []
    }
    var appended: [TranscriptEvent] = []
    var seq = (events.map(\.seq).max() ?? 0) + 1
    let assistantId: String
    if case .assistant(let id, _, _, _) = call {
        assistantId = id
    } else {
        assistantId = "recovered-call:\(record.requestId)"
        appended.append(.assistant(
            id: assistantId,
            seq: seq,
            createdAt: now,
            parts: [.toolCall(id: toolCallId, executionId: record.requestId, name: record.name, arguments: record.arguments)]
        ))
        seq += 1
    }
    let originalName: String? = {
        guard case .assistant(_, _, _, let parts) = call else { return nil }
        for part in parts {
            if case .toolCall(let id, _, let name, _) = part, id == toolCallId { return name }
        }
        return nil
    }()
    appended.append(.tool(
        id: newId(),
        seq: seq,
        createdAt: now,
        assistantId: assistantId,
        toolCallId: toolCallId,
        executionId: record.requestId,
        permissionTaskKey: nil,
        name: originalName ?? record.name,
        content: record.output,
        ok: record.ok,
        spillPath: nil
    ))
    return appended
}

struct RecoveryError: Error, Sendable, Equatable, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
