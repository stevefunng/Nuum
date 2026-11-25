import Foundation
@testable import NuumAgent
import NuumContracts

final class ManualClock: Clock, @unchecked Sendable {
    var millis: Int64
    init(_ millis: Int64 = 1_700_000_000_000) { self.millis = millis }
    func nowMillis() -> Int64 { millis }
}

final class MemorySecrets: SecretStore, @unchecked Sendable {
    var current: Secrets
    init(_ current: Secrets = Secrets()) { self.current = current }
    func read() async throws -> Secrets { current }
    func write(_ secrets: Secrets) async throws { current = secrets }
}

final class MemoryAgentStore: AgentStore, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var dirs: Set<String> = [""]

    private func normalize(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).replacingOccurrences(of: "\\", with: "/")
    }

    private func parents(_ path: String) {
        var current = ""
        for part in path.split(separator: "/").dropLast() {
            current = current.isEmpty ? String(part) : "\(current)/\(part)"
            dirs.insert(current)
        }
    }

    func readText(_ relativePath: String) async throws -> String? { readTextSync(relativePath) }
    func writeTextAtomic(_ relativePath: String, text: String) async throws { writeTextSync(relativePath, text) }
    func appendLine(_ relativePath: String, line: String) async throws { appendLineSync(relativePath, line) }
    func readBytes(_ relativePath: String) async throws -> Data? { readBytesSync(relativePath) }
    func writeBytesAtomic(_ relativePath: String, bytes: Data) async throws { writeBytesSync(relativePath, bytes) }

    private func readTextSync(_ relativePath: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = files[normalize(relativePath)] else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func writeTextSync(_ relativePath: String, _ text: String) {
        lock.lock()
        defer { lock.unlock() }
        let path = normalize(relativePath)
        parents(path)
        files[path] = Data(text.utf8)
    }

    private func appendLineSync(_ relativePath: String, _ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let path = normalize(relativePath)
        parents(path)
        let existing = files[path].map { String(decoding: $0, as: UTF8.self) } ?? ""
        let body = existing.isEmpty || existing.hasSuffix("\n") ? existing : String(existing.prefix(upTo: existing.lastIndex(of: "\n") ?? existing.endIndex)) + "\n"
        files[path] = Data((body + line.trimmingCharacters(in: CharacterSet(charactersIn: "\n")) + "\n").utf8)
    }

    private func readBytesSync(_ relativePath: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return files[normalize(relativePath)]
    }

    private func writeBytesSync(_ relativePath: String, _ bytes: Data) {
        lock.lock()
        defer { lock.unlock() }
        let path = normalize(relativePath)
        parents(path)
        files[path] = bytes
    }

    func readTail(_ relativePath: String, maxBytes: Int) async throws -> String {
        let text = try await readText(relativePath) ?? ""
        let bytes = Array(text.utf8)
        if bytes.count <= maxBytes { return text }
        return String(decoding: bytes.suffix(maxBytes), as: UTF8.self)
    }

    func list(_ relativePath: String) async throws -> [String] { listSync(relativePath) }

    private func listSync(_ relativePath: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let prefix = normalize(relativePath)
        if !prefix.isEmpty && !dirs.contains(prefix) && !files.keys.contains(where: { $0 == prefix || $0.hasPrefix("\(prefix)/") }) {
            return []
        }
        let base = prefix.isEmpty ? "" : "\(prefix)/"
        var children = Set<String>()
        for dir in dirs where dir.hasPrefix(base) && dir != prefix {
            children.insert(String(dir.dropFirst(base.count).prefix { $0 != "/" }))
        }
        for file in files.keys where file.hasPrefix(base) {
            children.insert(String(file.dropFirst(base.count).prefix { $0 != "/" }))
        }
        return children.filter { !$0.isEmpty }.sorted()
    }

    func delete(_ relativePath: String) async throws { deleteSync(relativePath) }

    private func deleteSync(_ relativePath: String) {
        lock.lock()
        defer { lock.unlock() }
        let path = normalize(relativePath)
        files.keys.filter { $0 == path || $0.hasPrefix("\(path)/") }.forEach { files.removeValue(forKey: $0) }
        dirs = dirs.filter { $0 != path && !$0.hasPrefix("\(path)/") }
    }

    func exists(_ relativePath: String) async throws -> Bool { existsSync(relativePath) }

    private func existsSync(_ relativePath: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let path = normalize(relativePath)
        return files[path] != nil || dirs.contains(path) || files.keys.contains { $0.hasPrefix("\(path)/") }
    }
}

