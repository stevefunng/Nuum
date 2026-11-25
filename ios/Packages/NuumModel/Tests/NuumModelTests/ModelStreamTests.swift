import Foundation
import NuumContracts
import Testing
@testable import NuumModel

@Test func non200Becomes1004WithoutTheKey() async throws {
    let server = FakeHTTPServer()
    try server.start()
    defer { server.stop() }
    let log = LogCapture()
    server.enqueue(FakeHTTPResponse(
        status: 401,
        headers: ["Content-Type": "application/json"],
        body: Data("{\"error\":\"rejected \(openAIKey)\",\"hint\":\"Authorization: Bearer \(openAIKey)\"}".utf8)
    ))
    let port = providerModel(
        .openai,
        client: testClient { log.append($0) },
        openAIURL: server.baseURL
    )
    do {
        _ = try await collect(port.streamChat(chatRequest(provider: .openai, model: "gpt-4o", apiKey: openAIKey)))
        Issue.record("expected HTTP 401 to fail")
    } catch let error as NuumError {
        #expect(error.code == KernelErrorCode.model)
        #expect(error.code == 1004)
        #expect(error.message.contains("OpenAI HTTP 401"))
        #expect(error.message.contains("[redacted]"))
        #expect(!error.message.contains(openAIKey))
    }
    let text = log.snapshot()
    #expect(!text.contains(openAIKey))
    #expect(!text.lowercased().contains("authorization"))
    #expect(!text.lowercased().contains("x-api-key"))
    let recorded = try #require(await server.takeRequest())
    #expect(recorded.header("Authorization") == "Bearer \(openAIKey)")
}

@Test func missingKeyIs1007AndDoesNotConnect() async throws {
    let server = FakeHTTPServer()
    try server.start()
    defer { server.stop() }
    let client = testClient()
    let started = ContinuousClock.now
    do {
        _ = try await collect(URLSessionModelPort(client: client).streamChat(
            chatRequest(provider: .openai, model: "gpt-4o", apiKey: "")
        ))
        Issue.record("expected a missing key to throw")
    } catch let error as NuumError {
        #expect(error.code == 1007)
        #expect(error.code == KernelErrorCode.invalid)
        #expect(error.message == "API key missing for openai")
    }
    let elapsed = ContinuousClock.now - started
    #expect(elapsed < .seconds(1))
    let recorded = await server.takeRequest(timeout: .milliseconds(200))
    #expect(recorded == nil)
}

@Test func cancelEndsTheTask() async throws {
    let server = FakeHTTPServer()
    try server.start()
    defer { server.stop() }
    server.enqueue(.hang)
    let model = OpenAIModel(client: testClient(), baseURL: server.baseURL, label: openAILabel)
    let stream = model.streamChat(chatRequest(provider: .openai, model: "gpt-4o", apiKey: openAIKey))
    let task = Task { () -> String in
        do {
            for try await _ in stream {}
            return "ended"
        } catch is CancellationError {
            return "ended"
        } catch {
            return "error:\(error)"
        }
    }
    let recorded = try #require(await server.takeRequest())
    #expect(recorded.header("Authorization") == "Bearer \(openAIKey)")

    let clock = ContinuousClock()
    let started = clock.now
    task.cancel()
    let ended = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            _ = await task.value
            return true
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(3))
            return false
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
    #expect(ended)
    #expect(clock.now - started < .seconds(3))
    #expect(await server.waitForHangRelease())
    let outcome = await task.value
    #expect(outcome == "ended")
    #expect(!outcome.contains(openAIKey))
    #expect(!outcome.lowercased().contains("authorization"))
    #expect(!outcome.lowercased().contains("x-api-key"))
}

