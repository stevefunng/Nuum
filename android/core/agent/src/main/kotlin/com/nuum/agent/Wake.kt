package com.nuum.agent

import com.nuum.protocol.TranscriptEvent
import com.nuum.protocol.WakeSource

data class QueuedWake(
    val fromId: String,
    val fromName: String,
    val text: String,
    val hops: Int
)

/**
 * The queue is memory only. A wake already lives in the recipient transcript.
 * After a restart, [pendingWake] finds one that never received a reply.
 * Cold start queues that wake and does not mark the agent running.
 */
class WakeQueue(
    private val now: () -> Long = { System.currentTimeMillis() }
) {
    private val queued = LinkedHashMap<String, ArrayDeque<QueuedWake>>()
    private val rate = HashMap<String, ArrayDeque<Long>>()
    private val creates = HashMap<String, Int>()

    fun check(fromId: String, toId: String, hops: Int): WakeVerdict {
        if (fromId == toId) {
            return WakeVerdict.Refused("That is you. Do the work yourself instead of messaging yourself.")
        }
        if (hops > MAX_HOPS) {
            return WakeVerdict.Refused(
                "Refused: this message is already ${hops - 1} agents away from the user. Answer it yourself instead of passing it on."
            )
        }
        val key = "$fromId>$toId"
        val recent = rate.getOrPut(key) { ArrayDeque() }
        val cutoff = now() - WAKE_RATE_WINDOW_MS
        while (recent.isNotEmpty() && recent.first() < cutoff) recent.removeFirst()
        if (recent.size >= WAKE_RATE_LIMIT) {
            return WakeVerdict.Refused(
                "Refused: you have already sent $WAKE_RATE_LIMIT messages to that agent this minute. Wait for it to answer."
            )
        }
        recent.addLast(now())
        return WakeVerdict.Allowed
    }

    fun enqueue(toId: String, wake: QueuedWake) {
        queued.getOrPut(toId) { ArrayDeque() }.addLast(wake)
    }

    fun dequeue(toId: String): QueuedWake? {
        val queue = queued[toId] ?: return null
        if (queue.isEmpty()) return null
        val next = queue.removeFirst()
        if (queue.isEmpty()) queued.remove(toId)
        return next
    }

    fun drop(toId: String): Int {
        val dropped = queued[toId]?.size ?: 0
        queued.remove(toId)
        return dropped
    }

    fun depth(toId: String): Int = queued[toId]?.size ?: 0

    fun closeRun(runId: String) {
        creates.remove(runId)
    }

    fun claimCreate(runId: String?): Boolean {
        if (runId == null) return true
        val used = creates[runId] ?: 0
        if (used >= MAX_CREATES_PER_RUN) return false
        creates[runId] = used + 1
        return true
    }
}

sealed class WakeVerdict {
    data object Allowed : WakeVerdict()
    data class Refused(val reason: String) : WakeVerdict()
}

/**
 * An unanswered agent wake is the last wake with no later assistant, message, or user event.
 * User turns are not replayed on startup.
 */
fun pendingWake(events: List<TranscriptEvent>): QueuedWake? {
    for (index in events.indices.reversed()) {
        when (val event = events[index]) {
            is TranscriptEvent.Assistant, is TranscriptEvent.Message, is TranscriptEvent.User -> return null
            is TranscriptEvent.Wake -> {
                val source = event.source as? WakeSource.Agent ?: return null
                return QueuedWake(source.fromId, source.fromName, event.text, event.hops)
            }
            else -> Unit
        }
    }
    return null
}

/** Hops come from the transcript, so they survive a process restart. */
fun currentHops(events: List<TranscriptEvent>): Int {
    for (index in events.indices.reversed()) {
        when (val event = events[index]) {
            is TranscriptEvent.User -> return 0
            is TranscriptEvent.Wake -> return event.hops
            else -> Unit
        }
    }
    return 0
}
