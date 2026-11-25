import Foundation
import NuumContracts

/// JSON for provider request bodies and SSE payloads.
/// The three clients build the wire object directly. There is no shared LLM SDK.
enum WireValue {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([WireValue])
    case object([(String, WireValue)])

    var objectFields: [(String, WireValue)]? {
        if case .object(let fields) = self { return fields }
        return nil
    }

    func field(_ name: String) -> WireValue? {
        objectFields?.first { $0.0 == name }?.1
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var array: [WireValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var int: Int? {
        switch self {
        case .int(let value):
            guard value >= Int64(Int.min), value <= Int64(Int.max) else { return nil }
            return Int(value)
        case .double(let value):
            guard value.rounded() == value, value >= Double(Int.min), value <= Double(Int.max) else { return nil }
            return Int(value)
        default:
            return nil
        }
    }

    var jsonValue: JSONValue {
        switch self {
        case .null:
            .null
        case .bool(let value):
            .bool(value)
        case .int(let value):
            .int(value)
        case .double(let value):
            .double(value)
        case .string(let value):
            .string(value)
        case .array(let values):
            .array(values.map(\.jsonValue))
        case .object(let fields):
            .object(fields.reduce(into: [String: JSONValue]()) { object, field in
                object[field.0] = field.1.jsonValue
            })
        }
    }
}

enum ModelJSON {
    static func encode(_ value: WireValue) -> String {
        switch value {
        case .null:
            "null"
        case .bool(let flag):
            flag ? "true" : "false"
        case .int(let number):
            String(number)
        case .double(let number):
            encodeDouble(number)
        case .string(let text):
            encodeString(text)
        case .array(let values):
            "[" + values.map(encode).joined(separator: ",") + "]"
        case .object(let fields):
            "{" + fields.map { encodeString($0.0) + ":" + encode($0.1) }.joined(separator: ",") + "}"
        }
    }

    static func data(_ value: WireValue) -> Data {
        Data(encode(value).utf8)
    }

    static func parse(_ text: String) throws -> WireValue {
        var parser = Parser(text)
        let value = try parser.parseValue()
        try parser.skipWhitespace()
        guard parser.isAtEnd else { throw ParseError() }
        return value
    }

    static func value(_ json: JSONValue) -> WireValue {
        switch json {
        case .null:
            .null
        case .bool(let flag):
            .bool(flag)
        case .int(let number):
            .int(number)
        case .double(let number):
            .double(number)
        case .string(let text):
            .string(text)
        case .array(let values):
            .array(values.map(value))
        case .object(let fields):
            .object(fields.map { ($0.key, value($0.value)) })
        }
    }

    /// Tool-call argument object. Blank is `{}`. A JSON array or scalar is dropped.
    /// Invalid JSON is a model error (1004) and the message does not echo the payload.
    static func argumentObject(_ raw: String) throws -> [String: JSONValue] {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        let value: WireValue
        do {
            value = try parse(raw)
        } catch {
            throw NuumError(code: KernelErrorCode.model, message: "Model tool arguments were not valid JSON")
        }
        guard let fields = value.objectFields else { return [:] }
        var object: [String: JSONValue] = [:]
        for (key, item) in fields {
            object[key] = item.jsonValue
        }
        return object
    }

    private static func encodeDouble(_ number: Double) -> String {
        guard number.isFinite else { return "null" }
        if number.rounded() == number, number >= Double(Int64.min), number <= Double(Int64.max) {
            return String(Int64(number))
        }
        return String(number)
    }

    private static func encodeString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22:
                out += "\\\""
            case 0x5C:
                out += "\\\\"
            case 0x08:
                out += "\\b"
            case 0x0C:
                out += "\\f"
            case 0x0A:
                out += "\\n"
            case 0x0D:
                out += "\\r"
            case 0x09:
                out += "\\t"
            case 0..<0x20:
                out += String(format: "\\u%04x", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
        return out
    }

    private struct ParseError: Error {}

    private struct Parser {
        private let scalars: [Unicode.Scalar]
        private var index = 0

        init(_ text: String) {
            scalars = Array(text.unicodeScalars)
        }

        var isAtEnd: Bool { index >= scalars.count }

        private var peek: Unicode.Scalar? {
            isAtEnd ? nil : scalars[index]
        }

        private mutating func advance() -> Unicode.Scalar? {
            guard !isAtEnd else { return nil }
            let scalar = scalars[index]
            index += 1
            return scalar
        }

        mutating func skipWhitespace() throws {
            while let scalar = peek, scalar == " " || scalar == "\n" || scalar == "\r" || scalar == "\t" {
                index += 1
            }
        }

        mutating func parseValue() throws -> WireValue {
            try skipWhitespace()
            guard let scalar = peek else { throw ParseError() }
            switch scalar {
            case "{":
                return try parseObject()
            case "[":
                return try parseArray()
            case "\"":
                return .string(try parseString())
            case "t":
                try expect("true")
                return .bool(true)
            case "f":
                try expect("false")
                return .bool(false)
            case "n":
                try expect("null")
                return .null
            default:
                return try parseNumber()
            }
        }

        private mutating func parseObject() throws -> WireValue {
            _ = advance()
            var fields: [(String, WireValue)] = []
            try skipWhitespace()
            if peek == "}" {
                _ = advance()
                return .object(fields)
            }
            while true {
                try skipWhitespace()
                guard peek == "\"" else { throw ParseError() }
                let key = try parseString()
                try skipWhitespace()
                guard advance() == ":" else { throw ParseError() }
                let value = try parseValue()
                fields.append((key, value))
                try skipWhitespace()
                let separator = advance()
                if separator == "}" { return .object(fields) }
                guard separator == "," else { throw ParseError() }
            }
        }

        private mutating func parseArray() throws -> WireValue {
            _ = advance()
            var values: [WireValue] = []
            try skipWhitespace()
            if peek == "]" {
                _ = advance()
                return .array(values)
            }
            while true {
                values.append(try parseValue())
                try skipWhitespace()
                let separator = advance()
                if separator == "]" { return .array(values) }
                guard separator == "," else { throw ParseError() }
            }
        }

        private mutating func parseString() throws -> String {
            guard advance() == "\"" else { throw ParseError() }
            var out = String.UnicodeScalarView()
            while let scalar = advance() {
                if scalar == "\"" { return String(out) }
                if scalar == "\\" {
                    guard let escaped = advance() else { throw ParseError() }
                    switch escaped {
                    case "\"": out.append("\"")
                    case "\\": out.append("\\")
                    case "/": out.append("/")
                    case "b": out.append("\u{08}")
                    case "f": out.append("\u{0C}")
                    case "n": out.append("\n")
                    case "r": out.append("\r")
                    case "t": out.append("\t")
                    case "u":
                        let unit = try parseHex4()
                        if UTF16.isLeadSurrogate(unit), let next = peek, next == "\\" {
                            let saved = index
                            _ = advance()
                            if peek == "u" {
                                _ = advance()
                                let low = try parseHex4()
                                if UTF16.isTrailSurrogate(low) {
                                    let encoded = String(utf16CodeUnits: [unit, low], count: 2)
                                    out.append(contentsOf: encoded.unicodeScalars)
                                    continue
                                }
                            }
                            index = saved
                        }
                        guard let decoded = Unicode.Scalar(unit) else { throw ParseError() }
                        out.append(decoded)
                    default:
                        throw ParseError()
                    }
                } else {
                    out.append(scalar)
                }
            }
            throw ParseError()
        }

        private mutating func parseHex4() throws -> UInt16 {
            var value: UInt16 = 0
            for _ in 0..<4 {
                guard let scalar = advance(), let digit = hex(scalar) else { throw ParseError() }
                value = value << 4 | UInt16(digit)
            }
            return value
        }

        private func hex(_ scalar: Unicode.Scalar) -> Int? {
            switch scalar {
            case "0"..."9": Int(scalar.value - Unicode.Scalar("0").value)
            case "a"..."f": Int(scalar.value - Unicode.Scalar("a").value) + 10
            case "A"..."F": Int(scalar.value - Unicode.Scalar("A").value) + 10
            default: nil
            }
        }

        private mutating func parseNumber() throws -> WireValue {
            let start = index
            if peek == "-" { index += 1 }
            guard let first = peek, first >= "0", first <= "9" else { throw ParseError() }
            if first == "0" {
                index += 1
            } else {
                while let scalar = peek, scalar >= "0", scalar <= "9" { index += 1 }
            }
            var isFloat = false
            if peek == "." {
                isFloat = true
                index += 1
                guard let digit = peek, digit >= "0", digit <= "9" else { throw ParseError() }
                while let scalar = peek, scalar >= "0", scalar <= "9" { index += 1 }
            }
            if peek == "e" || peek == "E" {
                isFloat = true
                index += 1
                if peek == "+" || peek == "-" { index += 1 }
                guard let digit = peek, digit >= "0", digit <= "9" else { throw ParseError() }
                while let scalar = peek, scalar >= "0", scalar <= "9" { index += 1 }
            }
            let literal = String(String.UnicodeScalarView(scalars[start..<index]))
            if isFloat {
                guard let number = Double(literal) else { throw ParseError() }
                return .double(number)
            }
            guard let number = Int64(literal) else { throw ParseError() }
            return .int(number)
        }

        private mutating func expect(_ literal: String) throws {
            for scalar in literal.unicodeScalars {
                guard advance() == scalar else { throw ParseError() }
            }
        }
    }
}
