import Foundation
import NuumContracts

/// Conservative fallback, not a provider tokenizer. Mirrors
/// `packages/protocol/src/context-budget.ts`: images are stripped from the JSON
/// envelope and each one adds 8192 tokens. Null optional fields are omitted the
/// way `JSON.stringify` omits `undefined`. Key order does not change the count.
func estimateModelTokens(_ messages: [ChatMessage], tools: [ToolDefinition] = []) -> Int {
    var text = "{\"messages\":["
    for (index, message) in messages.enumerated() {
        if index > 0 { text.append(",") }
        appendEstimateMessage(message, to: &text)
    }
    text.append("],\"tools\":[")
    for (index, tool) in tools.enumerated() {
        if index > 0 { text.append(",") }
        appendEstimateTool(tool, to: &text)
    }
    text.append("]}")
    let units = Array(text.utf16)
    let wide = units.reduce(into: 0) { count, unit in
        if unit > 0x7F { count += 1 }
    }
    let raw = Double(units.count - wide) / 3.0 + Double(wide) * 2.0
    let textTokens = Int(raw.rounded(.up))
    let imageTokens = messages.reduce(into: 0) { total, message in
        total += (message.images?.count ?? 0) * 8192
    }
    return textTokens + imageTokens
}

private func appendEstimateMessage(_ message: ChatMessage, to text: inout String) {
    text.append("{\"id\":")
    appendJSONString(message.id, to: &text)
    text.append(",\"role\":")
    appendJSONString(message.role.rawValue, to: &text)
    text.append(",\"content\":")
    appendJSONString(message.content, to: &text)
    if let thinking = message.thinking {
        text.append(",\"thinking\":")
        appendJSONString(thinking, to: &text)
    }
    if let calls = message.toolCalls, !calls.isEmpty {
        text.append(",\"toolCalls\":[")
        for (index, call) in calls.enumerated() {
            if index > 0 { text.append(",") }
            appendEstimateToolCall(call, to: &text)
        }
        text.append("]")
    }
    if let toolCallId = message.toolCallId {
        text.append(",\"toolCallId\":")
        appendJSONString(toolCallId, to: &text)
    }
    if let name = message.name {
        text.append(",\"name\":")
        appendJSONString(name, to: &text)
    }
    text.append(",\"seq\":")
    text.append(String(message.seq))
    text.append(",\"createdAt\":")
    text.append(String(message.createdAt))
    text.append("}")
}

private func appendEstimateToolCall(_ call: ToolCall, to text: inout String) {
    text.append("{\"id\":")
    appendJSONString(call.id, to: &text)
    text.append(",\"name\":")
    appendJSONString(call.name, to: &text)
    text.append(",\"arguments\":")
    appendJSONObject(call.arguments, to: &text)
    text.append("}")
}

private func appendEstimateTool(_ tool: ToolDefinition, to text: inout String) {
    text.append("{\"name\":")
    appendJSONString(tool.name, to: &text)
    text.append(",\"description\":")
    appendJSONString(tool.description, to: &text)
    text.append(",\"inputSchema\":")
    appendJSONObject(tool.inputSchema, to: &text)
    text.append(",\"mutating\":")
    text.append(tool.mutating ? "true" : "false")
    if let action = tool.action {
        text.append(",\"action\":")
        appendJSONString(action.rawValue, to: &text)
    }
    text.append("}")
}

private func appendJSONObject(_ fields: [String: JSONValue], to text: inout String) {
    text.append("{")
    var first = true
    for (key, value) in fields {
        if !first { text.append(",") }
        first = false
        appendJSONString(key, to: &text)
        text.append(":")
        appendJSONValue(value, to: &text)
    }
    text.append("}")
}

private func appendJSONValue(_ value: JSONValue, to text: inout String) {
    switch value {
    case .null:
        text.append("null")
    case .bool(let flag):
        text.append(flag ? "true" : "false")
    case .int(let number):
        text.append(String(number))
    case .double(let number):
        appendJSONNumber(number, to: &text)
    case .string(let string):
        appendJSONString(string, to: &text)
    case .array(let values):
        text.append("[")
        for (index, nested) in values.enumerated() {
            if index > 0 { text.append(",") }
            appendJSONValue(nested, to: &text)
        }
        text.append("]")
    case .object(let fields):
        appendJSONObject(fields, to: &text)
    }
}

private func appendJSONNumber(_ value: Double, to text: inout String) {
    guard value.isFinite else {
        text.append("null")
        return
    }
    if value == 0 {
        text.append("0")
        return
    }
    let truncated = value.rounded(.towardZero)
    if truncated == value, value <= maxSafeInteger, value >= -maxSafeInteger {
        text.append(String(Int64(value)))
        return
    }
    text.append(String(value))
}

private func appendJSONString(_ value: String, to text: inout String) {
    text.append("\"")
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x22:
            text.append("\\\"")
        case 0x5C:
            text.append("\\\\")
        case 0x08:
            text.append("\\b")
        case 0x09:
            text.append("\\t")
        case 0x0A:
            text.append("\\n")
        case 0x0C:
            text.append("\\f")
        case 0x0D:
            text.append("\\r")
        case 0x00..<0x20, 0x2028, 0x2029:
            text.append(String(format: "\\u%04x", scalar.value))
        default:
            text.unicodeScalars.append(scalar)
        }
    }
    text.append("\"")
}

private let maxSafeInteger: Double = 9_007_199_254_740_991
