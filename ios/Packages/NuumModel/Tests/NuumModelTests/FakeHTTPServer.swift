import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct RecordedHTTPRequest: Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: String

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

struct FakeHTTPResponse: Sendable {
    var status: Int = 200
    var headers: [String: String] = ["Content-Type": "text/event-stream; charset=utf-8"]
    var body: Data = Data()
    var hang: Bool = false

    static func sse(_ events: String...) -> FakeHTTPResponse {
        var payload = ""
        for event in events {
            payload += "data: "
            payload += event
            payload += "\n\n"
        }
        return FakeHTTPResponse(body: Data(payload.utf8))
    }

    static var hang: FakeHTTPResponse {
        FakeHTTPResponse(hang: true)
    }
}

/// Local HTTP/1.1 server. Tests point provider base URLs here and never call a real host.
final class FakeHTTPServer: @unchecked Sendable {
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var clientFDs: [Int32] = []
    private var stopped = false
    private var responses: [FakeHTTPResponse] = []
    private var requests: [RecordedHTTPRequest] = []
    private var hangReleases = 0
    private(set) var port: UInt16 = 0

    var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)/v1")!
    }

    func start() throws {
        #if canImport(Glibc)
        let streamType = Int32(SOCK_STREAM.rawValue)
        #else
        let streamType = SOCK_STREAM
        #endif
        let fd = socket(AF_INET, streamType, 0)
        guard fd >= 0 else { throw FakeHTTPError("socket failed") }
        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        let boundAddress = "127.0.0.1".withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        guard boundAddress == 1 else {
            close(fd)
            throw FakeHTTPError("inet_pton failed")
        }
        let bound = withUnsafePointer(to: &addr) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw FakeHTTPError("bind failed")
        }
        var named = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let namedResult = withUnsafeMutablePointer(to: &named) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard namedResult == 0 else {
            close(fd)
            throw FakeHTTPError("getsockname failed")
        }
        lock.lock()
        listenFD = fd
        port = UInt16(bigEndian: named.sin_port)
        lock.unlock()
        // A detached thread, not the shared queue. URLSession also uses that queue, and
        // parking accept there stalls the handshake long enough for cancellation tests to time out.
        Thread.detachNewThread { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        let listen = listenFD
        listenFD = -1
        let clients = clientFDs
        clientFDs.removeAll()
        lock.unlock()
        if listen >= 0 { close(listen) }
        for client in clients { close(client) }
    }

    func enqueue(_ response: FakeHTTPResponse) {
        lock.lock()
        responses.append(response)
        lock.unlock()
    }

    func takeRequest(timeout: Duration = .seconds(5)) async -> RecordedHTTPRequest? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let request = dequeueRequest() { return request }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    func waitForHangRelease(timeout: Duration = .seconds(3)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if hangReleased() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func dequeueRequest() -> RecordedHTTPRequest? {
        lock.lock()
        defer { lock.unlock() }
        guard !requests.isEmpty else { return nil }
        return requests.removeFirst()
    }

    private func hangReleased() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hangReleases > 0
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let fd = listenFD
            let shouldStop = stopped
            lock.unlock()
            if shouldStop || fd < 0 { return }
            let client = accept(fd, nil, nil)
            if client < 0 { return }
            lock.lock()
            if stopped {
                lock.unlock()
                close(client)
                return
            }
            clientFDs.append(client)
            lock.unlock()
            Thread.detachNewThread { [weak self] in
                self?.handle(client)
            }
        }
    }

    private func handle(_ client: Int32) {
        defer {
            lock.lock()
            clientFDs.removeAll { $0 == client }
            lock.unlock()
            close(client)
        }
        setReceiveTimeout(client, seconds: 5)
        guard let request = readRequest(client) else { return }
        lock.lock()
        requests.append(request.recorded)
        let response = responses.isEmpty
            ? FakeHTTPResponse(status: 500, body: Data("no response queued".utf8))
            : responses.removeFirst()
        lock.unlock()
        if response.hang {
            waitForPeerClose(client)
            lock.lock()
            hangReleases += 1
            lock.unlock()
            return
        }
        writeResponse(client, response)
    }

    private func readRequest(_ client: Int32) -> (recorded: RecordedHTTPRequest, header: String)? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let marker = Data("\r\n\r\n".utf8)
        while data.range(of: marker) == nil && data.count < 1024 * 1024 {
            let capacity = buffer.count
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return read(client, base, capacity)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            data.append(buffer, count: count)
        }
        guard let range = data.range(of: marker) else { return nil }
        let headerData = data.subdata(in: 0..<range.lowerBound)
        var body = data.subdata(in: range.upperBound..<data.count)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon])
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = String(value)
        }
        if headers.contains(where: { $0.key.caseInsensitiveCompare("Expect") == .orderedSame && $0.value.contains("100") }) {
            let cont = Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)
            writeAll(client, cont)
        }
        let length = Int(headers.first { $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame }?.value ?? "") ?? body.count
        while body.count < length {
            let capacity = min(buffer.count, length - body.count)
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return read(client, base, capacity)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                break
            }
            body.append(buffer, count: count)
        }
        if body.count > length { body = body.prefix(length) }
        let recorded = RecordedHTTPRequest(
            method: String(parts[0]),
            path: String(parts[1]),
            headers: headers,
            body: String(data: body, encoding: .utf8) ?? ""
        )
        return (recorded, headerText)
    }

    private func writeResponse(_ client: Int32, _ response: FakeHTTPResponse) {
        let reason: String
        switch response.status {
        case 200: reason = "OK"
        case 401: reason = "Unauthorized"
        default: reason = "Status"
        }
        var header = "HTTP/1.1 \(response.status) \(reason)\r\n"
        var fields = response.headers
        if !fields.keys.contains(where: { $0.caseInsensitiveCompare("Content-Length") == .orderedSame }) {
            fields["Content-Length"] = "\(response.body.count)"
        }
        if !fields.keys.contains(where: { $0.caseInsensitiveCompare("Connection") == .orderedSame }) {
            fields["Connection"] = "close"
        }
        for (name, value) in fields {
            header += "\(name): \(value)\r\n"
        }
        header += "\r\n"
        var bytes = Data(header.utf8)
        bytes.append(response.body)
        writeAll(client, bytes)
    }

    private func waitForPeerClose(_ client: Int32) {
        var buffer = [UInt8](repeating: 0, count: 64)
        for _ in 0..<30 {
            var descriptor = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
            let result = poll(&descriptor, nfds_t(1), 1000)
            if result < 0 {
                if errno == EINTR { continue }
                return
            }
            if result == 0 { continue }
            let capacity = buffer.count
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return read(client, base, capacity)
            }
            if count <= 0 { return }
        }
    }

    private func writeAll(_ client: Int32, _ data: Data) {
        let total = data.count
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < total {
                let count = write(client, base.advanced(by: sent), total - sent)
                if count < 0 {
                    if errno == EINTR { continue }
                    return
                }
                if count == 0 { return }
                sent += count
            }
        }
    }

    private func setReceiveTimeout(_ client: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: time_t(seconds), tv_usec: 0)
        _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
}

private struct FakeHTTPError: Error {
    var message: String
    init(_ message: String) { self.message = message }
}
