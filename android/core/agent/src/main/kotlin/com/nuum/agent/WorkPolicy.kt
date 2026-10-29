package com.nuum.agent

import com.nuum.protocol.WorkRole
import com.nuum.protocol.WorkTaskState

enum class TaskActorRole { USER, COORDINATOR, WORKER, OBSERVER }

private data class TransitionRule(val to: WorkTaskState, val roles: Set<TaskActorRole>)

/**
 * Single transition table. The work screen and the model tools both read it.
 * Blocked returns to in_progress or ready only for the user.
 */
private val TRANSITIONS: Map<WorkTaskState, List<TransitionRule>> = mapOf(
    WorkTaskState.PROPOSED to listOf(
        TransitionRule(WorkTaskState.READY, setOf(TaskActorRole.USER, TaskActorRole.COORDINATOR)),
        TransitionRule(WorkTaskState.CANCELLED, setOf(TaskActorRole.USER, TaskActorRole.COORDINATOR))
    ),
    WorkTaskState.READY to listOf(
        TransitionRule(WorkTaskState.IN_PROGRESS, setOf(TaskActorRole.USER, TaskActorRole.COORDINATOR, TaskActorRole.WORKER)),
        TransitionRule(WorkTaskState.CANCELLED, setOf(TaskActorRole.USER, TaskActorRole.COORDINATOR))
    ),
    WorkTaskState.IN_PROGRESS to listOf(
        TransitionRule(WorkTaskState.REVIEW, setOf(TaskActorRole.USER, TaskActorRole.COORDINATOR, TaskActorRole.WORKER)),
        TransitionRule(WorkTaskState.BLOCKED, setOf(TaskActorRole.USER, TaskActorRole.COORDINATOR, TaskActorRole.WORKER)),
        TransitionRule(WorkTaskState.CANCELLED, setOf(TaskActorRole.USER, TaskActorRole.COORDINATOR))
    ),
    WorkTaskState.BLOCKED to listOf(
        TransitionRule(WorkTaskState.IN_PROGRESS, setOf(TaskActorRole.USER)),
        TransitionRule(WorkTaskState.READY, setOf(TaskActorRole.USER)),
        TransitionRule(WorkTaskState.CANCELLED, setOf(TaskActorRole.USER, TaskActorRole.COORDINATOR))
    ),
    WorkTaskState.REVIEW to listOf(
        TransitionRule(WorkTaskState.DONE, setOf(TaskActorRole.USER)),
        TransitionRule(WorkTaskState.IN_PROGRESS, setOf(TaskActorRole.USER, TaskActorRole.COORDINATOR)),
        TransitionRule(WorkTaskState.CANCELLED, setOf(TaskActorRole.USER, TaskActorRole.COORDINATOR))
    ),
    WorkTaskState.DONE to listOf(
        TransitionRule(WorkTaskState.IN_PROGRESS, setOf(TaskActorRole.USER, TaskActorRole.COORDINATOR))
    ),
    WorkTaskState.CANCELLED to emptyList()
)

fun allowedTaskTransitions(state: WorkTaskState, role: TaskActorRole): List<WorkTaskState> =
    TRANSITIONS.getValue(state).filter { role in it.roles }.map { it.to }

fun assertTaskTransition(from: WorkTaskState, to: WorkTaskState, role: TaskActorRole) {
    if (to in allowedTaskTransitions(from, role)) return
    throw IllegalArgumentException("Transition $from -> $to is not allowed for $role")
}

fun roleOf(role: WorkRole): TaskActorRole = when (role) {
    WorkRole.COORDINATOR -> TaskActorRole.COORDINATOR
    WorkRole.WORKER -> TaskActorRole.WORKER
    WorkRole.OBSERVER -> TaskActorRole.OBSERVER
}
