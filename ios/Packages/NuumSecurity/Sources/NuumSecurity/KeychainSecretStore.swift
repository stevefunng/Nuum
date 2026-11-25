#if canImport(Security)
import Foundation
import NuumContracts
@preconcurrency import Security

/// One generic-password item. Service and account are `KeychainSecretItem`.
/// Accessibility is `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
/// The item is not synchronizable and has no access-control flags.
/// A missing item reads as empty `Secrets`. Read and write failures throw
/// `NuumError.secretReadFailed` or `NuumError.secretWriteFailed` and do not
/// chain the underlying status, JSON, or payload.
public struct KeychainSecretStore: SecretStore, CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    public init() {}

    public func read() async throws -> Secrets {
        guard var data = try Self.copyValue() else { return .empty }
        defer { wipe(&data) }
        do {
            return try SecretsCodec.decode(data)
        } catch {
            throw NuumError.secretReadFailed
        }
    }

    public func write(_ secrets: Secrets) async throws {
        var encoded = SecretsCodec.encode(secrets)
        defer { wipe(&encoded) }
        try Self.store(encoded)
    }

    public var description: String { "KeychainSecretStore" }

    public var debugDescription: String { description }

    func removeItem() throws {
        let status = SecItemDelete(Self.baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NuumError.secretWriteFailed
        }
    }

    func replaceData(_ data: Data) throws {
        try Self.store(data)
    }

    func currentItem() throws -> KeychainItemRecord? {
        let count = try Self.matchingItemCount()
        guard count > 0 else { return nil }
        let attributes = try Self.copyAttributes()
        return KeychainItemRecord(
            service: attributes.service,
            account: attributes.account,
            accessible: attributes.accessible,
            synchronizable: attributes.synchronizable,
            hasAccessControl: attributes.hasAccessControl,
            isGenericPassword: attributes.isGenericPassword,
            matchingItemCount: count
        )
    }

    private static func copyValue() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = copyMatching(query)
        switch status {
        case errSecSuccess:
            return try materialize(result)
        case errSecItemNotFound:
            return nil
        default:
            throw NuumError.secretReadFailed
        }
    }

    private static func store(_ data: Data) throws {
        var payload = copied(data)
        defer { wipe(&payload) }
        let match = baseQuery()
        let (status, _) = copyMatching(match)
        switch status {
        case errSecSuccess:
            try update(match, data: payload)
        case errSecItemNotFound:
            let added = SecItemAdd(addQuery(payload) as CFDictionary, nil)
            if added == errSecDuplicateItem {
                try update(match, data: payload)
            } else if added != errSecSuccess {
                throw NuumError.secretWriteFailed
            }
        default:
            throw NuumError.secretWriteFailed
        }
    }

    private static func update(_ match: [String: Any], data: Data) throws {
        let changes = [
            kSecValueData as String: data,
        ]
        let status = SecItemUpdate(match as CFDictionary, changes as CFDictionary)
        guard status == errSecSuccess else {
            throw NuumError.secretWriteFailed
        }
    }

    private static func matchingItemCount() throws -> Int {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        let (status, result) = copyMatching(query)
        switch status {
        case errSecItemNotFound:
            return 0
        case errSecSuccess:
            if let items = result as? [Any] {
                return items.count
            }
            if let items = result as? NSArray {
                return items.count
            }
            return result == nil ? 0 : 1
        default:
            throw KeychainItemInspectionError.unavailable
        }
    }

    private static func copyAttributes() throws -> ParsedAttributes {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = copyMatching(query)
        guard status == errSecSuccess else {
            throw KeychainItemInspectionError.unavailable
        }
        guard let dictionary = result as? NSDictionary else {
            throw KeychainItemInspectionError.attributesIncomplete
        }
        guard
            let service = dictionary.object(forKey: kSecAttrService) as? String,
            let account = dictionary.object(forKey: kSecAttrAccount) as? String,
            let accessible = dictionary.object(forKey: kSecAttrAccessible) as? String
        else {
            throw KeychainItemInspectionError.attributesIncomplete
        }
        let synchronizable: Bool
        if dictionary.object(forKey: kSecAttrSynchronizable) == nil {
            synchronizable = false
        } else if let value = boolValue(dictionary.object(forKey: kSecAttrSynchronizable)) {
            synchronizable = value
        } else {
            throw KeychainItemInspectionError.attributesIncomplete
        }
        let itemClass = dictionary.object(forKey: kSecClass) as? String
        let isGenericPassword = itemClass == nil || itemClass == (kSecClassGenericPassword as String)
        return ParsedAttributes(
            service: service,
            account: account,
            accessible: accessible,
            synchronizable: synchronizable,
            hasAccessControl: dictionary.object(forKey: kSecAttrAccessControl) != nil,
            isGenericPassword: isGenericPassword
        )
    }

    private static func materialize(_ result: CFTypeRef?) throws -> Data {
        guard let result, let bridged = result as? Data else {
            throw NuumError.secretReadFailed
        }
        return copied(bridged)
    }

    private static func copied(_ data: Data) -> Data {
        data.withUnsafeBytes { buffer in
            Data(buffer)
        }
    }

    private static func wipe(_ data: inout Data) {
        guard !data.isEmpty else { return }
        data.resetBytes(in: 0..<data.count)
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private static func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainSecretItem.service,
            kSecAttrAccount as String: KeychainSecretItem.account,
            kSecAttrSynchronizable as String: false,
            // Data-protection keychain. Ignored on iOS. Failure still throws 3001.
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private static func addQuery(_ data: Data) -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = data
        return query
    }
}

enum KeychainItemInspectionError: Error, CustomStringConvertible, CustomDebugStringConvertible {
    case unavailable
    case attributesIncomplete

    var description: String { "KeychainItemInspectionError" }
    var debugDescription: String { description }
}

struct KeychainItemRecord: Equatable, Sendable {
    var service: String
    var account: String
    var accessible: String
    var synchronizable: Bool
    var hasAccessControl: Bool
    var isGenericPassword: Bool
    var matchingItemCount: Int
}

private struct ParsedAttributes {
    var service: String
    var account: String
    var accessible: String
    var synchronizable: Bool
    var hasAccessControl: Bool
    var isGenericPassword: Bool
}
#endif
