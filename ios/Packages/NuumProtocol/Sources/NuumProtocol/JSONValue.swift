import Foundation

/// JSON value with object key order preserved.
/// Field names elsewhere in this package match `packages/protocol` and `android/core/protocol`.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])

    public var objectPairs: [(String, JSONValue)]? {
        if case .object(let pairs) = self { return pairs }
        return nil
    }

    public var arrayValues: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int64? {
        switch self {
        case .int(let value):
            return value
        case .double(let value) where value.rounded() == value && value >= Double(Int64.min) && value <= Double(Int64.max):
            return Int64(value)
        default:
            return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            return true
        case (.bool(let left), .bool(let right)):
            return left == right
        case (.int(let left), .int(let right)):
            return left == right
        case (.double(let left), .double(let right)):
            return left == right
        case (.int(let left), .double(let right)):
            return Double(left) == right
        case (.double(let left), .int(let right)):
            return left == Double(right)
        case (.string(let left), .string(let right)):
            return left == right
        case (.array(let left), .array(let right)):
            return left == right
        case (.object(let left), .object(let right)):
            return Dictionary(left, uniquingKeysWith: { _, last in last })
                == Dictionary(right, uniquingKeysWith: { _, last in last })
        default:
            return false
        }
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int64.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            if value.rounded() == value, value >= Double(Int64.min), value <= Double(Int64.max) {
                self = .int(Int64(value))
            } else {
                self = .double(value)
            }
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            let pairs = value.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
            self = .object(pairs)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .double(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case .object(let pairs):
            var container = encoder.container(keyedBy: JSONCodingKey.self)
            for (key, value) in pairs {
                try container.encode(value, forKey: JSONCodingKey(stringValue: key))
            }
        }
    }
}

struct JSONCodingKey: CodingKey, Hashable, Sendable {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

public struct JSONFieldList: Sendable {
    public private(set) var pairs: [(String, JSONValue)] = []

    public init() {}

    public mutating func add(_ key: String, _ value: JSONValue) {
        pairs.append((key, value))
    }

    public mutating func add(_ key: String, _ value: String) {
        add(key, .string(value))
    }

    public mutating func add(_ key: String, _ value: Int) {
        add(key, .int(Int64(value)))
    }

    public mutating func add(_ key: String, _ value: Int64) {
        add(key, .int(value))
    }

    public mutating func add(_ key: String, _ value: Bool) {
        add(key, .bool(value))
    }

    public mutating func addIfPresent(_ key: String, _ value: String?) {
        if let value { add(key, value) }
    }

    public mutating func addIfPresent(_ key: String, _ value: Int?) {
        if let value { add(key, value) }
    }

    public mutating func addIfPresent(_ key: String, _ value: Int64?) {
        if let value { add(key, value) }
    }

    public mutating func addIfPresent(_ key: String, _ value: Bool?) {
        if let value { add(key, value) }
    }

    public mutating func addIfPresent(_ key: String, _ value: JSONValue?) {
        if let value { add(key, value) }
    }

    public mutating func addNull(_ key: String) {
        add(key, .null)
    }

    public var json: JSONValue { .object(pairs) }
}

struct JSONObject: Sendable {
    var pairs: [(String, JSONValue)]
    var path: [String]

    init(pairs: [(String, JSONValue)], path: [String] = []) {
        self.pairs = pairs
        self.path = path
    }

    init(_ value: JSONValue, path: [String] = []) throws {
        guard case .object(let pairs) = value else {
            throw ProtocolParseException(path, "Expected an object")
        }
        self.pairs = pairs
        self.path = path
    }

    func contains(_ key: String) -> Bool {
        pairs.contains { $0.0 == key }
    }

    func value(_ key: String) -> JSONValue? {
        pairs.last { $0.0 == key }?.1
    }

    func require(_ key: String) throws -> JSONValue {
        guard let value = value(key) else {
            throw ProtocolParseException(path + [key], "Required")
        }
        return value
    }

    func string(_ key: String) throws -> String {
        let raw = try require(key)
        guard case .string(let value) = raw else {
            throw ProtocolParseException(path + [key], "Expected a string")
        }
        return value
    }

    /// Missing or JSON null becomes nil. Any other non-string fails.
    func optionalString(_ key: String) throws -> String? {
        guard let raw = value(key) else { return nil }
        if raw.isNull { return nil }
        guard case .string(let value) = raw else {
            throw ProtocolParseException(path + [key], "Expected a string")
        }
        return value
    }