@Test func selectModelMatchesRouterOrderAndRejectsAMissingKey() throws {
    let deepseek = try selectModel(
        ModelRef(provider: .deepseek, model: "deepseek-reasoner"),
        secrets: Secrets(deepseekApiKey: deepSeekKey)
    )
    #expect(deepseek.apiKey == deepSeekKey)
    let deepseekPort = try #require(deepseek.port as? OpenAIModel)
    #expect(deepseekPort.baseURL == deepSeekBaseURL)
    #expect(deepseekPort.label == deepSeekLabel)

    let openai = try selectModel(
        ModelRef(provider: .openai, model: "gpt-4o"),
        secrets: Secrets(openaiApiKey: openAIKey)
    )
    let openaiPort = try #require(openai.port as? OpenAIModel)
    #expect(openaiPort.baseURL == openAIBaseURL)
    #expect(openaiPort.label == openAILabel)
    #expect(openai.apiKey == openAIKey)

    let anthropic = try selectModel(
        ModelRef(provider: .anthropic, model: "claude-sonnet-4-20250514"),
        secrets: Secrets(anthropicApiKey: anthropicKey)
    )
    let anthropicPort = try #require(anthropic.port as? AnthropicModel)
    #expect(anthropicPort.baseURL == anthropicBaseURL)
    #expect(anthropic.apiKey == anthropicKey)

    do {
        _ = try selectModel(
            ModelRef(provider: .anthropic, model: "claude-sonnet-4-20250514"),
            secrets: Secrets(openaiApiKey: openAIKey, deepseekApiKey: deepSeekKey)
        )
        Issue.record("expected 1007")
    } catch let error as NuumError {
        #expect(error.code == 1007)
        #expect(error.message == "API key missing for anthropic")
        #expect(!error.message.contains(openAIKey))
        #expect(!error.message.contains(deepSeekKey))
    }

    do {
        _ = try selectModel(
            ModelRef(provider: .openai, model: "gpt-4o"),
            secrets: Secrets(openaiApiKey: "")
        )
        Issue.record("expected a blank key to throw")
    } catch let error as NuumError {
        #expect(error.code == 1007)
    }

    #expect(String(describing: deepseek).contains(deepSeekKey) == false)
    #expect(String(reflecting: deepseek).contains(deepSeekKey) == false)
}

@Test func defaultClientUsesTheReadTimeoutAndDoesNotLog() {
    let client = ModelHTTPClient.shared
    #expect(client.requestTimeout == ModelHTTPTimeout.read)
    #expect(client.requestTimeout == 60)
    #expect(ModelHTTPTimeout.connect == 20)
    #expect(ModelHTTPTimeout.write == 60)
    #expect(client.debugLog == nil)
    #expect(ModelHTTPClient.make { _ in }.debugLog != nil)
}

@Test func authHeadersNeverAppearInLogFixtures() async throws {
    let fixture = """
    --> POST https://api.openai.com/v1/chat/completions
    Authorization: Bearer \(openAIKey)
    authorization: Bearer sk-live-openai-lower
    x-api-key: \(anthropicKey)
    X-Api-Key: sk-ant-secret-mixed
    content-type: application/json
    --> END POST
    """
    let redacted = redactLogFixture(fixture)
    #expect(!redacted.lowercased().contains("authorization"))
    #expect(!redacted.lowercased().contains("x-api-key"))
    #expect(!redacted.contains(openAIKey))
    #expect(!redacted.contains(anthropicKey))
    #expect(!redacted.contains("sk-live-openai-lower"))
    #expect(!redacted.contains("sk-ant-secret-mixed"))
    #expect(redacted.contains("content-type: application/json"))
    #expect(redacted.contains("--> POST https://api.openai.com/v1/chat/completions"))

    let server = FakeHTTPServer()
    try server.start()
    defer { server.stop() }
    let log = LogCapture()
    server.enqueue(.sse(#"{"choices":[{"delta":{"content":"hi"}}]}"#, "[DONE]"))
    server.enqueue(.sse(#"{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}"#))
    let client = testClient { log.append($0) }
    let openAI = OpenAIModel(client: client, baseURL: server.baseURL, label: openAILabel)
    let anthropic = AnthropicModel(client: client, baseURL: server.baseURL)
    _ = try await collect(openAI.streamChat(chatRequest(
        provider: .openai,
        model: "gpt-4o",
        apiKey: openAIKey,
        messages: [chatMessage(.user, "UNIQUE_PROMPT_TEXT")]
    )))
    _ = try await collect(anthropic.streamChat(chatRequest(
        provider: .anthropic,
        model: "claude-sonnet-4-20250514",
        apiKey: anthropicKey
    )))

    let text = log.snapshot()
    #expect(!text.lowercased().contains("authorization"))
    #expect(!text.lowercased().contains("x-api-key"))
    #expect(!text.contains(openAIKey))
    #expect(!text.contains(anthropicKey))
    #expect(!text.contains("UNIQUE_PROMPT_TEXT"))
    #expect(text.contains("--> POST"))
    #expect(text.contains("<-- 200"))

    #expect((await server.takeRequest())?.header("Authorization") == "Bearer \(openAIKey)")
    let anthropicRequest = try #require(await server.takeRequest())
    #expect(anthropicRequest.header("x-api-key") == anthropicKey)
    #expect(anthropicRequest.header("Authorization") == nil)
}
