@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

package com.nuum.protocol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive

/** `hostname:443` or `hostname:80`. Nothing else. */
val NETWORK_TARGET = Regex("""^(?:[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?):(?:443|80)$""")

fun isNetworkTarget(value: String): Boolean = NETWORK_TARGET.matches(value)

@Serializable
enum class ExternalOperationKind {
    @SerialName("read") READ,
    @SerialName("import") IMPORT,
    @SerialName("export") EXPORT,
    @SerialName("shell") SHELL
}

@Serializable
enum class ExternalScope {
    @SerialName("file") FILE,
    @SerialName("directory") DIRECTORY
}

@Serializable
data class ExternalOperation(
    val operation: ExternalOperationKind,
    val justification: String,
    val source: String? = null,
    val destination: String? = null,
    val resourceRoot: String? = null,
    val command: String? = null,
    val cwd: String? = null,
    val readPaths: List<String> = emptyList(),
    val writePaths: List<String> = emptyList(),
    val networkTargets: List<String> = emptyList(),
    val overwrite: Boolean = false
)

@Serializable
@kotlinx.serialization.json.JsonClassDiscriminator("kind")
sealed interface CommandRule

@Serializable
@SerialName("exact")
data class ExactCommand(val command: String) : CommandRule

@Serializable
@SerialName("prefix")
data class PrefixCommand(val argv: List<String>) : CommandRule

@Serializable
@SerialName("compound")
data class CompoundCommand(val commands: List<CommandRule>, val operators: List<String>) : CommandRule

@Serializable
data class ExternalGrant(
    val environment: String,
    val workspaceId: String,
    val operation: ExternalOperationKind,
    val readPaths: List<String>,
    val writePaths: List<String>,
    val overwrite: Boolean,
    val scope: ExternalScope? = null,
    val source: String? = null,
    val destination: String? = null,
    val cwd: String? = null,
    val command: CommandRule? = null,
    val networkTargets: List<String>? = null,
    val rememberable: Boolean? = null,
    val fingerprints: JsonObject = JsonObject(emptyMap())
)

private data class QueryGrammar(
    val flags: List<String>,
    val values: Map<String, Regex> = emptyMap(),
    val positional: Regex? = null,
    val required: List<String> = emptyList()
)

private val positiveCount = Regex("""^[1-9][0-9]{0,3}$""")
private val ghJson = Regex("""^[a-zA-Z]+(?:,[a-zA-Z]+)*$""")
private val ghRepo = Regex("""^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$""")
private val ghValues = mapOf("--json" to ghJson, "--repo" to ghRepo)

private val queryGrammars: Map<String, QueryGrammar> = mapOf(
    "git log" to QueryGrammar(
        flags = listOf("--oneline", "--graph", "--all", "--reverse", "--no-merges", "--first-parent", "--no-decorate"),
        values = mapOf("-n" to positiveCount, "--max-count" to positiveCount)
    ),
    "git diff" to QueryGrammar(
        flags = listOf(
            "--no-ext-diff", "--no-textconv", "--stat", "--name-only", "--name-status",
            "--numstat", "--shortstat", "--cached", "--staged", "--check"
        ),
        required = listOf("--no-ext-diff", "--no-textconv")
    ),
    "gh issue view" to QueryGrammar(
        flags = listOf("--comments"),
        values = ghValues,
        positional = Regex("""^[1-9][0-9]*$""")
    ),
    "gh pr list" to QueryGrammar(
        flags = emptyList(),
        values = ghValues + mapOf("--limit" to positiveCount, "--state" to Regex("""^(open|closed|merged|all)$"""))
    ),
    "gh issue list" to QueryGrammar(
        flags = emptyList(),
        values = ghValues + mapOf("--limit" to positiveCount, "--state" to Regex("""^(open|closed|all)$"""))
    ),
    "gh run list" to QueryGrammar(
        flags = emptyList(),
        values = ghValues + mapOf("--limit" to positiveCount)
    ),
    "gh run view" to QueryGrammar(
        flags = listOf("--verbose"),
        values = ghValues,
        positional = Regex("""^[1-9][0-9]*$""")
    )
)

private val gitStatusWord = Regex("""^(--short|--porcelain(?:=v[12])?|--branch|-s|-b)$""")
private val shellMeta = Regex("""[;&|<>$`\\*?(){}\[\]~]""")
private val doubleQuoteMeta = Regex("""[$`\\]""")