    func bool(_ key: String) throws -> Bool {
        let raw = try require(key)
        guard case .bool(let value) = raw else {
            throw ProtocolParseException(path + [key], "Expected a boolean")
        }
        return value
    }

    func optionalBool(_ key: String) throws -> Bool? {
        guard let raw = value(key) else { return nil }
        if raw.isNull { return nil }
        guard case .bool(let value) = raw else {
            throw ProtocolParseException(path + [key], "Expected a boolean")
        }
        return value
    }

    func int(_ key: String) throws -> Int {
        let raw = try integer(key)
        guard raw >= Int64(Int.min), raw <= Int64(Int.max) else {
            throw ProtocolParseException(path + [key], "Expected an integer")
        }
        return Int(raw)
    }

    func optionalInt(_ key: String) throws -> Int? {
        guard let raw = value(key) else { return nil }
        if raw.isNull { return nil }
        let number = try integerValue(raw, key: key)
        guard number >= Int64(Int.min), number <= Int64(Int.max) else {
            throw ProtocolParseException(path + [key], "Expected an integer")
        }
        return Int(number)
    }

    func int64(_ key: String) throws -> Int64 {
        try integer(key)
    }

    func optionalInt64(_ key: String) throws -> Int64? {
        guard let raw = value(key) else { return nil }
        if raw.isNull { return nil }
        return try integerValue(raw, key: key)
    }

    /// Required key that may be JSON null.
    func nullableString(_ key: String) throws -> String? {
        let raw = try require(key)
        if raw.isNull { return nil }
        guard case .string(let value) = raw else {
            throw ProtocolParseException(path + [key], "Expected a string")
        }
        return value
    }

    func stringArray(_ key: String) throws -> [String] {
        guard let raw = value(key) else { return [] }
        if raw.isNull { return [] }
        guard case .array(let values) = raw else {
            throw ProtocolParseException(path + [key], "Expected an array")
        }
        return try values.enumerated().map { index, element in
            guard case .string(let value) = element else {
                throw ProtocolParseException(path + [key, String(index)], "Expected a string")
            }
            return value
        }
    }

    func optionalStringArray(_ key: String) throws -> [String]? {
        guard let raw = value(key) else { return nil }
        if raw.isNull { return nil }
        guard case .array(let values) = raw else {
            throw ProtocolParseException(path + [key], "Expected an array")
        }
        return try values.enumerated().map { index, element in
            guard case .string(let value) = element else {
                throw ProtocolParseException(path + [key, String(index)], "Expected a string")
            }
            return value
        }
    }

    func object(_ key: String) throws -> JSONObject {
        let raw = try require(key)
        guard case .object(let nested) = raw else {
            throw ProtocolParseException(path + [key], "Expected an object")
        }
        return JSONObject(pairs: nested, path: path + [key])
    }

    func optionalObject(_ key: String) throws -> JSONObject? {
        guard let raw = value(key) else { return nil }
        if raw.isNull { return nil }
        guard case .object(let nested) = raw else {
            throw ProtocolParseException(path + [key], "Expected an object")
        }
        return JSONObject(pairs: nested, path: path + [key])
    }

    func array(_ key: String) throws -> [JSONValue] {
        let raw = try require(key)
        guard case .array(let values) = raw else {
            throw ProtocolParseException(path + [key], "Expected an array")
        }
        return values
    }

    func optionalArray(_ key: String) throws -> [JSONValue]? {
        guard let raw = value(key) else { return nil }
        if raw.isNull { return nil }
        guard case .array(let values) = raw else {
            throw ProtocolParseException(path + [key], "Expected an array")
        }
        return values
    }

    func enumeration<T: RawRepresentable>(_ key: String, as type: T.Type) throws -> T where T.RawValue == String {
        let raw = try string(key)
        guard let value = T(rawValue: raw) else {
            throw ProtocolParseException(path + [key], "Invalid enum value")
        }
        return value
    }

    func optionalEnumeration<T: RawRepresentable>(_ key: String, as type: T.Type) throws -> T? where T.RawValue == String {
        guard let raw = try optionalString(key) else { return nil }
        guard let value = T(rawValue: raw) else {
            throw ProtocolParseException(path + [key], "Invalid enum value")
        }
        return value
    }

