package com.nuum.agent

import com.nuum.contracts.TurnSupervisor
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job

/**
 * In-process run scheduling. A [runId] is process-local and is not a resume cursor.
 * Global cap is [maxConcurrent]. One agent has one active run. Nested project roots
 * do not run together.
 */
class AgentScheduler(
    private val supervisor: TurnSupervisor,
    private val maxConcurrent: Int = DEFAULT_MAX_CONCURRENT_RUNS,
    private val newRunId: () -> String = { UUID.randomUUID().toString() }
) {
    class RunRequest(
        val agentId: String,
        val context: RunContext,
        val projectRoot: String? = null,
        val start: suspend (runId: String) -> Unit
    )

    private class Scheduled(
        val request: RunRequest,
        val runId: String,
        val projectRoot: String?,
        val completed: CompletableDeferred<RunOutcome>
    )

    private val lock = Any()
    private val active = LinkedHashMap<String, Scheduled>()
    private val pending = ArrayList<Scheduled>()
    private val jobs = ConcurrentHashMap<String, Job>()

    fun submit(request: RunRequest): SubmittedRun = synchronized(lock) {
        val completed = CompletableDeferred<RunOutcome>()
        val scheduled = Scheduled(
            request = request,
            runId = newRunId(),
            projectRoot = request.projectRoot?.let(::canonicalRoot),
            completed = completed
        )
        if (canStart(scheduled)) {
            val started = launch(scheduled)
            SubmittedRun(scheduled.runId, RunState.STARTED, started, completed)
        } else {
            pending += scheduled
            SubmittedRun(scheduled.runId, RunState.QUEUED, null, completed)
        }
    }

    fun settle(runId: String, status: RunOutcome = RunOutcome.COMPLETED) {
        synchronized(lock) {
            val run = active.remove(runId) ?: return
            jobs.remove(runId)
            run.completed.complete(status)
            pump()
        }
    }

    /** Drops queued work for [agentId] and returns active run ids the kernel must cancel. */
    fun cancelAgent(agentId: String): List<String> = synchronized(lock) {
        for (index in pending.indices.reversed()) {
            if (pending[index].request.agentId == agentId) {
                pending.removeAt(index).completed.complete(RunOutcome.CANCELLED)
            }
        }
        val cancelling = active.values.filter { it.request.agentId == agentId }.map { it.runId }
        cancelling.forEach { jobs[it]?.cancel() }
        cancelling
    }

    fun cancelQueued(runId: String): Boolean = synchronized(lock) {
        val index = pending.indexOfFirst { it.runId == runId }
        if (index < 0) return false
        pending.removeAt(index).completed.complete(RunOutcome.CANCELLED)
        true
    }

    fun agentIdFor(runId: String): String? = synchronized(lock) {
        active[runId]?.request?.agentId ?: pending.find { it.runId == runId }?.request?.agentId
    }

    fun contextFor(runId: String): RunContext? = synchronized(lock) {
        active[runId]?.request?.context ?: pending.find { it.runId == runId }?.request?.context
    }

    fun activeRunFor(agentId: String): String? = synchronized(lock) {
        active.values.firstOrNull { it.request.agentId == agentId }?.runId
    }

    fun isBusy(agentId: String): Boolean = synchronized(lock) {
        active.values.any { it.request.agentId == agentId } || pending.any { it.request.agentId == agentId }
    }

    fun activeCount(): Int = synchronized(lock) { active.size }

    fun queueDepth(): Int = synchronized(lock) { pending.size }

    fun close() {
        synchronized(lock) {
            (pending + active.values).forEach { it.completed.complete(RunOutcome.CANCELLED) }
            pending.clear()
            active.clear()
            jobs.values.forEach { it.cancel() }
            jobs.clear()
        }
    }

    private fun canStart(candidate: Scheduled): Boolean {
        if (active.size >= maxConcurrent) return false
        for (run in active.values) {
            if (run.request.agentId == candidate.request.agentId) return false
            val left = run.projectRoot
            val right = candidate.projectRoot
            if (left != null && right != null && (containsRoot(left, right) || containsRoot(right, left))) {
                return false
            }
        }
        return true
    }

    private fun launch(run: Scheduled): CompletableDeferred<Unit> {
        active[run.runId] = run
        val started = CompletableDeferred<Unit>()
        val job = supervisor.launch {
            try {
                run.request.start(run.runId)
                started.complete(Unit)
            } catch (error: CancellationException) {
                if (!started.isCompleted) started.completeExceptionally(error)
                settle(run.runId, RunOutcome.CANCELLED)
                throw error
            } catch (error: Throwable) {
                if (!started.isCompleted) started.completeExceptionally(error)
                settle(run.runId, RunOutcome.FAILED)
            }
        }
        jobs[run.runId] = job
        return started
    }

    /** Skip a busy agent at the head so a free agent behind it can start. */
    private fun pump() {
        while (active.size < maxConcurrent) {
            val index = pending.indexOfFirst { canStart(it) }
            if (index < 0) return
            launch(pending.removeAt(index))
        }
    }
}

enum class RunState { STARTED, QUEUED }

enum class RunOutcome { COMPLETED, FAILED, CANCELLED }

class SubmittedRun(
    val runId: String,
    val state: RunState,
    val started: CompletableDeferred<Unit>?,
    val completed: CompletableDeferred<RunOutcome>
)

sealed class RunContext {
    data object Direct : RunContext()

    data class Work(
        val workId: String,
        val bridgeId: String? = null,
        val taskId: String? = null,
        val discussionId: String? = null,
        val membershipRevision: Int? = null,
        val instruction: String = "",
        val inputAfterSeq: Int? = null
    ) : RunContext()
}

internal fun canonicalRoot(root: String): String = File(root).absoluteFile.normalize().path

internal fun containsRoot(parent: String, child: String): Boolean {
    val base = File(parent).absoluteFile.normalize().toPath()
    val other = File(child).absoluteFile.normalize().toPath()
    return other.startsWith(base)
}
