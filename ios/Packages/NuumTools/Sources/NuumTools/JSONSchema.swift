import NuumContracts

enum JSONSchema {
    static func object(
        _ properties: [String: JSONValue],
        required: [String] = [],
        additionalProperties: Bool? = nil,
        oneOf: [JSONValue]? = nil
    ) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            body["required"] = .array(required.map { .string($0) })
        }
        if let additionalProperties {
            body["additionalProperties"] = .bool(additionalProperties)
        }
        if let oneOf {
            body["oneOf"] = .array(oneOf)
        }
        return body
    }

    static func string(description: String? = nil) -> JSONValue {
        var fields: [String: JSONValue] = ["type": .string("string")]
        if let description {
            fields["description"] = .string(description)
        }
        return .object(fields)
    }

    static func integer(minimum: Int64? = nil, default defaultValue: Int64? = nil) -> JSONValue {
        var fields: [String: JSONValue] = ["type": .string("integer")]
        if let minimum {
            fields["minimum"] = .int(minimum)
        }
        if let defaultValue {
            fields["default"] = .int(defaultValue)
        }
        return .object(fields)
    }

    static func boolean() -> JSONValue {
        .object(["type": .string("boolean")])
    }

    static func enumeration(_ values: [String]) -> JSONValue {
        .object(["enum": .array(values.map { .string($0) })])
    }

    static func array(items: JSONValue, minItems: Int64? = nil, description: String? = nil) -> JSONValue {
        var fields: [String: JSONValue] = [
            "type": .string("array"),
            "items": items,
        ]
        if let minItems {
            fields["minItems"] = .int(minItems)
        }
        if let description {
            fields["description"] = .string(description)
        }
        return .object(fields)
    }

    static func required(_ keys: [String]) -> JSONValue {
        .object(["required": .array(keys.map { .string($0) })])
    }
}
