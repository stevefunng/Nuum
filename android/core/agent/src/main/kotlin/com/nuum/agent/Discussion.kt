package com.nuum.agent

/** A blank reply or `(pass)` spends no public message. */
fun isPass(text: String): Boolean {
    val trimmed = text.trim()
    if (trimmed.isEmpty()) return true
    return PASS.matches(trimmed)
}

fun <T> orderSpeakers(members: List<T>, round: Int): List<T> {
    if (members.isEmpty()) return emptyList()
    val offset = round % members.size
    return members.drop(offset) + members.take(offset)
}

data class MentionedMessage(val body: String, val mentionedAgentIds: List<String>)

data class DiscussionMember(val id: String, val name: String)

fun discussionResponders(
    members: List<DiscussionMember>,
    messages: List<MentionedMessage>,
    defaultAll: Boolean = true
): List<DiscussionMember> {
    val ids = LinkedHashSet<String>()
    for (message in messages) {
        val text = message.body.lowercase()
        if (EVERYONE.containsMatchIn(text)) return members
        message.mentionedAgentIds.forEach { ids += it }
        if (message.mentionedAgentIds.isNotEmpty()) continue
        val aliases = LinkedHashMap<String, MutableList<String>>()
        for (member in members) {
            val name = member.name.trim().lowercase()
            val first = name.split(Regex("\\s+")).firstOrNull().orEmpty()
            for (alias in linkedSetOf(name, name.replace(Regex("\\s+"), ""), first)) {
                if (alias.isEmpty()) continue
                aliases.getOrPut(alias) { mutableListOf() }.add(member.id)
            }
        }
        for ((alias, targets) in aliases) {
            if (!mentioned(text, alias)) continue
            if (targets.size > 1) {
                val full = members.filter { member ->
                    member.id in targets &&
                        member.name.trim().lowercase() != alias &&
                        mentioned(text, member.name.trim().lowercase())
                }
                if (full.size == 1) {
                    ids += full[0].id
                    continue
                }
                throw IllegalArgumentException("Ambiguous @$alias; use the member's full name or select a specific member")
            }
            ids += targets[0]
        }
    }
    if (ids.isEmpty() && defaultAll) return members
    return members.filter { it.id in ids }
}

data class MemberTurn(val messages: Int, val failed: Boolean = false)

/**
 * The room owns this loop only. Each member's turn still goes through [AgentScheduler].
 * Stops after [DiscussionLimits.rounds], [DiscussionLimits.messages], a silent round, or cancellation.
 */
suspend fun runDiscussion(
    current: () -> Boolean,
    responders: suspend () -> List<String>,
    runMember: suspend (agentId: String) -> MemberTurn
) {
    var total = 0
    val failed = mutableSetOf<String>()
    for (round in 0 until discussionLimits.rounds) {
        if (!current()) return
        val order = orderSpeakers(responders().filter { it !in failed }, round)
        var spoken = 0
        for (agentId in order) {
            if (!current() || total >= discussionLimits.messages) return
            val result = runMember(agentId)
            total += result.messages
            spoken += result.messages
            if (result.failed) failed += agentId
        }
        if (spoken == 0) return
    }
}

private fun mentioned(text: String, handle: String): Boolean {
    val needle = "@$handle"
    var at = text.indexOf(needle)
    while (at >= 0) {
        val before = text.getOrNull(at - 1)?.toString() ?: ""
        val after = text.getOrNull(at + needle.length)?.toString() ?: ""
        if (!before.matches(Regex("[a-z0-9]")) && !after.matches(Regex("[a-z0-9]"))) return true
        at = text.indexOf(needle, at + 1)
    }
    return false
}

private val PASS = Regex("""^\(?\s*pass\s*\)?\.?$""", RegexOption.IGNORE_CASE)
private val EVERYONE = Regex("""(?:^|[^a-z0-9])@(everyone|all)\b""")
