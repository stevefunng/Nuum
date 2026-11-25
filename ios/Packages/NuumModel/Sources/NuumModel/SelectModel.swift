import Foundation
import NuumContracts

/// `selectModel` result. Description and debug description do not include the key.
public struct SelectedModel: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let port: any ModelPort
    public let apiKey: String

    public init(port: any ModelPort, apiKey: String) {
        self.port = port
        self.apiKey = apiKey
    }

    public var description: String {
        "SelectedModel(apiKey: <redacted>)"
    }

    public var debugDescription: String { description }
}

public func secretForProvider(_ secrets: Secrets, _ provider: ProviderId) -> String? {
    switch provider {
    case .openai:
        secrets.openaiApiKey
    case .anthropic:
        secrets.anthropicApiKey
    case .deepseek:
        secrets.deepseekApiKey
    }
}

/// Same choice as `packages/kernel/src/model/router.ts`.
/// The selected provider's key is required. An empty string is not a key.
/// Missing key throws `KernelErrorCode.invalid` (1007) and does not fall through to another provider.
/// Host fallback `deepseek → openai → anthropic` is `providerFallback` in NuumContracts, not this function.
public func selectModel(
    _ model: ModelRef,
    secrets: Secrets,
    client: ModelHTTPClient = .shared
) throws -> SelectedModel {
    guard let apiKey = secretForProvider(secrets, model.provider), !apiKey.isEmpty else {
        throw NuumError(
            code: KernelErrorCode.invalid,
            message: "API key missing for \(model.provider.rawValue)"
        )
    }
    return SelectedModel(port: providerModel(model.provider, client: client), apiKey: apiKey)
}

/// Composition-root `ModelPort`. The request already carries the key.
/// An empty key throws 1007 before a socket is opened.
public struct URLSessionModelPort: ModelPort {
    public let client: ModelHTTPClient

    public init(client: ModelHTTPClient = .shared) {
        self.client = client
    }

    public func streamChat(_ request: NormalizedChatRequest) -> AsyncThrowingStream<NormalizedChunk, Error> {
        providerModel(request.model.provider, client: client).streamChat(request)
    }
}

func providerModel(
    _ provider: ProviderId,
    client: ModelHTTPClient,
    openAIURL: URL = openAIBaseURL,
    deepSeekURL: URL = deepSeekBaseURL,
    anthropicURL: URL = anthropicBaseURL
) -> any ModelPort {
    switch provider {
    case .anthropic:
        AnthropicModel(client: client, baseURL: anthropicURL)
    case .deepseek:
        OpenAIModel(client: client, baseURL: deepSeekURL, label: deepSeekLabel)
    case .openai:
        OpenAIModel(client: client, baseURL: openAIURL, label: openAILabel)
    }
}