private fun queryArgumentsMatch(args: List<String>, grammar: QueryGrammar): Boolean {
    var positionals = 0
    var i = 0
    while (i < args.size) {
        val arg = args[i]
        if (arg in grammar.flags) {
            i++
            continue
        }
        val equals = arg.indexOf('=')
        val option = if (equals > 0) arg.substring(0, equals) else arg
        val pattern = grammar.values[option]
        if (pattern != null) {
            val value = if (equals > 0) arg.substring(equals + 1) else args.getOrNull(++i) ?: ""
            if (!pattern.matches(value)) return false
            i++
            continue
        }
        val positional = grammar.positional
        if (positional != null && positional.matches(arg) && positionals++ == 0) {
            i++
            continue
        }
        return false
    }
    return (grammar.positional == null || positionals == 1) && grammar.required.all { it in args }
}

/** Conservative POSIX words only. No expansion, redirection, pipelines, or control syntax. */
fun staticShellWords(command: String): List<String>? {
    val words = mutableListOf<String>()
    var word = ""
    var quoted: Char? = null
    var started = false
    for (ch in command) {
        if (quoted != null) {
            if (ch == quoted) {
                quoted = null
                continue
            }
            if (quoted == '"' && doubleQuoteMeta.matches(ch.toString())) return null
            word += ch
            continue
        }
        if (ch == '\'' || ch == '"') {
            quoted = ch
            started = true
            continue
        }
        if (ch == '\n' || ch == '\r') return null
        if (ch.isWhitespace()) {
            if (started) {
                words += word
                word = ""
                started = false
            }
            continue
        }
        if (shellMeta.matches(ch.toString())) return null
        word += ch
        started = true
    }
    if (quoted != null) return null
    if (started) words += word
    return words.takeIf { it.isNotEmpty() }
}

data class ShellChain(val commands: List<String>, val operators: List<String>)

/** Linear shell chains only. Preserves operators and rejects dynamic or control syntax. */
fun splitShellCommands(command: String): ShellChain? {
    val commands = mutableListOf<String>()
    val operators = mutableListOf<String>()
    var quote: Char? = null
    var start = 0
    var i = 0
    while (i < command.length) {
        val ch = command[i]
        if (quote != null) {
            if (ch == quote) quote = null
            else if (quote == '"' && doubleQuoteMeta.matches(ch.toString())) return null
            i++
            continue
        }
        if (ch == '\'' || ch == '"') {
            quote = ch
            i++
            continue
        }
        if (ch == '&' && command.getOrNull(i + 1) != '&') return null
        if (ch == ';' || ch == '|' || ch == '&') {
            val part = command.substring(start, i).trim()
            if (staticShellWords(part) == null) return null
            commands += part
            val doubled = (ch == '&' || ch == '|') && command.getOrNull(i + 1) == ch
            operators += if (doubled) "$ch$ch" else ch.toString()
            if (doubled) i++
            start = i + 1
        }
        i++
    }
    val tail = command.substring(start).trim()
    if (quote != null || staticShellWords(tail) == null) return null
    commands += tail
    return ShellChain(commands, operators)
}

private fun reusablePrefix(command: String): List<String>? {
    val words = staticShellWords(command) ?: return null
    val program = words[0].substringAfterLast('/')
    val prefixLen = if (program == "git") 2 else 3
    val slots = List(prefixLen) { index -> if (index == 0) program else words.getOrNull(index) }
    val grammar = queryGrammars[slots.joinToString(" ") { it ?: "" }]
    if (grammar != null && queryArgumentsMatch(words.drop(prefixLen), grammar)) {
        return slots.filterNotNull()
    }
    if (program == "git" && words.getOrNull(1) == "status" && words.drop(2).all { gitStatusWord.matches(it) }) {
        return listOf("git", "status")
    }
    if (program == "gh" && words.getOrNull(1) == "pr" && words.getOrNull(2) == "view") {
        val args = words.drop(3)
        var i = 0
        while (i < args.size) {
            val value = args[i]
            if (Regex("""^\d+$""").matches(value) || value == "--comments") {
                i++
                continue
            }
            if (value == "--json" && Regex("""^[a-zA-Z,]+$""").matches(args.getOrNull(++i) ?: "")) {
                i++
                continue
            }
            if (value == "--repo" && ghRepo.matches(args.getOrNull(++i) ?: "")) {
                i++
                continue
            }
            return null
        }
        return listOf("gh", "pr", "view")
    }
    return null
}

