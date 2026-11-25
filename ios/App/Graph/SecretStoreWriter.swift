import NuumContracts

/// Settings-page writer. Reads the Keychain record, replaces one provider, and writes it back.
/// An empty string or nil deletes that provider's key. This type has no read method.
/// `description` does not include key material, and nothing here is handed back to the settings UI.
final class SecretStoreWriter: SecretWriter, CustomStringConvertible, CustomDebugStringConvertible, @unchecked Sendable {
    private let store: any SecretStore
    private let gate = WriteGate()

    init(store: any SecretStore) {
        self.store = store
    }

    func write(provider: ProviderId, apiKey: String?) async throws {
        let store = self.store
        let replacement = blankToNil(apiKey)
        try await gate.exclusive {
            let current = try await store.read()
            try await store.write(replacing(current, provider: provider, apiKey: replacement))
        }
    }

    var description: String { "SecretStoreWriter" }

    var debugDescription: String { description }
}

private actor WriteGate {
    func exclusive(_ body: @Sendable () async throws -> Void) async rethrows {
        try await body()
    }
}

private func blankToNil(_ apiKey: String?) -> String? {
    guard let apiKey, !apiKey.isEmpty else { return nil }
    return apiKey
}

private func replacing(_ secrets: Secrets, provider: ProviderId, apiKey: String?) -> Secrets {
    switch provider {
    case .openai:
        Secrets(openaiApiKey: apiKey, anthropicApiKey: secrets.anthropicApiKey, deepseekApiKey: secrets.deepseekApiKey)
    case .anthropic:
        Secrets(openaiApiKey: secrets.openaiApiKey, anthropicApiKey: apiKey, deepseekApiKey: secrets.deepseekApiKey)
    case .deepseek:
        Secrets(openaiApiKey: secrets.openaiApiKey, anthropicApiKey: secrets.anthropicApiKey, deepseekApiKey: apiKey)
    }
}
