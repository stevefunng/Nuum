import Foundation

private let imageTokenCost = 8192

/// Conservative budget, not a provider tokenizer.
/// Image bytes are removed from the JSON, then each image adds 8192.
/// ASCII is about 3 characters per token; non-ASCII is about 2 characters per token.
/// Length is counted in UTF-16 code units, matching `JSON.stringify(...).length`.
public func estimateModelTokens(_ messages: [ChatMessage], tools: [ToolDefinition] = []) -> Int {
    var fields = JSONFieldList()
    fields.add("messages", .array(messages.map(\.budgetJSON)))
    fields.add("tools", .array(tools.map(\.budgetJSON)))
    let text = ProtocolJSON.stringify(fields.json)
    let units = Array(text.utf16)
    let wide = units.reduce(0) { count, unit in count + (unit > 0x7F ? 1 : 0) }
    let body = Int((Double(units.count - wide) / 3.0 + Double(wide) * 2.0).rounded(.up))
    let images = messages.reduce(0) { total, message in
        total + (message.images?.count ?? 0) * imageTokenCost
    }
    return body + images
}

extension ToolDefinition {
    var budgetJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("name", name)
        fields.add("description", description)
        fields.add("inputSchema", inputSchema)
        fields.add("mutating", mutating)
        if let action { fields.add("action", action.rawValue) }
        return fields.json
    }
}