private fun atomRule(command: String): CommandRule {
    val argv = reusablePrefix(command)
    return if (argv != null) PrefixCommand(argv) else ExactCommand(command)
}

fun commandRule(command: String): CommandRule {
    val chain = splitShellCommands(command)
    return if (chain != null && chain.commands.size > 1) {
        CompoundCommand(chain.commands.map { atomRule(it) }, chain.operators)
    } else {
        atomRule(command)
    }
}

fun commandMatches(rule: CommandRule, command: String): Boolean = when (rule) {
    is CompoundCommand -> {
        val chain = splitShellCommands(command)
        chain != null &&
            chain.operators == rule.operators &&
            chain.commands.size == rule.commands.size &&
            chain.commands.indices.all { index -> commandMatches(rule.commands[index], chain.commands[index]) }
    }
    is ExactCommand -> rule.command == command
    is PrefixCommand -> reusablePrefix(command) == rule.argv
}

fun externalGrantCovers(grant: ExternalGrant, wanted: ExternalGrant): Boolean {
    if (grant.environment != wanted.environment || grant.workspaceId != wanted.workspaceId || grant.operation != wanted.operation) {
        return false
    }
    fun contains(root: String?, value: String?): Boolean {
        if (root == value) return true
        if (root.isNullOrEmpty() || value == null) return false
        return value.startsWith("$root/")
    }
    if (grant.scope == ExternalScope.DIRECTORY) {
        if (!contains(grant.source, wanted.source) || !contains(grant.destination, wanted.destination)) return false
    } else if (wanted.scope == ExternalScope.DIRECTORY || grant.source != wanted.source || grant.destination != wanted.destination) {
        return false
    }
    val wantedTargets = wanted.networkTargets.orEmpty()
    val grantTargets = grant.networkTargets.orEmpty()
    if (!wantedTargets.all { it in grantTargets }) return false
    if (grant.cwd != wanted.cwd || grant.overwrite != wanted.overwrite) return false
    if (grant.readPaths != wanted.readPaths || grant.writePaths != wanted.writePaths) return false
    if (grant.fingerprints.toString() != wanted.fingerprints.toString()) return false
    return commandJson(grant.command) == commandJson(wanted.command)
}

private fun commandJson(rule: CommandRule?): String =
    if (rule == null) "null" else ProtocolJson.encodeToString(CommandRule.serializer(), rule)

private val externalOperationKeys = setOf(
    "operation", "justification", "source", "destination", "resourceRoot",
    "command", "cwd", "readPaths", "writePaths", "networkTargets", "overwrite"
)

/** Strict parse. Unknown keys, bad targets, and over-long lists fail closed. */
fun parseExternalOperation(input: JsonObject): ExternalOperation? = try {
    parseExternalOperationOrThrow(input)
} catch (_: InvalidOptional) {
    null
}

private fun parseExternalOperationOrThrow(input: JsonObject): ExternalOperation? {
    if (input.keys.any { it !in externalOperationKeys }) return null
    val operation = operationWires[input.stringOrNull("operation")] ?: return null
    val justification = input.stringOrNull("justification")?.trim() ?: return null
    if (justification.isEmpty() || justification.length > 1000) return null
    val source = input.readOptionalString("source")
    val destination = input.readOptionalString("destination")
    val resourceRoot = input.readOptionalString("resourceRoot")
    val command = input.readOptionalString("command")
    if (command != null && command.isEmpty()) return null
    val cwd = input.readOptionalString("cwd")
    val readPaths = input.stringList("readPaths", 16) ?: return null
    val writePaths = input.stringList("writePaths", 16) ?: return null
    val networkTargets = input.stringList("networkTargets", 16) ?: return null
    if (networkTargets.any { !isNetworkTarget(it) }) return null
    val overwrite = when (val raw = input["overwrite"]) {
        null -> false
        JsonNull -> return null
        is JsonPrimitive -> if (raw.isString) return null else raw.content.toBooleanStrictOrNull() ?: return null
        else -> return null
    }
    return ExternalOperation(
        operation = operation,
        justification = justification,
        source = source,
        destination = destination,
        resourceRoot = resourceRoot,
        command = command,
        cwd = cwd,
        readPaths = readPaths,
        writePaths = writePaths,
        networkTargets = networkTargets,
        overwrite = overwrite
    )
}

