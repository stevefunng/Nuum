import NuumContracts

func stringField(
    _ input: [String: JSONValue],
    _ key: String,
    optional: Bool = false,
    allowEmpty: Bool = false
) throws -> String? {
    guard let value = present(input, key) else {
        if optional { return nil }
        throw invalidString(key, allowEmpty: allowEmpty)
    }
    guard case .string(let text) = value, allowEmpty || !text.isEmpty else {
        throw invalidString(key, allowEmpty: allowEmpty)
    }
    return text
}

func booleanField(_ input: [String: JSONValue], _ key: String) throws -> Bool? {
    guard let value = present(input, key) else { return nil }
    guard case .bool(let flag) = value else {
        throw NuumError(code: KernelErrorCode.invalid, message: "\(key) must be a boolean.")
    }
    return flag
}

func integerField(_ input: [String: JSONValue], _ key: String, min: Int) throws -> Int? {
    guard let value = present(input, key) else { return nil }
    guard let integer = asInteger(value), integer >= Int64(min), integer <= Int64(Int.max) else {
        throw NuumError(code: KernelErrorCode.invalid, message: "\(key) must be an integer >= \(min).")
    }
    return Int(integer)
}

func enumField(
    _ input: [String: JSONValue],
    _ key: String,
    values: [String],
    fallback: String
) throws -> String {
    guard let value = present(input, key) else { return fallback }
    guard case .string(let text) = value, values.contains(text) else {
        throw NuumError(
            code: KernelErrorCode.invalid,
            message: "\(key) must be one of: \(values.joined(separator: ", "))."
        )
    }
    return text
}

func present(_ input: [String: JSONValue], _ key: String) -> JSONValue? {
    guard let value = input[key] else { return nil }
    if case .null = value { return nil }
    return value
}

private func invalidString(_ key: String, allowEmpty: Bool) -> NuumError {
    let qualifier = allowEmpty ? "string" : "non-empty string"
    return NuumError(code: KernelErrorCode.invalid, message: "\(key) must be a \(qualifier).")
}

private func asInteger(_ value: JSONValue) -> Int64? {
    switch value {
    case .int(let number):
        return number
    case .double(let number):
        guard number.isFinite, number == number.rounded() else { return nil }
        guard number >= Double(Int64.min), number <= Double(Int64.max) else { return nil }
        return Int64(number)
    default:
        return nil
    }
}
