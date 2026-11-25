import Foundation
import NuumContracts

/// UTF-8 JSON object: `openaiApiKey`, `anthropicApiKey`, `deepseekApiKey`.
/// Null fields are omitted. Empty strings are kept.
/// A failure carries no payload, so a bad blob cannot echo a key.
enum SecretsCodec {
    static func encode(_ secrets: Secrets) -> Data {
        var fields: [String] = []
        appendField(&fields, "openaiApiKey", secrets.openaiApiKey)
        appendField(&fields, "anthropicApiKey", secrets.anthropicApiKey)
        appendField(&fields, "deepseekApiKey", secrets.deepseekApiKey)
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

    static func decode(_ data: Data) throws -> Secrets {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw SecretsCodecError.unreadable
        }
        guard let object = parsed as? [String: Any] else {
            throw SecretsCodecError.unreadable
        }
        return Secrets(
            openaiApiKey: try stringField(object, "openaiApiKey"),
            anthropicApiKey: try stringField(object, "anthropicApiKey"),
            deepseekApiKey: try stringField(object, "deepseekApiKey")
        )
    }

    private static func appendField(_ fields: inout [String], _ name: String, _ value: String?) {
        guard let value else { return }
        fields.append("\"\(name)\":\(quoted(value))")
    }

    private static func quoted(_ value: String) -> String {
        var encoded = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22:
                encoded.append("\\\"")
            case 0x5C:
                encoded.append("\\\\")
            case 0x08:
                encoded.append("\\b")
            case 0x09:
                encoded.append("\\t")
            case 0x0A:
                encoded.append("\\n")
            case 0x0C:
                encoded.append("\\f")
            case 0x0D:
                encoded.append("\\r")
            case 0x00..<0x08, 0x0B, 0x0E..<0x20, 0x2028, 0x2029:
                encoded.append(String(format: "\\u%04x", scalar.value))
            default:
                encoded.unicodeScalars.append(scalar)
            }
        }
        encoded.append("\"")
        return encoded
    }

    private static func stringField(_ object: [String: Any], _ name: String) throws -> String? {
        guard let value = object[name] else { return nil }
        if value is NSNull { return nil }
        guard let string = value as? String else {
            throw SecretsCodecError.unreadable
        }
        return string
    }
}

enum SecretsCodecError: Error, CustomStringConvertible, CustomDebugStringConvertible {
    case unreadable

    var description: String { "SecretsCodecError" }
    var debugDescription: String { description }
}
