import Foundation
import NuumContracts
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Android `ModelHttp` budgets.
/// `URLSession` has one idle timer (`timeoutIntervalForRequest`). It is the 60s read budget
/// and also covers a stalled upload. A separate 20s timer until response headers would cancel
/// a normal time-to-first-token, so the connect figure stays as the named budget and is not
/// applied as a pre-header deadline.
public enum ModelHTTPTimeout {
    public static let connect: TimeInterval = 20
    public static let read: TimeInterval = 60
    public static let write: TimeInterval = 60
    public static let resource: TimeInterval = 60 * 60
}

public let openAIBaseURL = URL(string: "https://api.openai.com/v1")!
public let deepSeekBaseURL = URL(string: "https://api.deepseek.com/v1")!
public let anthropicBaseURL = URL(string: "https://api.anthropic.com/v1")!
public let openAILabel = "OpenAI"
public let deepSeekLabel = "DeepSeek"
public let anthropicLabel = "Anthropic"
public let anthropicVersion = "2023-06-01"

let maxErrorBodyCharacters = 4_096

struct HTTPRequestParts: Sendable {
    var url: URL
    var headers: [(String, String)]
    var body: Data
}

func endpoint(_ base: URL, _ path: String) -> URL? {
    var text = base.absoluteString
    while text.hasSuffix("/") { text.removeLast() }
    return URL(string: text + path)
}

func headerIsSensitive(_ name: String) -> Bool {
    let lower = name.lowercased()
    return lower == "authorization" || lower == "x-api-key"
}

/// Drops `Authorization` and `x-api-key` lines. The header name and the key value both go.
public func redactLogFixture(_ raw: String) -> String {
    raw.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { line in
            let name = line.split(separator: ":", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            return !headerIsSensitive(String(name))
        }
        .joined(separator: "\n")
}

func scrubSecrets(_ text: String, secrets: [String]) -> String {
    var scrubbed = text
    for secret in secrets where !secret.isEmpty {
        scrubbed = scrubbed.replacingOccurrences(of: secret, with: "[redacted]")
    }
    return scrubbed
}

func formatExchange(start: String, headers: [(String, String)], end: String) -> String {
    var raw = start + "\n"
    for (name, value) in headers {
        raw += name
        raw += ": "
        raw += value
        raw += "\n"
    }
    raw += end
    return redactLogFixture(raw)
}

enum HTTPEvent: Sendable {
    case response(status: Int, headers: [(String, String)])
    case data(Data)
}

/// One `URLSession` plus the delegate that reads SSE bytes.
/// Release builds pass no `debugLog`. The logger never receives the request body.
public final class ModelHTTPClient: @unchecked Sendable {
    public let debugLog: (@Sendable (String) -> Void)?
    public let requestTimeout: TimeInterval
    let session: URLSession
    private let bridge: SessionBridge

    public static let shared: ModelHTTPClient = .make()

    public static func make(
        debugLog: (@Sendable (String) -> Void)? = nil,
        requestTimeout: TimeInterval = ModelHTTPTimeout.read,
        resourceTimeout: TimeInterval = ModelHTTPTimeout.resource
    ) -> ModelHTTPClient {
        let bridge = SessionBridge()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = nil
        let session = URLSession(configuration: configuration, delegate: bridge, delegateQueue: nil)
        return ModelHTTPClient(session: session, bridge: bridge, debugLog: debugLog, requestTimeout: requestTimeout)
    }

    private init(
        session: URLSession,
        bridge: SessionBridge,
        debugLog: (@Sendable (String) -> Void)?,
        requestTimeout: TimeInterval
    ) {
        self.session = session
        self.bridge = bridge
        self.debugLog = debugLog
        self.requestTimeout = requestTimeout
    }

    func dataTask(for parts: HTTPRequestParts) -> HTTPCall {
        var request = URLRequest(url: parts.url)
        request.httpMethod = "POST"
        request.httpBody = parts.body
        for (name, value) in parts.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if debugLog != nil {
            let logged = formatExchange(
                start: "--> POST \(parts.url.absoluteString)",
                headers: parts.headers,
                end: "--> END POST"
            )
            debugLog?(logged)
        }
        let handler = HTTPEventHandler()
        let task = session.dataTask(with: request)
        bridge.register(task.taskIdentifier, handler: handler)
        let events = AsyncThrowingStream<HTTPEvent, Error> { continuation in
            handler.attach(continuation)
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
        let call = HTTPCall(task: task, events: events)
        task.resume()
        return call
    }
}

final class HTTPCall: @unchecked Sendable {
    let events: AsyncThrowingStream<HTTPEvent, Error>
    private let task: URLSessionDataTask

    init(task: URLSessionDataTask, events: AsyncThrowingStream<HTTPEvent, Error>) {
        self.task = task
        self.events = events
    }

    func cancel() {
        task.cancel()
    }
}

private final class SessionBridge: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [Int: HTTPEventHandler] = [:]

    func register(_ identifier: Int, handler: HTTPEventHandler) {
        lock.lock()
        handlers[identifier] = handler
        lock.unlock()
    }

    private func handler(_ task: URLSessionTask) -> HTTPEventHandler? {
        lock.lock()
        let handler = handlers[task.taskIdentifier]
        lock.unlock()
        return handler
    }

    private func remove(_ task: URLSessionTask) {
        lock.lock()
        handlers[task.taskIdentifier] = nil
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? -1
        var headers: [(String, String)] = []
        if let fields = http?.allHeaderFields {
            for (key, value) in fields {
                let name = (key as? String) ?? String(describing: key)
                let text = (value as? String) ?? String(describing: value)
                headers.append((name, text))
            }
        }
        handler(dataTask)?.emit(.response(status: status, headers: headers))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handler(dataTask)?.emit(.data(data))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let handler = handler(task)
        remove(task)
        if let error, !isCancellation(error) {
            handler?.finish(throwing: error)
        } else {
            handler?.finish(throwing: nil)
        }
    }
}

private final class HTTPEventHandler: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<HTTPEvent, Error>.Continuation?
    private var pending: [HTTPEvent] = []
    private var finished = false
    private var storedError: Error?

    func attach(_ continuation: AsyncThrowingStream<HTTPEvent, Error>.Continuation) {
        lock.lock()
        self.continuation = continuation
        let queued = pending
        pending.removeAll()
        let finished = self.finished
        let storedError = self.storedError
        lock.unlock()
        for event in queued {
            continuation.yield(event)
        }
        if finished {
            if let storedError {
                continuation.finish(throwing: storedError)
            } else {
                continuation.finish()
            }
        }
    }

    func emit(_ event: HTTPEvent) {
        lock.lock()
        let continuation = self.continuation
        let finished = self.finished
        if continuation == nil && !finished {
            pending.append(event)
        }
        lock.unlock()
        guard !finished else { return }
        continuation?.yield(event)
    }

    func finish(throwing error: Error?) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        storedError = error
        let continuation = self.continuation
        lock.unlock()
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
    }
}

