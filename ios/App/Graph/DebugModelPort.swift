import Foundation
import NuumContracts
import NuumModel
#if DEBUG
import Synchronization
#endif

/// Production model is `URLSessionModelPort`. The request already carries the key.
/// A fake port exists only in debug builds and stays off unless a launch argument asks for it.
/// There is no settings control, and nothing in this file prints a secret.
enum DebugModelPorts {
    static func select(nuumRoot: String) -> any ModelPort {
        #if DEBUG
        if fakeModelRouterEnabled {
            return AcceptanceRouterModel(nuumRoot: nuumRoot)
        }
        #endif
        return URLSessionModelPort()
    }
}

#if DEBUG
private let fakeModelArgument = "nuum.fakeModel=router"

private var fakeModelRouterEnabled: Bool {
    if ProcessInfo.processInfo.environment["NUUM_FAKE_MODEL"] == "router" { return true }
    return ProcessInfo.processInfo.arguments.contains(fakeModelArgument)
}

/// Debug stand-in used by a later simulator pass. It never reads `apiKey` and never logs the request.
private final class AcceptanceRouterModel: ModelPort, Sendable {
    private let nuumRoot: String
    private let ids = Mutex(0)

    init(nuumRoot: String) {
        self.nuumRoot = nuumRoot
    }

    func streamChat(_ request: NormalizedChatRequest) -> AsyncThrowingStream<NormalizedChunk, Error> {
        let chunks = reply(to: request)
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    private func reply(to request: NormalizedChatRequest) -> [NormalizedChunk] {
        let names = Set(request.tools.map(\.name))
        if names.isEmpty {
            return [.text("summary")]
        }
        if let last = request.messages.last, last.role == .tool {
            if last.name == "SendMessage" || last.name == "CreateTask" { return [] }
            return [send("model saw: \(last.content.prefix(180))")]
        }
        let user = request.messages
            .filter { $0.role == .user }
            .map(\.content)
            .joined(separator: "\n")
        if names.contains("CreateTask") {
            return [tool("CreateTask", [
                "title": .string("Lane card"),
                "description": .string("Created by the acceptance router"),
            ])]
        }
        if user.contains("acceptance-secrets") {
            return [tool("write", [
                "path": .string(joinPath(nuumRoot, SealedSecretFilename.secretsJSON)),
                "content": .string("accepted-note"),
            ])]
        }
        if user.contains("acceptance-write"), names.contains("write") {
            return [tool("write", [
                "path": .string(joinPath(nuumRoot, "outside-scratch.txt")),
                "content": .string("accepted-note"),
            ])]
        }
        return [.text("scratchpad-not-the-body"), send("Visible from SendMessage")]
    }

    private func send(_ content: String) -> NormalizedChunk {
        tool("SendMessage", [
            "type": .string("text"),
            "content": .string(content),
        ])
    }

    private func tool(_ name: String, _ arguments: [String: JSONValue]) -> NormalizedChunk {
        let next = ids.withLock { value in
            value += 1
            return value
        }
        return .toolCall(id: "call-\(next)", name: name, arguments: arguments)
    }
}
#endif