    private func integer(_ key: String) throws -> Int64 {
        try integerValue(try require(key), key: key)
    }

    private func integerValue(_ raw: JSONValue, key: String) throws -> Int64 {
        switch raw {
        case .int(let value):
            return value
        case .double(let value):
            throw ProtocolParseException(path + [key], "Expected an integer")
        case .string:
            throw ProtocolParseException(path + [key], "Expected an integer")
        default:
            throw ProtocolParseException(path + [key], "Expected an integer")
        }
    }
}

public enum ProtocolJSON {
    public static func parse(_ text: String) throws -> JSONValue {
        var parser = JSONParser(text)
        let value = try parser.parseValue()
        try parser.skipWhitespace()
        if !parser.isAtEnd {
            throw ProtocolParseException([], "Trailing JSON")
        }
        return value
    }

    public static func stringify(_ value: JSONValue) -> String {
        var output = ""
        write(value, into: &output)
        return output
    }

    public static func decode<T: WireRepresentable>(_ type: T.Type, from text: String) throws -> T {
        try T(protocolJSON: parse(text))
    }

    public static func encode(_ value: some WireRepresentable) -> String {
        stringify(value.protocolJSON)
    }

    private static func write(_ value: JSONValue, into output: inout String) {
        switch value {
        case .null:
            output += "null"
        case .bool(let flag):
            output += flag ? "true" : "false"
        case .int(let number):
            output += String(number)
        case .double(let number):
            if number.rounded() == number, number >= Double(Int64.min), number <= Double(Int64.max) {
                output += String(Int64(number))
            } else {
                output += String(number)
            }
        case .string(let text):
            writeString(text, into: &output)
        case .array(let values):
            output += "["
            for (index, element) in values.enumerated() {
                if index > 0 { output += "," }
                write(element, into: &output)
            }
            output += "]"
        case .object(let pairs):
            output += "{"
            for (index, pair) in pairs.enumerated() {
                if index > 0 { output += "," }
                writeString(pair.0, into: &output)
                output += ":"
                write(pair.1, into: &output)
            }
            output += "}"
        }
    }

    private static func writeString(_ text: String, into output: inout String) {
        output += "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"":
                output += "\\\""
            case "\\":
                output += "\\\\"
            case "\u{08}":
                output += "\\b"
            case "\u{0c}":
                output += "\\f"
            case "\n":
                output += "\\n"
            case "\r":
                output += "\\r"
            case "\t":
                output += "\\t"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.append(Character(scalar))
                }
            }
        }
        output += "\""
    }
}

private struct JSONParser {
    let scalars: [Unicode.Scalar]
    var index = 0

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    var isAtEnd: Bool { index >= scalars.count }

    mutating func parseValue() throws -> JSONValue {
        try skipWhitespace()
        guard let scalar = peek() else {
            throw ProtocolParseException([], "Expected JSON")
        }
        switch scalar {
        case "n":
            try consumeLiteral("null")
            return .null
        case "t":
            try consumeLiteral("true")
            return .bool(true)
        case "f":
            try consumeLiteral("false")
            return .bool(false)
        case "\"":
            return .string(try parseString())
        case "[":
            return try parseArray()
        case "{":
            return try parseObject()
        default:
            return try parseNumber()
        }
    }

