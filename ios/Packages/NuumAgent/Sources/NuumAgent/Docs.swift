import Foundation
import NuumContracts
import NuumProtocol

func readDoc<T: WireRepresentable>(_ store: any AgentStore, _ path: String, as type: T.Type) async throws -> T? {
    guard let text = try await store.readText(path)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
        return nil
    }
    return try? ProtocolJSON.decode(type, from: text)
}

func writeDoc<T: WireRepresentable>(_ store: any AgentStore, _ path: String, _ value: T) async throws {
    try await store.writeTextAtomic(path, text: ProtocolJSON.encode(value) + "\n")
}

func readTranscript(_ store: any AgentStore, _ path: String) async throws -> [NuumProtocol.TranscriptEvent] {
    guard let raw = try await store.readText(path) else { return [] }
    let committed: String
    if raw.hasSuffix("\n") {
        committed = raw
    } else if let newline = raw.lastIndex(of: "\n") {
        committed = String(raw[..<raw.index(after: newline)])
    } else {
        return []
    }
    if committed.isEmpty { return [] }
    return committed.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
        let text = String(line)
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        return tryParseTranscriptLine(text)
    }
}

func appendTranscriptLine(_ store: any AgentStore, _ path: String, _ event: NuumProtocol.TranscriptEvent) async throws {
    try await store.appendLine(path, line: ProtocolJSON.encode(event))
}

func readWorkEvents(_ store: any AgentStore, _ path: String) async throws -> [NuumProtocol.WorkEvent] {
    guard let raw = try await store.readText(path) else { return [] }
    let committed: String
    if raw.hasSuffix("\n") {
        committed = raw
    } else if let newline = raw.lastIndex(of: "\n") {
        committed = String(raw[..<raw.index(after: newline)])
    } else {
        return []
    }
    if committed.isEmpty { return [] }
    return committed.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
        let text = String(line)
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        return try? ProtocolJSON.decode(NuumProtocol.WorkEvent.self, from: text)
    }
}

func appendWorkLine(_ store: any AgentStore, _ path: String, _ event: NuumProtocol.WorkEvent) async throws {
    try await store.appendLine(path, line: ProtocolJSON.encode(event))
}

func readReceipts(_ store: any AgentStore, _ path: String) async throws -> [ExecutionReceipt] {
    guard let text = try await store.readText(path)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
        return []
    }
    guard let value = try? ProtocolJSON.parse(text), case .array(let items) = value else { return [] }
    return items.compactMap { try? ExecutionReceipt(protocolJSON: $0) }
}

struct ReadCursor: WireRepresentable, Sendable, Equatable {
    var seq: Int

    init(seq: Int) { self.seq = seq }

    init(protocolJSON: NuumProtocol.JSONValue) throws {
        seq = try requireInt(protocolJSON, "seq")
    }

    var protocolJSON: NuumProtocol.JSONValue {
        var fields = JSONFieldList()
        fields.add("seq", seq)
        return fields.json
    }
}

struct ApprovalFile: WireRepresentable, Sendable, Equatable {
    var always: [NuumProtocol.ToolApproval]
    var refused: [NuumProtocol.ToolApproval]

    init(always: [NuumProtocol.ToolApproval] = [], refused: [NuumProtocol.ToolApproval] = []) {
        self.always = always
        self.refused = refused
    }

    init(protocolJSON: NuumProtocol.JSONValue) throws {
        always = try fieldArray(protocolJSON, "always").map { try NuumProtocol.ToolApproval(protocolJSON: $0) }
        refused = try fieldArray(protocolJSON, "refused").map { try NuumProtocol.ToolApproval(protocolJSON: $0) }
    }

    var protocolJSON: NuumProtocol.JSONValue {
        var fields = JSONFieldList()
        fields.add("always", .array(always.map(\.protocolJSON)))
        fields.add("refused", .array(refused.map(\.protocolJSON)))
        return fields.json
    }
}

struct PromptCache: WireRepresentable, Sendable, Equatable {
    var epoch: Int
    var profileRender: String?
    var identityName: String?
    var identityDescription: String?
    var identityTags: [String]
    var memory: String?

