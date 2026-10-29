package com.nuum.agent

import com.nuum.contracts.AgentStore
import com.nuum.contracts.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlin.math.ln
import kotlin.math.max

enum class MemoryTier { PROFILE, LOG, NOTE }

data class MemoryFact(
    val fact: String,
    val tier: MemoryTier,
    val day: String? = null
)

data class ExtractedMemory(
    val writes: List<Pair<String, MemoryTier>>,
    val removals: List<String>
)

/**
 * Markdown memory. `profile.md` is standing facts. `log/YYYY-MM.md` is dated.
 * The files are the only source. There is no memory transcript event.
 */
class MemoryStore(
    private val store: AgentStore,
    private val memoryDir: String,
    private val clock: Clock
) {
    private val profilePath = "$memoryDir/profile.md"

    suspend fun write(fact: String, tier: MemoryTier, nowMillis: Long = clock.nowMillis()): MemoryWrite {
        val text = normalizeMemory(fact)
        if (text.isEmpty()) return MemoryWrite(written = false)
        val existing = all()
        if (existing.any { dedupeKey(it.fact) == dedupeKey(text) }) return MemoryWrite(written = false)
        if (tier == MemoryTier.PROFILE) {
            val standing = existing.count { it.tier == MemoryTier.PROFILE }
            if (standing >= PROFILE_FACT_LIMIT) return MemoryWrite(written = false)
            val lines = readLines(profilePath).toMutableList()
            val body = if (lines.isNotEmpty()) lines else mutableListOf("# Standing facts", "")
            body += "- $text"
            store.writeTextAtomic(profilePath, body.joinToString("\n").trimEnd() + "\n")
            return MemoryWrite(written = true)
        }
        val file = logPath(nowMillis)
        val lines = readLines(file).toMutableList()
        val body = if (lines.isNotEmpty()) {
            lines
        } else {
            mutableListOf("# ${monthKey(nowMillis)}", "", FACTS_HEADING, "", NOTES_HEADING, "")
        }
        val heading = if (tier == MemoryTier.NOTE) NOTES_HEADING else FACTS_HEADING
        val entry = "- ${dayKey(nowMillis)} · $text"
        val at = body.indexOf(heading)
        if (at < 0) {
            body += listOf("", heading, "", entry)
        } else {
            var insert = at + 1
            while (insert < body.size && !body[insert].startsWith("## ")) insert += 1
            body.add(insert, entry)
        }
        store.writeTextAtomic(file, body.joinToString("\n").trimEnd() + "\n")
        return MemoryWrite(written = true)
    }

    suspend fun forget(fact: String): MemoryForget {
        val target = dedupeKey(normalizeMemory(fact))
        if (target.isEmpty()) return MemoryForget(0)
        var removed = 0
        for (file in files()) {
            val lines = readLines(file)
            val kept = lines.filter { line ->
                val parsed = parseLine(line) ?: return@filter true
                if (dedupeKey(parsed.fact) != target) return@filter true
                removed += 1
                false
            }
            if (kept.size != lines.size) {
                store.writeTextAtomic(file, kept.joinToString("\n").trimEnd() + "\n")
            }
        }
        return MemoryForget(removed)
    }

    suspend fun all(): List<MemoryFact> {
        val out = mutableListOf<MemoryFact>()
        for (line in readLines(profilePath)) {
            val parsed = parseLine(line) ?: continue
            out += MemoryFact(parsed.fact, MemoryTier.PROFILE)
        }
        val logDir = "$memoryDir/log"
        if (store.exists(logDir)) {
            for (name in store.list(logDir).filter { MONTH_FILE.matches(it) }.sorted()) {
                var tier = MemoryTier.LOG
                for (line in readLines("$logDir/$name")) {
                    if (line.startsWith("## ")) {
                        tier = if (line.trim() == NOTES_HEADING) MemoryTier.NOTE else MemoryTier.LOG
                        continue
                    }
                    val parsed = parseLine(line) ?: continue
                    out += MemoryFact(parsed.fact, tier, parsed.day)
                }
            }
        }
        return out
    }

    private suspend fun files(): List<String> {
        val months = if (store.exists("$memoryDir/log")) {
            store.list("$memoryDir/log").filter { MONTH_FILE.matches(it) }.sorted()
        } else {
            emptyList()
        }
        return listOf(profilePath) + months.map { "$memoryDir/log/$it" }
    }

    private fun logPath(nowMillis: Long) = "$memoryDir/log/${monthKey(nowMillis)}.md"

    private suspend fun readLines(path: String): List<String> {
        val raw = store.readText(path) ?: return emptyList()
        return raw.split('\n')
    }
}

data class MemoryWrite(val written: Boolean)
data class MemoryForget(val removed: Int)

fun renderMemory(facts: List<MemoryFact>, memoryDir: String, nowMillis: Long): String {
    val standing = facts.filter { it.tier == MemoryTier.PROFILE }.take(PROFILE_FACT_LIMIT)
    val dated = facts.filter { it.tier != MemoryTier.PROFILE }.sortedByDescending { recallRank(it, nowMillis) }
    val kept = mutableListOf<MemoryFact>()
    var budget = RECALL_BUDGET
    for (entry in dated) {
        val cost = entry.fact.length + 16
        if (cost > budget) break
        budget -= cost
        kept += entry
    }
    kept.sortBy { it.day ?: "" }
    val lines = mutableListOf("## Memory", "")
    if (standing.isEmpty() && kept.isEmpty()) {
        lines += "You have not recorded anything about this user yet."
    }
    if (standing.isNotEmpty()) {
        lines += "What you know about this user and your work together:"
        lines += ""
        standing.forEach { lines += "- ${it.fact}" }
        lines += ""
    }
    if (kept.isNotEmpty()) {
        lines += "Recent:"
        lines += ""
        kept.forEach { lines += "- ${it.day} · ${it.fact}" }
        lines += ""
    }
    val hidden = dated.size - kept.size
    if (hidden > 0) {
        lines += "$hidden older entries did not fit here. They are on disk — grep them."
        lines += ""
    }
    lines += "Your memory lives in $memoryDir as Markdown: profile.md for standing"
    lines += "facts, log/YYYY-MM.md for dated ones. Read or grep them directly when you"
    lines += "need more than the above."
    lines += ""
    lines += "Record something with update_state when it will still matter in a later"
    lines += "conversation — a preference, a decision, a name, how this project works."
    lines += "Do not record what you can read off disk again."
    return lines.joinToString("\n").trimEnd()
}

