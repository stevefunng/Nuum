package com.nuum.agent

import java.security.MessageDigest

data class CardSession(
    val id: String,
    val workId: String,
    val taskId: String,
    val agentId: String,
    val membershipRevision: Int
)

/** sha256 of the Mac `JSON.stringify([workId, taskId, agentId, membershipRevision])`. */
fun cardSession(workId: String, taskId: String, agentId: String, membershipRevision: Int): CardSession {
    val payload = "[${jsonString(workId)},${jsonString(taskId)},${jsonString(agentId)},$membershipRevision]"
    return CardSession(sha256(payload), workId, taskId, agentId, membershipRevision)
}

fun cardSessionDir(session: CardSession): String {
    val room = sha256(session.workId)
    return "work-sessions/$room/${session.id}"
}

fun sha256(text: String): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
    return digest.joinToString("") { "%02x".format(it) }
}

private fun jsonString(value: String): String =
    buildString {
        append('"')
        for (ch in value) {
            when (ch) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                else -> append(ch)
            }
        }
        append('"')
    }
