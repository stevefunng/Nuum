import Foundation

/// `hostname:443` or `hostname:80`. Nothing else.
public func isNetworkTarget(_ value: String) -> Bool {
    wholeMatch(#"^(?:[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?):(?:443|80)$"#, value)
}

public enum ExternalOperationKind: String, Sendable, Equatable, Codable, CaseIterable {
    case read
    case `import`
    case export
    case shell
}

public enum ExternalScope: String, Sendable, Equatable, Codable, CaseIterable {
    case file
    case directory
}

public struct ExternalOperation: WireRepresentable, Sendable, Equatable {
    public var operation: ExternalOperationKind
    public var justification: String
    public var source: String?
    public var destination: String?
    public var resourceRoot: String?
    public var command: String?
    public var cwd: String?
    public var readPaths: [String]
    public var writePaths: [String]
    public var networkTargets: [String]
    public var overwrite: Bool

    public init(
        operation: ExternalOperationKind,
        justification: String,
        source: String? = nil,
        destination: String? = nil,
        resourceRoot: String? = nil,
        command: String? = nil,
        cwd: String? = nil,
        readPaths: [String] = [],
        writePaths: [String] = [],
        networkTargets: [String] = [],
        overwrite: Bool = false
    ) {
        self.operation = operation
        self.justification = justification
        self.source = source
        self.destination = destination
        self.resourceRoot = resourceRoot
        self.command = command
        self.cwd = cwd
        self.readPaths = readPaths
        self.writePaths = writePaths
        self.networkTargets = networkTargets
        self.overwrite = overwrite
    }

    public init(protocolJSON: JSONValue) throws {
        guard let parsed = parseExternalOperation(protocolJSON) else {
            throw ProtocolParseException([], "Invalid external operation")
        }
        self = parsed
    }

    public var protocolJSON: JSONValue { identityJSON }

    var identityJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("operation", operation.rawValue)
        fields.add("justification", justification)
        fields.addIfPresent("source", source)
        fields.addIfPresent("destination", destination)
        fields.addIfPresent("resourceRoot", resourceRoot)
        fields.addIfPresent("command", command)
        fields.addIfPresent("cwd", cwd)
        fields.add("readPaths", .array(readPaths.map(JSONValue.string)))
        fields.add("writePaths", .array(writePaths.map(JSONValue.string)))
        fields.add("networkTargets", .array(networkTargets.map(JSONValue.string)))
        fields.add("overwrite", overwrite)
        return fields.json
    }
}

public enum CommandRule: WireRepresentable, Sendable, Equatable {
    case exact(command: String)
    case prefix(argv: [String])
    case compound(commands: [CommandRule], operators: [String])

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        switch try object.string("kind") {
        case "exact":
            self = .exact(command: try object.string("command"))
        case "prefix":
            self = .prefix(argv: try object.stringArray("argv"))
        case "compound":
            let commands = try object.array("commands").map { try CommandRule(protocolJSON: $0) }
            self = .compound(commands: commands, operators: try object.stringArray("operators"))
        default:
            throw ProtocolParseException(["kind"], "Invalid enum value")
        }
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        switch self {
        case .exact(let command):
            fields.add("kind", "exact")
            fields.add("command", command)
        case .prefix(let argv):
            fields.add("kind", "prefix")
            fields.add("argv", .array(argv.map(JSONValue.string)))
        case .compound(let commands, let operators):
            fields.add("kind", "compound")
            fields.add("commands", .array(commands.map(\.protocolJSON)))
            fields.add("operators", .array(operators.map(JSONValue.string)))
        }
        return fields.json
    }
}

public struct ExternalGrant: WireRepresentable, Sendable, Equatable {
    public var environment: String
    public var workspaceId: String
    public var operation: ExternalOperationKind
    public var readPaths: [String]
    public var writePaths: [String]
    public var overwrite: Bool
    public var scope: ExternalScope?
    public var source: String?
    public var destination: String?
    public var cwd: String?
    public var command: CommandRule?
    public var networkTargets: [String]?
    public var rememberable: Bool?
    public var fingerprints: JSONValue