fun recallRank(entry: MemoryFact, nowMillis: Long): Double {
    val importance = if (entry.tier == MemoryTier.NOTE) 1.0 else 2.0
    val ageDays = entry.day?.let { day ->
        val then = Instant.parse("${day}T00:00:00Z").toEpochMilli()
        (nowMillis - then) / 86_400_000.0
    } ?: 0.0
    return ln(importance) / ln(2.0) - max(0.0, ageDays) / HALF_LIFE_DAYS
}

private val SMALL_TALK = setOf(
    "thanks", "thank you", "ok", "okay", "sure", "yes", "no", "got it", "nice", "cool",
    "谢谢", "好的", "好", "行", "嗯", "收到"
)

fun isMemorableExchange(userText: String): Boolean {
    val text = userText.trim()
    if (text.isEmpty()) return false
    val stripped = text.lowercase().replace(Regex("[.!?。！？]+$"), "")
    if (stripped in SMALL_TALK) return false
    return estimateSpeechTokens(text) > 10 || text.contains('?') || text.contains('？')
}

fun estimateSpeechTokens(text: String): Int {
    val cjk = text.count { Character.UnicodeScript.of(it.code) in CJK_SCRIPTS }
    return cjk + ((text.length - cjk) + 3) / 4
}

private val CJK_SCRIPTS = setOf(
    Character.UnicodeScript.HAN,
    Character.UnicodeScript.HIRAGANA,
    Character.UnicodeScript.KATAKANA,
    Character.UnicodeScript.HANGUL
)

const val EXTRACTION_PROMPT = """You extract durable facts from one exchange between a user and their agent.

Emit one line per fact, each prefixed by its tier:

  profile: <a standing fact — a preference, a name, how this project works>
  log: <a dated fact — a decision made, a thing done, a problem found>
  note: <a minor observation worth keeping but not important>
  remove: <a previously recorded fact that this exchange contradicts>

Rules:
- Each line must stand alone. A reader with no other context must understand
  it, so no pronouns pointing outside the line and no 'as discussed'.
- Only what will still matter in a later conversation. Nothing that can be
  read off disk again, nothing about this exchange's mechanics.
- Most exchanges yield nothing. Emitting no lines at all is the common and
  correct answer. Do not pad.
- No preamble, no explanation, no blank lines. Just the prefixed lines."""

fun parseExtraction(raw: String): ExtractedMemory {
    val writes = mutableListOf<Pair<String, MemoryTier>>()
    val removals = mutableListOf<String>()
    val pattern = Regex("""^\s*(profile|log|note|remove)\s*:\s*(.+)$""", RegexOption.IGNORE_CASE)
    for (line in raw.split('\n')) {
        val match = pattern.matchEntire(line) ?: continue
        val kind = match.groupValues[1].lowercase()
        val fact = normalizeMemory(match.groupValues[2])
        if (fact.isEmpty()) continue
        if (kind == "remove") removals += fact
        else writes += fact to when (kind) {
            "profile" -> MemoryTier.PROFILE
            "note" -> MemoryTier.NOTE
            else -> MemoryTier.LOG
        }
    }
    return ExtractedMemory(writes, removals)
}

fun normalizeMemory(fact: String): String =
    fact.replace(Regex("\\s+"), " ")
        .replace(Regex("^[-*•]\\s*"), "")
        .trim()
        .replace(Regex("\\s*[.。]$"), "")

fun dedupeKey(fact: String): String =
    normalizeMemory(fact)
        .lowercase()
        .replace(Regex("[^\\p{L}\\p{N}\\s]"), "")
        .replace(Regex("\\s+"), " ")
        .trim()

private data class ParsedLine(val fact: String, val day: String?)

private fun parseLine(line: String): ParsedLine? {
    val match = Regex("""^\s*-\s+(.*)$""").matchEntire(line) ?: return null
    val body = match.groupValues[1].trim()
    if (body.isEmpty()) return null
    val dated = Regex("""^(\d{4}-\d{2}-\d{2})\s+·\s+(.*)$""").matchEntire(body)
    return if (dated != null) ParsedLine(dated.groupValues[2].trim(), dated.groupValues[1]) else ParsedLine(body, null)
}

private val MONTH_FILE = Regex("""\d{4}-\d{2}\.md""")
private val MONTH = DateTimeFormatter.ofPattern("yyyy-MM").withZone(ZoneOffset.UTC)
private val DAY = DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(ZoneOffset.UTC)

private fun monthKey(millis: Long): String = MONTH.format(Instant.ofEpochMilli(millis))
private fun dayKey(millis: Long): String = DAY.format(Instant.ofEpochMilli(millis))

private const val FACTS_HEADING = "## Facts"
private const val NOTES_HEADING = "## Notes"
