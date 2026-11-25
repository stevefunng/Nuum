import Foundation

enum JSONNode: Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONNode])
    case object([(String, JSONNode)])
}

enum JSONDocument {
    static let settingsMustBeObject = "settings.json must be a JSON object"

    static func parse(_ text: String) -> JSONNode? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return JSONNode(raw)
    }

    static func requireObject(_ text: String) throws -> JSONNode {
        guard let node = parse(text), case .object = node else {
            throw invalid(settingsMustBeObject)
        }
        return node
    }

    static func field(_ node: JSONNode?, _ name: String) -> JSONNode? {
        guard case .object(let fields) = node else { return nil }
        return fields.first { $0.0 == name }?.1
    }

    static func has(_ node: JSONNode?, _ name: String) -> Bool {
        guard case .object(let fields) = node else { return false }
        return fields.contains { $0.0 == name }
    }

    static func isNull(_ node: JSONNode?) -> Bool {
        if node == nil { return true }
        if case .null = node { return true }
        return false
    }

    static func string(_ node: JSONNode?) -> String? {
        if case .string(let value) = node { return value }
        return nil
    }

    static func int(_ node: JSONNode?) -> Int64? {
        switch node {
        case .int(let value):
            value
        case .double(let value):
            Int64(value)
        default:
            nil
        }
    }

    static func nullableString(_ node: JSONNode?, _ name: String) -> String? {
        guard has(node, name), let value = field(node, name), !isNull(value) else { return nil }
        return string(value)
    }

    static func stringList(_ node: JSONNode?) -> [String] {
        guard case .array(let items) = node else { return [] }
        var seen: Set<String> = []
        var values: [String] = []
        for item in items {
            guard let text = string(item)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
            if seen.insert(text).inserted {
                values.append(text)
            }
        }
        return values
    }

    static func render(_ node: JSONNode, indent: Int = 0) -> String {
        switch node {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .int(let value):
            return String(value)
        case .double(let value):
            if !value.isFinite { return "null" }
            return String(value)
        case .string(let value):
            return quote(value)
        case .array(let items):
            if items.isEmpty { return "[]" }
            let pad = String(repeating: " ", count: indent)
            let nested = String(repeating: " ", count: indent + 2)
            let body = items.map { nested + render($0, indent: indent + 2) }.joined(separator: ",\n")
            return "[\n\(body)\n\(pad)]"
        case .object(let fields):
            return renderFields(fields, indent: indent)
        }
    }

    static func renderFields(_ fields: [(String, JSONNode)], indent: Int = 0) -> String {
        if fields.isEmpty { return "{}" }
        let pad = String(repeating: " ", count: indent)
        let nested = String(repeating: " ", count: indent + 2)
        let body = fields.map { name, value in
            nested + quote(name) + ": " + render(value, indent: indent + 2)
        }.joined(separator: ",\n")
        return "{\n\(body)\n\(pad)}"
    }

    static func removingSecretFields(_ node: JSONNode) -> (JSONNode, Bool) {
        switch node {
        case .object(let fields):
            var next: [(String, JSONNode)] = []
            var removed = false
            next.reserveCapacity(fields.count)
            for (key, value) in fields {
                if isForbiddenKey(key) {
                    removed = true
                    continue
                }
                let (child, childRemoved) = removingSecretFields(value)
                if childRemoved { removed = true }
                next.append((key, child))
            }
            return (.object(next), removed)
        case .array(let items):
            var removed = false
            let next = items.map { item in
                let (child, childRemoved) = removingSecretFields(item)
                if childRemoved { removed = true }
                return child
            }
            return (.array(next), removed)
        default:
            return (node, false)
        }
    }

    static func quote(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x5C:
                out += "\\\\"
            case 0x22:
                out += "\\\""
            case 0x0A:
                out += "\\n"
            case 0x0D:
                out += "\\r"
            case 0x09:
                out += "\\t"
            case let code where code < 0x20:
                out += String(format: "\\u%04x", code)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
        return out
    }

    private static func isForbiddenKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.contains("key") || normalized.contains("secret") || normalized == "authorization"
    }
}

extension JSONNode {
    fileprivate init?(_ value: Any) {
        if value is NSNull {
            self = .null
            return
        }
        if let bool = value as? Bool {
            self = .bool(bool)
            return
        }
        if let int = value as? Int {
            self = .int(Int64(int))
            return
        }
        if let int = value as? Int64 {
            self = .int(int)
            return
        }
        if let double = value as? Double {
            self = JSONNode(double)
            return
        }
        if let number = value as? NSNumber {
            let type = String(cString: number.objCType)
            if type == "d" || type == "f" {
                self = JSONNode(number.doubleValue)
            } else {
                self = .int(number.int64Value)
            }
            return
        }
        if let string = value as? String {
            self = .string(string)
            return
        }
        if let array = value as? [Any] {
            var items: [JSONNode] = []
            items.reserveCapacity(array.count)
            for item in array {
                guard let node = JSONNode(item) else { return nil }
                items.append(node)
            }
            self = .array(items)
            return
        }
        if let object = value as? [String: Any] {
            var fields: [(String, JSONNode)] = []
            fields.reserveCapacity(object.count)
            for (key, item) in object {
                guard let node = JSONNode(item) else { return nil }
                fields.append((key, node))
            }
            self = .object(fields)
            return
        }
        return nil
    }

    private init(_ double: Double) {
        if double.isFinite,
           double.rounded(.towardZero) == double,
           double <= Double(Int64.max),
           double >= Double(Int64.min) {
            self = .int(Int64(double))
        } else {
            self = .double(double)
        }
    }
}