    public init(
        environment: String,
        workspaceId: String,
        operation: ExternalOperationKind,
        readPaths: [String],
        writePaths: [String],
        overwrite: Bool,
        scope: ExternalScope? = nil,
        source: String? = nil,
        destination: String? = nil,
        cwd: String? = nil,
        command: CommandRule? = nil,
        networkTargets: [String]? = nil,
        rememberable: Bool? = nil,
        fingerprints: JSONValue = .object([])
    ) {
        self.environment = environment
        self.workspaceId = workspaceId
        self.operation = operation
        self.readPaths = readPaths
        self.writePaths = writePaths
        self.overwrite = overwrite
        self.scope = scope
        self.source = source
        self.destination = destination
        self.cwd = cwd
        self.command = command
        self.networkTargets = networkTargets
        self.rememberable = rememberable
        self.fingerprints = fingerprints
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        environment = try object.string("environment")
        workspaceId = try object.string("workspaceId")
        operation = try object.enumeration("operation", as: ExternalOperationKind.self)
        readPaths = try object.stringArray("readPaths")
        writePaths = try object.stringArray("writePaths")
        overwrite = try object.bool("overwrite")
        scope = try object.optionalEnumeration("scope", as: ExternalScope.self)
        source = try object.optionalString("source")
        destination = try object.optionalString("destination")
        cwd = try object.optionalString("cwd")
        if let commandJSON = object.value("command"), !commandJSON.isNull {
            command = try CommandRule(protocolJSON: commandJSON)
        } else {
            command = nil
        }
        if object.contains("networkTargets") {
            networkTargets = try object.stringArray("networkTargets")
        } else {
            networkTargets = nil
        }
        rememberable = try object.optionalBool("rememberable")
        fingerprints = object.value("fingerprints") ?? .object([])
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("environment", environment)
        fields.add("workspaceId", workspaceId)
        fields.add("operation", operation.rawValue)
        fields.add("readPaths", .array(readPaths.map(JSONValue.string)))
        fields.add("writePaths", .array(writePaths.map(JSONValue.string)))
        fields.add("overwrite", overwrite)
        if let scope { fields.add("scope", scope.rawValue) }
        fields.addIfPresent("source", source)
        fields.addIfPresent("destination", destination)
        fields.addIfPresent("cwd", cwd)
        if let command { fields.add("command", command.protocolJSON) }
        if let networkTargets { fields.add("networkTargets", .array(networkTargets.map(JSONValue.string))) }
        fields.addIfPresent("rememberable", rememberable)
        fields.add("fingerprints", fingerprints)
        return fields.json
    }
}

private struct QueryGrammar: Sendable {
    var flags: [String]
    var values: [String: String] = [:]
    var positional: String?
    var required: [String] = []
}

private let positiveCount = #"^[1-9][0-9]{0,3}$"#
private let ghJSON = #"^[a-zA-Z]+(?:,[a-zA-Z]+)*$"#
private let ghRepo = #"^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$"#
private let ghValues = ["--json": ghJSON, "--repo": ghRepo]