final class FakeKernel: KernelPort, @unchecked Sendable {
    var summarized: [SummarizeRunParams] = []
    var started: [TurnStartParams] = []
    var results: [TurnToolResult] = []
    var contexts: [TurnContextResult] = []
    var hold: AsyncGate<Void>?
    private let lock = NSLock()
    private var continuation: AsyncStream<KernelEvent>.Continuation?
    let events: AsyncStream<KernelEvent>

    init() {
        var captured: AsyncStream<KernelEvent>.Continuation?
        events = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured
    }

    func start(_ params: TurnStartParams) async throws {
        let gate = recordStart(params)
        if let gate { try await gate.wait() }
    }

    private func recordStart(_ params: TurnStartParams) -> AsyncGate<Void>? {
        lock.lock()
        defer { lock.unlock() }
        started.append(params)
        return hold
    }

    func cancel(runId: String) async throws {}
    func approveTool(_ decision: TurnToolDecision) async throws {}
    func denyTool(_ decision: TurnToolDecision) async throws {}
    func provideContext(_ result: TurnContextResult) async throws { recordContext(result) }
    func provideToolResult(_ result: TurnToolResult) async throws { recordResult(result) }
    func summarize(_ params: SummarizeRunParams) async throws -> SummarizeRunResult {
        recordSummary(params)
        return SummarizeRunResult(text: "compacted")
    }

    private func recordContext(_ result: TurnContextResult) {
        lock.lock()
        contexts.append(result)
        lock.unlock()
    }

    private func recordResult(_ result: TurnToolResult) {
        lock.lock()
        results.append(result)
        lock.unlock()
    }

    private func recordSummary(_ params: SummarizeRunParams) {
        lock.lock()
        summarized.append(params)
        lock.unlock()
    }
    func cancelSummary(runId: String) async throws {}

    func emit(_ event: KernelEvent) {
        continuation?.yield(event)
    }

    func startedSnapshot() -> [TurnStartParams] { copyStarted() }
    func summarizedSnapshot() -> [SummarizeRunParams] { copySummarized() }
    func contextsSnapshot() -> [TurnContextResult] { copyContexts() }

    private func copyStarted() -> [TurnStartParams] {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    private func copySummarized() -> [SummarizeRunParams] {
        lock.lock()
        defer { lock.unlock() }
        return summarized
    }

    private func copyContexts() -> [TurnContextResult] {
        lock.lock()
        defer { lock.unlock() }
        return contexts
    }
}

struct ScopeSupervisor: TurnSupervisor {
    func launch(_ block: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task { await block() }
    }
}

func openRuntime(
    store: any AgentStore = MemoryAgentStore(),
    kernel: any KernelPort = FakeKernel(),
    secrets: any SecretStore = MemorySecrets(Secrets(deepseekApiKey: "sk-test")),
    clock: any Clock = ManualClock(),
    contextWindowTokens: Int = defaultContextWindow,
    osLabel: String = "iOS 26.2"
) -> HostRuntime {
    HostRuntime(
        store: store,
        kernel: kernel,
        secretStore: secrets,
        tools: EmptyTools(),
        clock: clock,
        supervisor: ScopeSupervisor(),
        nuumRoot: "",
        osLabel: osLabel,
        contextWindowTokens: contextWindowTokens
    )
}

func ended(_ runId: String) -> KernelEvent {
    .ended(KernelEndedEvent(runId: runId, status: .idle))
}

struct EmptyTools: ToolBackend {
    func definitions() -> [ToolDefinition] {
        [ToolDefinition(name: "read", description: "read", inputSchema: [:], mutating: false, action: .readFile)]
    }
    func bind(runId: String, roots: ToolRoots, permission: ToolPermission, approvals: [ToolApproval], refused: [ToolApproval]) {}
    func authorize(runId: String, action: LocalToolAction, target: String) async throws -> PermissionVerdict {
        PermissionVerdict(decision: .allow, target: target)
    }
    func grantOnce(runId: String, action: LocalToolAction, target: String) {}
    func refuse(runId: String, action: LocalToolAction, target: String) {}
    func setPermission(runId: String, permission: ToolPermission) {}
    func execute(runId: String, call: ToolCall) async throws -> ToolExecutionResult { ToolExecutionResult(ok: true, output: "") }
    func release(runId: String) {}
}

func waitUntil(_ timeoutMs: Int = 5_000, _ condition: @Sendable () async -> Bool) async {
    let start = Date()
    while await !condition() {
        if Date().timeIntervalSince(start) > Double(timeoutMs) / 1000 { return }
        await Task.yield()
    }
}