    mutating func skipWhitespace() throws {
        while let scalar = peek(), scalar == " " || scalar == "\n" || scalar == "\r" || scalar == "\t" {
            index += 1
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        try consume("[")
        try skipWhitespace()
        var values: [JSONValue] = []
        if peek() == "]" {
            index += 1
            return .array(values)
        }
        while true {
            values.append(try parseValue())
            try skipWhitespace()
            if peek() == "," {
                index += 1
                continue
            }
            if peek() == "]" {
                index += 1
                return .array(values)
            }
            throw ProtocolParseException([], "Expected ',' or ']'")
        }
    }

    private mutating func parseObject() throws -> JSONValue {
        try consume("{")
        try skipWhitespace()
        var pairs: [(String, JSONValue)] = []
        if peek() == "}" {
            index += 1
            return .object(pairs)
        }
        while true {
            try skipWhitespace()
            let key = try parseString()
            try skipWhitespace()
            try consume(":")
            let value = try parseValue()
            pairs.append((key, value))
            try skipWhitespace()
            if peek() == "," {
                index += 1
                continue
            }
            if peek() == "}" {
                index += 1
                return .object(pairs)
            }
            throw ProtocolParseException([], "Expected ',' or '}'")
        }
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = index
        if peek() == "-" { index += 1 }
        guard let first = peek(), first.isDigit else {
            throw ProtocolParseException([], "Expected a number")
        }
        while let scalar = peek(), scalar.isDigit { index += 1 }
        var isDouble = false
        if peek() == "." {
            isDouble = true
            index += 1
            guard let digit = peek(), digit.isDigit else {
                throw ProtocolParseException([], "Expected a digit")
            }
            while let scalar = peek(), scalar.isDigit { index += 1 }
        }
        if peek() == "e" || peek() == "E" {
            isDouble = true
            index += 1
            if peek() == "+" || peek() == "-" { index += 1 }
            guard let digit = peek(), digit.isDigit else {
                throw ProtocolParseException([], "Expected an exponent")
            }
            while let scalar = peek(), scalar.isDigit { index += 1 }
        }
        let literal = String(String.UnicodeScalarView(scalars[start..<index]))
        if !isDouble, let integer = Int64(literal) {
            return .int(integer)
        }
        guard let number = Double(literal) else {
            throw ProtocolParseException([], "Expected a number")
        }
        return .double(number)
    }

    private mutating func parseString() throws -> String {
        try consume("\"")
        var output = ""
        while let scalar = peek() {
            index += 1
            if scalar == "\"" { return output }
            if scalar == "\\" {
                guard let escaped = peek() else {
                    throw ProtocolParseException([], "Unterminated string")
                }
                index += 1
                switch escaped {
                case "\"": output.append("\"")
                case "\\": output.append("\\")
                case "/": output.append("/")
                case "b": output.append("\u{08}")
                case "f": output.append("\u{0c}")
                case "n": output.append("\n")
                case "r": output.append("\r")
                case "t": output.append("\t")
                case "u":
                    let unit = try parseHex4()
                    if let unicode = Unicode.Scalar(unit) {
                        output.append(Character(unicode))
                    } else if UTF16.isLeadSurrogate(unit),
                              peek() == "\\",
                              scalars.indices.contains(index + 1),
                              scalars[index + 1] == "u" {
                        index += 2
                        let trail = try parseHex4()
                        guard let composed = Unicode.Scalar(UInt32(unit - 0xD800) << 10 + UInt32(trail - 0xDC00) + 0x10000) else {
                            throw ProtocolParseException([], "Invalid unicode escape")
                        }
                        output.append(Character(composed))
                    } else {
                        throw ProtocolParseException([], "Invalid unicode escape")
                    }
                default:
                    throw ProtocolParseException([], "Invalid escape")
                }
            } else {
                output.append(Character(scalar))
            }
        }
        throw ProtocolParseException([], "Unterminated string")
    }

    private mutating func parseHex4() throws -> UInt16 {
        guard index + 4 <= scalars.count else {
            throw ProtocolParseException([], "Invalid unicode escape")
        }
        let hex = String(String.UnicodeScalarView(scalars[index..<(index + 4)]))
        guard let value = UInt16(hex, radix: 16) else {
            throw ProtocolParseException([], "Invalid unicode escape")
        }
        index += 4
        return value
    }

    private mutating func consumeLiteral(_ literal: String) throws {
        for scalar in literal.unicodeScalars {
            guard peek() == scalar else {
                throw ProtocolParseException([], "Expected \(literal)")
            }
            index += 1
        }
    }

    private mutating func consume(_ expected: Unicode.Scalar) throws {
        guard peek() == expected else {
            throw ProtocolParseException([], "Expected \(expected)")
        }
        index += 1
    }

    private func peek() -> Unicode.Scalar? {
        index < scalars.count ? scalars[index] : nil
    }
}

private extension Unicode.Scalar {
    var isDigit: Bool { value >= 48 && value <= 57 }
}

public protocol WireRepresentable: Codable, Sendable {
    init(protocolJSON: JSONValue) throws
    var protocolJSON: JSONValue { get }
}

extension WireRepresentable {
    public init(from decoder: Decoder) throws {
        do {
            self = try Self(protocolJSON: JSONValue(from: decoder))
        } catch let error as ProtocolParseException {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: error.message,
                    underlyingError: error
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try protocolJSON.encode(to: encoder)
    }
}