private let queryGrammars: [String: QueryGrammar] = [
    "git log": QueryGrammar(
        flags: ["--oneline", "--graph", "--all", "--reverse", "--no-merges", "--first-parent", "--no-decorate"],
        values: ["-n": positiveCount, "--max-count": positiveCount]
    ),
    "git diff": QueryGrammar(
        flags: [
            "--no-ext-diff", "--no-textconv", "--stat", "--name-only", "--name-status",
            "--numstat", "--shortstat", "--cached", "--staged", "--check",
        ],
        required: ["--no-ext-diff", "--no-textconv"]
    ),
    "gh issue view": QueryGrammar(flags: ["--comments"], values: ghValues, positional: #"^[1-9][0-9]*$"#),
    "gh pr list": QueryGrammar(
        flags: [],
        values: ghValues.merging(["--limit": positiveCount, "--state": #"^(open|closed|merged|all)$"#]) { _, new in new }
    ),
    "gh issue list": QueryGrammar(
        flags: [],
        values: ghValues.merging(["--limit": positiveCount, "--state": #"^(open|closed|all)$"#]) { _, new in new }
    ),
    "gh run list": QueryGrammar(flags: [], values: ghValues.merging(["--limit": positiveCount]) { _, new in new }),
    "gh run view": QueryGrammar(flags: ["--verbose"], values: ghValues, positional: #"^[1-9][0-9]*$"#),
]

private let gitStatusWord = #"^(--short|--porcelain(?:=v[12])?|--branch|-s|-b)$"#
private let shellMeta = #"[;&|<>$`\\*?(){}\[\]~]"#
private let doubleQuoteMeta = #"[$`\\]"#

private func queryArgumentsMatch(_ args: [String], _ grammar: QueryGrammar) -> Bool {
    var positionals = 0
    var index = 0
    while index < args.count {
        let arg = args[index]
        if grammar.flags.contains(arg) {
            index += 1
            continue
        }
        let equals = arg.firstIndex(of: "=").map { arg.distance(from: arg.startIndex, to: $0) } ?? -1
        let option = equals > 0 ? String(arg.prefix(equals)) : arg
        if let pattern = grammar.values[option] {
            let value: String
            if equals > 0 {
                value = String(arg.dropFirst(equals + 1))
            } else {
                index += 1
                value = index < args.count ? args[index] : ""
            }
            if !wholeMatch(pattern, value) { return false }
            index += 1
            continue
        }
        if let positional = grammar.positional, wholeMatch(positional, arg), positionals == 0 {
            positionals += 1
            index += 1
            continue
        }
        return false
    }
    let positionalOK = grammar.positional == nil || positionals == 1
    return positionalOK && grammar.required.allSatisfy { args.contains($0) }
}

/// Conservative POSIX words only. No expansion, redirection, pipelines, or control syntax.
public func staticShellWords(_ command: String) -> [String]? {
    var words: [String] = []
    var word = ""
    var quoted: Character?
    var started = false
    for character in command {
        if let quote = quoted {
            if character == quote {
                quoted = nil
                continue
            }
            if quote == "\"", wholeMatch(doubleQuoteMeta, String(character)) { return nil }
            word.append(character)
            continue
        }
        if character == "'" || character == "\"" {
            quoted = character
            started = true
            continue
        }
        if character == "\n" || character == "\r" { return nil }
        if character.isWhitespace {
            if started {
                words.append(word)
                word = ""
                started = false
            }
            continue
        }
        if wholeMatch(shellMeta, String(character)) { return nil }
        word.append(character)
        started = true
    }
    if quoted != nil { return nil }
    if started { words.append(word) }
    return words.isEmpty ? nil : words
}

public struct ShellChain: Sendable, Equatable {
    public var commands: [String]
    public var operators: [String]

    public init(commands: [String], operators: [String]) {
        self.commands = commands
        self.operators = operators
    }
}

/// Linear shell chains only. Preserves operators and rejects dynamic or control syntax.
public func splitShellCommands(_ command: String) -> ShellChain? {
    var commands: [String] = []
    var operators: [String] = []
    var quote: Character?
    var start = command.startIndex
    var index = command.startIndex
    while index < command.endIndex {
        let character = command[index]
        if let current = quote {
            if character == current {
                quote = nil
            } else if current == "\"", wholeMatch(doubleQuoteMeta, String(character)) {
                return nil
            }
            index = command.index(after: index)
            continue
        }
        if character == "'" || character == "\"" {
            quote = character
            index = command.index(after: index)
            continue
        }
        let next = command.index(after: index)
        if character == "&", next >= command.endIndex || command[next] != "&" { return nil }
        if character == ";" || character == "|" || character == "&" {
            let part = command[start..<index].trimmingCharacters(in: .whitespacesAndNewlines)
            if staticShellWords(part) == nil { return nil }
            commands.append(part)
            let doubled = (character == "&" || character == "|") && next < command.endIndex && command[next] == character
            operators.append(doubled ? "\(character)\(character)" : String(character))
            if doubled { index = command.index(after: next) } else { index = next }
            start = index
            continue
        }
        index = command.index(after: index)
    }
    let tail = command[start...].trimmingCharacters(in: .whitespacesAndNewlines)
    if quote != nil || staticShellWords(tail) == nil { return nil }
    commands.append(tail)
    return ShellChain(commands: commands, operators: operators)
}

private func reusablePrefix(_ command: String) -> [String]? {
    guard let words = staticShellWords(command) else { return nil }
    let program = words[0].split(separator: "/").last.map(String.init) ?? words[0]
    let prefixLength = program == "git" ? 2 : 3
    var slots: [String?] = []
    for index in 0..<prefixLength {
        slots.append(index == 0 ? program : (index < words.count ? words[index] : nil))
    }
    let key = slots.map { $0 ?? "" }.joined(separator: " ")
    if let grammar = queryGrammars[key], queryArgumentsMatch(Array(words.dropFirst(prefixLength)), grammar) {
        return slots.compactMap { $0 }
    }
    if program == "git", words.count > 1, words[1] == "status", words.dropFirst(2).allSatisfy({ wholeMatch(gitStatusWord, $0) }) {
        return ["git", "status"]
    }
    if program == "gh", words.count > 2, words[1] == "pr", words[2] == "view" {
        let args = Array(words.dropFirst(3))
        var index = 0
        while index < args.count {
            let value = args[index]
            if wholeMatch(#"^\d+$"#, value) || value == "--comments" {
                index += 1
                continue
            }
            if value == "--json" {
                index += 1
                if index < args.count, wholeMatch(#"^[a-zA-Z,]+$"#, args[index]) {
                    index += 1
                    continue
                }
                return nil
            }
            if value == "--repo" {
                index += 1
                if index < args.count, wholeMatch(ghRepo, args[index]) {
                    index += 1
                    continue
                }
                return nil
            }
            return nil
        }
        return ["gh", "pr", "view"]
    }
    return nil
}

private func atomRule(_ command: String) -> CommandRule {
    if let argv = reusablePrefix(command) {
        return .prefix(argv: argv)
    }
    return .exact(command: command)
}

public func commandRule(_ command: String) -> CommandRule {
    if let chain = splitShellCommands(command), chain.commands.count > 1 {
        return .compound(commands: chain.commands.map(atomRule), operators: chain.operators)
    }
    return atomRule(command)
}

public func commandMatches(_ rule: CommandRule, _ command: String) -> Bool {
    switch rule {
    case .compound(let commands, let operators):
        guard let chain = splitShellCommands(command) else { return false }
        return chain.operators == operators
            && chain.commands.count == commands.count
            && zip(chain.commands, commands).allSatisfy { commandMatches($1, $0) }
    case .exact(let expected):
        return expected == command
    case .prefix(let argv):
        return reusablePrefix(command) == argv
    }
}

public func externalGrantCovers(_ grant: ExternalGrant, _ wanted: ExternalGrant) -> Bool {
    if grant.environment != wanted.environment || grant.workspaceId != wanted.workspaceId || grant.operation != wanted.operation {
        return false
    }
    func contains(_ root: String?, _ value: String?) -> Bool {
        if root == value { return true }
        guard let root, !root.isEmpty, let value else { return false }
        return value.hasPrefix(root + "/")
    }
    if grant.scope == .directory {
        if !contains(grant.source, wanted.source) || !contains(grant.destination, wanted.destination) { return false }
    } else if wanted.scope == .directory || grant.source != wanted.source || grant.destination != wanted.destination {
        return false
    }
    let wantedTargets = wanted.networkTargets ?? []
    let grantTargets = grant.networkTargets ?? []
    if !wantedTargets.allSatisfy({ grantTargets.contains($0) }) { return false }
    if grant.cwd != wanted.cwd || grant.overwrite != wanted.overwrite { return false }
    if grant.readPaths != wanted.readPaths || grant.writePaths != wanted.writePaths { return false }
    if canonicalJSON(grant.fingerprints) != canonicalJSON(wanted.fingerprints) { return false }
    return canonicalJSON(grant.command?.protocolJSON ?? .null) == canonicalJSON(wanted.command?.protocolJSON ?? .null)
}

private let externalOperationKeys: Set<String> = [
    "operation", "justification", "source", "destination", "resourceRoot",
    "command", "cwd", "readPaths", "writePaths", "networkTargets", "overwrite",
]

/// Strict parse. Unknown keys, bad targets, and over-long lists fail closed.
public func parseExternalOperation(_ input: JSONValue) -> ExternalOperation? {
    guard case .object(let pairs) = input else { return nil }
    if pairs.contains(where: { !externalOperationKeys.contains($0.0) }) { return nil }
    let object: JSONObject
    do {
        object = try JSONObject(input)
        guard let operation = ExternalOperationKind(rawValue: try object.string("operation")) else { return nil }
        let justification = try object.string("justification").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !justification.isEmpty, justification.count <= 1000 else { return nil }
        let source = try object.optionalString("source")
        let destination = try object.optionalString("destination")
        let resourceRoot = try object.optionalString("resourceRoot")
        let command = try object.optionalString("command")
        if let command, command.isEmpty { return nil }
        let cwd = try object.optionalString("cwd")
        guard let readPaths = boundedStringList(object, "readPaths", 16) else { return nil }
        guard let writePaths = boundedStringList(object, "writePaths", 16) else { return nil }
        guard let networkTargets = boundedStringList(object, "networkTargets", 16) else { return nil }
        if networkTargets.contains(where: { !isNetworkTarget($0) }) { return nil }
        let overwrite: Bool
        if let raw = object.value("overwrite") {
            if raw.isNull { return nil }
            guard case .bool(let flag) = raw else { return nil }
            overwrite = flag
        } else {
            overwrite = false
        }
        return ExternalOperation(
            operation: operation,
            justification: justification,
            source: source,
            destination: destination,
            resourceRoot: resourceRoot,
            command: command,
            cwd: cwd,
            readPaths: readPaths,
            writePaths: writePaths,
            networkTargets: networkTargets,
            overwrite: overwrite
        )
    } catch {
        return nil
    }
}

private func boundedStringList(_ object: JSONObject, _ key: String, _ max: Int) -> [String]? {
    guard object.contains(key) else { return [] }
    guard let raw = object.value(key), case .array(let values) = raw else { return nil }
    if values.count > max { return nil }
    var strings: [String] = []
    for element in values {
        guard case .string(let value) = element else { return nil }
        strings.append(value)
    }
    return strings
}

/// Request identity excludes model prose and sorts object keys.
/// Changing a justification cannot defeat a refusal.
public func permissionOperationKey(_ name: String, _ input: JSONValue) -> String {
    guard case .object(var pairs) = input else {
        return ProtocolJSON.stringify(.array([.string(name), input]))
    }
    if name == "external_operation", let parsed = parseExternalOperation(input) {
        if case .object(let identity) = parsed.identityJSON {
            pairs = identity
        }
    }
    var mapped = Dictionary(pairs, uniquingKeysWith: { _, last in last })
    if case .string(let command) = mapped["command"] {
        if let words = staticShellWords(command) {
            mapped["command"] = .array(words.map(JSONValue.string))
        } else {
            mapped["command"] = .string(command.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    for key in ["readPaths", "writePaths"] {
        guard case .array(let values) = mapped[key] else { continue }
        let sorted = values.compactMap(\.stringValue).sorted()
        mapped[key] = .array(sorted.map(JSONValue.string))
    }
    let stable = stableJSON(.object(mapped.map { ($0.key, $0.value) }))
    return ProtocolJSON.stringify(.array([.string(name), stable]))
}

private func stableJSON(_ value: JSONValue) -> JSONValue {
    switch value {
    case .array(let values):
        return .array(values.map(stableJSON))
    case .object(let pairs):
        let filtered = pairs.filter { $0.0 != "justification" }.sorted { $0.0 < $1.0 }
        return .object(filtered.map { ($0.0, stableJSON($0.1)) })
    default:
        return value
    }
}

private func canonicalJSON(_ value: JSONValue) -> String {
    ProtocolJSON.stringify(stableJSON(value))
}