/**
 * Request identity excludes model prose and sorts object keys.
 * Changing a justification cannot defeat a refusal.
 */
fun permissionOperationKey(name: String, input: JsonObject): String {
    val normalized = input.toMutableMap()
    if (name == "external_operation") {
        parseExternalOperation(input)?.let { parsed ->
            normalized.clear()
            normalized.putAll(parsed.toIdentityJson())
        }
    }
    val command = normalized["command"]
    if (command is JsonPrimitive && command.isString) {
        val words = staticShellWords(command.content)
        normalized["command"] = if (words != null) {
            JsonArray(words.map { JsonPrimitive(it) })
        } else {
            JsonPrimitive(command.content.trim())
        }
    }
    for (key in listOf("readPaths", "writePaths")) {
        val value = normalized[key] as? JsonArray ?: continue
        val sorted = value.map { it.jsonPrimitive.content }.sorted()
        normalized[key] = JsonArray(sorted.map { JsonPrimitive(it) })
    }
    val encoded = buildJsonArray {
        add(JsonPrimitive(name))
        add(stableJson(JsonObject(normalized)))
    }
    return encoded.toString()
}

private fun ExternalOperation.toIdentityJson(): Map<String, JsonElement> = buildJsonObject {
    put("operation", JsonPrimitive(operationWire(operation)))
    put("justification", JsonPrimitive(justification))
    source?.let { put("source", JsonPrimitive(it)) }
    destination?.let { put("destination", JsonPrimitive(it)) }
    resourceRoot?.let { put("resourceRoot", JsonPrimitive(it)) }
    command?.let { put("command", JsonPrimitive(it)) }
    cwd?.let { put("cwd", JsonPrimitive(it)) }
    put("readPaths", JsonArray(readPaths.map { JsonPrimitive(it) }))
    put("writePaths", JsonArray(writePaths.map { JsonPrimitive(it) }))
    put("networkTargets", JsonArray(networkTargets.map { JsonPrimitive(it) }))
    put("overwrite", JsonPrimitive(overwrite))
}.toMap()

private fun operationWire(kind: ExternalOperationKind): String = when (kind) {
    ExternalOperationKind.READ -> "read"
    ExternalOperationKind.IMPORT -> "import"
    ExternalOperationKind.EXPORT -> "export"
    ExternalOperationKind.SHELL -> "shell"
}

private fun stableJson(value: JsonElement): JsonElement = when (value) {
    is JsonArray -> JsonArray(value.map { stableJson(it) })
    is JsonObject -> JsonObject(
        value.entries
            .filter { it.key != "justification" }
            .sortedBy { it.key }
            .associate { (key, item) -> key to stableJson(item) }
    )
    else -> value
}

private val operationWires = mapOf(
    "read" to ExternalOperationKind.READ,
    "import" to ExternalOperationKind.IMPORT,
    "export" to ExternalOperationKind.EXPORT,
    "shell" to ExternalOperationKind.SHELL
)

private fun JsonObject.stringOrNull(key: String): String? {
    val raw = this[key] as? JsonPrimitive ?: return null
    if (raw is JsonNull || !raw.isString) return null
    return raw.content
}

/**
 * Missing or JSON null → null. A non-string value fails the strict parse.
 */
private fun JsonObject.readOptionalString(key: String): String? {
    if (key !in this || this[key] is JsonNull) return null
    val primitive = this[key] as? JsonPrimitive ?: throw InvalidOptional()
    if (!primitive.isString) throw InvalidOptional()
    return primitive.content
}

private class InvalidOptional : Exception()

private fun JsonObject.stringList(key: String, max: Int): List<String>? {
    if (key !in this) return emptyList()
    val raw = this[key] as? JsonArray ?: return null
    if (raw.size > max) return null
    return raw.map { element ->
        val primitive = element as? JsonPrimitive ?: return null
        if (!primitive.isString) return null
        primitive.content
    }
}