struct SSELineBuffer {
    private var pending = Data()

    mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            var line = pending.prefix(upTo: newline)
            pending.removeSubrange(...newline)
            if line.last == 0x0D { line = line.dropLast() }
            lines.append(String(decoding: line, as: UTF8.self))
        }
        return lines
    }

    mutating func finish() -> [String] {
        guard !pending.isEmpty else { return [] }
        var line = pending[...]
        pending.removeAll()
        if line.last == 0x0D { line = line.dropLast() }
        if line.isEmpty { return [] }
        return [String(decoding: line, as: UTF8.self)]
    }
}

func sseData(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("data:") else { return nil }
    return String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
}

func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let urlError = error as? URLError
    return urlError?.code == .cancelled
}

/// Shared POST + SSE driver. Cancellation of the consuming task cancels the `URLSessionTask`.
func streamSSE(
    client: ModelHTTPClient,
    apiKey: String,
    providerWire: String,
    label: String,
    parts: HTTPRequestParts,
    onLine: @escaping @Sendable (String) throws -> [NormalizedChunk],
    onFinish: @escaping @Sendable () throws -> [NormalizedChunk]
) -> AsyncThrowingStream<NormalizedChunk, Error> {
    let callBox = HTTPCallBox()
    return AsyncThrowingStream { continuation in
        let producer = Task {
            var call: HTTPCall?
            do {
                if apiKey.isEmpty {
                    throw NuumError(
                        code: KernelErrorCode.invalid,
                        message: "API key missing for \(providerWire)"
                    )
                }
                try Task.checkCancellation()
                let started = client.dataTask(for: parts)
                call = started
                callBox.set(started)
                try Task.checkCancellation()
                var buffer = SSELineBuffer()
                var status: Int?
                var errorBody = Data()
                for try await event in started.events {
                    try Task.checkCancellation()
                    switch event {
                    case .response(let code, let headers):
                        status = code
                        if let log = client.debugLog {
                            log(formatExchange(
                                start: "<-- \(code) \(parts.url.absoluteString)",
                                headers: headers,
                                end: "<-- END HTTP"
                            ))
                        }
                    case .data(let data):
                        let code = status ?? -1
                        if !(200..<300).contains(code) {
                            if errorBody.count < maxErrorBodyCharacters * 4 {
                                let room = maxErrorBodyCharacters * 4 - errorBody.count
                                errorBody.append(data.prefix(room))
                            }
                            continue
                        }
                        for line in buffer.append(data) {
                            for chunk in try onLine(line) {
                                continuation.yield(chunk)
                            }
                        }
                    }
                }
                try Task.checkCancellation()
                guard let status else {
                    throw NuumError(code: KernelErrorCode.model, message: "\(label) connection failed")
                }
                if !(200..<300).contains(status) {
                    let text = String(decoding: errorBody, as: UTF8.self)
                    let scrubbed = scrubSecrets(text, secrets: [apiKey])
                    let clipped = String(scrubbed.prefix(maxErrorBodyCharacters))
                    throw NuumError(
                        code: KernelErrorCode.model,
                        message: "\(label) HTTP \(status): \(clipped)"
                    )
                }
                for line in buffer.finish() {
                    for chunk in try onLine(line) {
                        continuation.yield(chunk)
                    }
                }
                for chunk in try onFinish() {
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch is CancellationError {
                call?.cancel()
                continuation.finish()
            } catch let error where isCancellation(error) {
                call?.cancel()
                continuation.finish()
            } catch let error as NuumError {
                continuation.finish(throwing: error)
            } catch {
                continuation.finish(throwing: NuumError(
                    code: KernelErrorCode.model,
                    message: "\(label) connection failed"
                ))
            }
        }
        continuation.onTermination = { @Sendable _ in
            producer.cancel()
            callBox.cancel()
        }
    }
}

private final class HTTPCallBox: @unchecked Sendable {
    private let lock = NSLock()
    private var call: HTTPCall?

    func set(_ call: HTTPCall) {
        lock.lock()
        self.call = call
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let call = self.call
        lock.unlock()
        call?.cancel()
    }
}

func allowedImages(_ images: [ModelImage]?) -> [ModelImage] {
    (images ?? []).filter { imageMIMETypes.contains($0.mimeType.lowercased()) }
}