    init(
        epoch: Int = 0,
        profileRender: String? = nil,
        identityName: String? = nil,
        identityDescription: String? = nil,
        identityTags: [String] = [],
        memory: String? = nil
    ) {
        self.epoch = epoch
        self.profileRender = profileRender
        self.identityName = identityName
        self.identityDescription = identityDescription
        self.identityTags = identityTags
        self.memory = memory
    }

    init(protocolJSON: NuumProtocol.JSONValue) throws {
        epoch = optionalInt(protocolJSON, "epoch") ?? 0
        profileRender = optionalString(protocolJSON, "profileRender")
        identityName = optionalString(protocolJSON, "identityName")
        identityDescription = optionalString(protocolJSON, "identityDescription")
        identityTags = optionalStringArray(protocolJSON, "identityTags") ?? []
        memory = optionalString(protocolJSON, "memory")
    }

    var protocolJSON: NuumProtocol.JSONValue {
        var fields = JSONFieldList()
        fields.add("epoch", epoch)
        fields.addIfPresent("profileRender", profileRender)
        fields.addIfPresent("identityName", identityName)
        fields.addIfPresent("identityDescription", identityDescription)
        if !identityTags.isEmpty {
            fields.add("identityTags", .array(identityTags.map(NuumProtocol.JSONValue.string)))
        }
        fields.addIfPresent("memory", memory)
        return fields.json
    }
}

/// A finished tool result that was written before the transcript line.
struct ExecutionReceipt: WireRepresentable, Sendable, Equatable {
    var requestId: String
    var runId: String
    var name: String
    var arguments: NuumProtocol.JSONValue
    var ok: Bool
    var output: String

    init(requestId: String, runId: String, name: String, arguments: NuumProtocol.JSONValue = .object([]), ok: Bool, output: String) {
        self.requestId = requestId
        self.runId = runId
        self.name = name
        self.arguments = arguments
        self.ok = ok
        self.output = output
    }

    init(protocolJSON: NuumProtocol.JSONValue) throws {
        requestId = try requireString(protocolJSON, "requestId")
        runId = try requireString(protocolJSON, "runId")
        name = try requireString(protocolJSON, "name")
        arguments = field(protocolJSON, "arguments") ?? .object([])
        ok = try requireBool(protocolJSON, "ok")
        output = try requireString(protocolJSON, "output")
    }

    var protocolJSON: NuumProtocol.JSONValue {
        var fields = JSONFieldList()
        fields.add("requestId", requestId)
        fields.add("runId", runId)
        fields.add("name", name)
        fields.add("arguments", arguments)
        fields.add("ok", ok)
        fields.add("output", output)
        return fields.json
    }
}

struct DocParseError: Error {}

func field(_ value: NuumProtocol.JSONValue, _ key: String) -> NuumProtocol.JSONValue? {
    value.objectPairs?.first { $0.0 == key }?.1
}

func requireString(_ value: NuumProtocol.JSONValue, _ key: String) throws -> String {
    guard let text = field(value, key)?.stringValue else { throw DocParseError() }
    return text
}

func optionalString(_ value: NuumProtocol.JSONValue, _ key: String) -> String? {
    guard let raw = field(value, key), !raw.isNull else { return nil }
    return raw.stringValue
}

func requireInt(_ value: NuumProtocol.JSONValue, _ key: String) throws -> Int {
    guard let number = field(value, key)?.intValue else { throw DocParseError() }
    return Int(number)
}

func optionalInt(_ value: NuumProtocol.JSONValue, _ key: String) -> Int? {
    field(value, key)?.intValue.map { Int($0) }
}

func requireBool(_ value: NuumProtocol.JSONValue, _ key: String) throws -> Bool {
    guard let flag = field(value, key)?.boolValue else { throw DocParseError() }
    return flag
}

func fieldArray(_ value: NuumProtocol.JSONValue, _ key: String) -> [NuumProtocol.JSONValue] {
    field(value, key)?.arrayValues ?? []
}

func optionalStringArray(_ value: NuumProtocol.JSONValue, _ key: String) -> [String]? {
    guard let raw = field(value, key) else { return nil }
    return raw.arrayValues?.compactMap(\.stringValue)
}
