package com.nuum.feature.work

import com.nuum.contracts.AgentStatus
import com.nuum.contracts.AgentView
import com.nuum.contracts.AssistantPart
import com.nuum.contracts.TranscriptEvent
import com.nuum.contracts.WorkBlocker
import com.nuum.contracts.WorkCatalogInput
import com.nuum.contracts.WorkEvent
import com.nuum.contracts.WorkEventBody
import com.nuum.contracts.WorkSnapshot
import com.nuum.contracts.WorkTask
import com.nuum.contracts.WorkTaskState
import com.nuum.contracts.WorkTaskView

private val WORK_TITLE = Regex(
    """^(?:work\s*bar|nunubar)\s*[·:：—–\-]\s*""",
    RegexOption.IGNORE_CASE,
)

/** Strips a leading "work bar" / "nunubar" separator. Otherwise returns [name]. */
internal fun workDisplayTitle(name: String): String {
    val stripped = WORK_TITLE.replace(name, "").trim()
    return stripped.ifEmpty { name }
}

internal enum class CatalogKind {
    SKILL,
    CLI,
    KNOWLEDGE,
    LOCAL_TOOL,
}

internal val CATALOG_KINDS: List<CatalogKind> = CatalogKind.entries

internal val LANE_ORDER: List<WorkTaskState> = listOf(
    WorkTaskState.PROPOSED,
    WorkTaskState.READY,
    WorkTaskState.IN_PROGRESS,
    WorkTaskState.BLOCKED,
    WorkTaskState.REVIEW,
    WorkTaskState.DONE,
    WorkTaskState.CANCELLED,
)

internal sealed class MemberActivity {
    data object Idle : MemberActivity()
    data object Error : MemberActivity()
    data object Discussion : MemberActivity()
    data object Elsewhere : MemberActivity()
    data class Card(val title: String?) : MemberActivity()
}

/**
 * Activity shown in the member status bubble.
 * A card is "running" only while the agent runtime is running; `in_progress` alone is a task state.
 */
internal fun memberActivity(agent: AgentView, snapshot: WorkSnapshot): MemberActivity {
    if (agent.runtime.status != AgentStatus.RUNNING) {
        return if (agent.runtime.status == AgentStatus.ERROR) MemberActivity.Error else MemberActivity.Idle
    }
    if (agent.runtime.activeRunId == null) return MemberActivity.Elsewhere
    val finished = snapshot.events.mapNotNull { event ->
        val body = event.body as? WorkEventBody.ExecutionFinished
        if (body != null && body.agentId == agent.profile.id) body.sourceEventId else null
    }.toSet()
    val requested = snapshot.events.asReversed().firstNotNullOfOrNull { event ->
        val body = event.body as? WorkEventBody.WorkRequested
        if (body != null && body.agentId == agent.profile.id && event.id !in finished) body else null
    }
    if (requested?.taskId != null) {
        val title = snapshot.tasks.firstOrNull { it.task.id == requested.taskId }?.task?.title
        return MemberActivity.Card(title)
    }
    if (snapshot.discussionRunning) return MemberActivity.Discussion
    val assigned = snapshot.tasks.firstOrNull { view ->
        view.task.state == WorkTaskState.IN_PROGRESS && agent.profile.id in view.task.assigneeIds
    }
    return if (assigned != null) MemberActivity.Card(assigned.task.title) else MemberActivity.Elsewhere
}

internal fun canDispatch(member: AgentView): Boolean =
    member.settings.workMembership?.binding?.grants?.canManageOwnTasks == true

internal fun membershipRevision(member: AgentView, workId: String): Int =
    member.roomMemberships[workId]?.revision
        ?: member.settings.workMembership?.revision
        ?: 0

/**
 * A transition that starts on a blocked card carries the card's existing blocker.
 * The host requires a reason when the destination is blocked; this screen does not
 * invent a reason field, it forwards the reason already on the card.
 */
internal fun blockerForTransition(task: WorkTask, to: WorkTaskState): WorkBlocker? {
    if (task.state != WorkTaskState.BLOCKED && to != WorkTaskState.BLOCKED) return null
    return task.blocker
}

internal fun inputAfterSeq(chat: List<WorkEvent>, recentCount: Int): Int {
    val recent = chat.takeLast(recentCount.coerceAtLeast(1))
    val first = recent.firstOrNull()?.seq ?: 1
    return (first - 1).coerceAtLeast(0)
}

internal fun skillManifestPath(directory: String): String =
    directory.trimEnd('/', '\\') + "/SKILL.md"

internal fun directoryName(directory: String): String =
    directory.trimEnd('/', '\\').substringAfterLast('/').substringAfterLast('\\')

/**
 * Builds one of the four catalog inputs the protocol accepts.
 * Returns null when the name or path is blank, or when a local-tool path has no tool name.
 */
internal fun catalogInput(
    kind: CatalogKind,
    name: String,
    path: String,
    commands: String,
): WorkCatalogInput? {
    val trimmedName = name.trim()
    val trimmedPath = path.trim()
    if (trimmedName.isEmpty() || trimmedPath.isEmpty()) return null
    return when (kind) {
        CatalogKind.SKILL -> WorkCatalogInput.Skill(
            name = trimmedName,
            description = "",
            manifestPath = trimmedPath,
        )
        CatalogKind.CLI -> WorkCatalogInput.Cli(
            name = trimmedName,
            description = "",
            executable = trimmedPath,
            allowedSubcommands = commands.split(Regex("[,\\s]+")).filter { it.isNotEmpty() },
        )
        CatalogKind.KNOWLEDGE -> WorkCatalogInput.Knowledge(
            name = trimmedName,
            description = "",
            roots = listOf(trimmedPath),
            readOnly = true,
        )
        CatalogKind.LOCAL_TOOL -> {
            val tools = trimmedPath.split(',').map { it.trim() }.filter { it.isNotEmpty() }
            if (tools.isEmpty()) return null
            WorkCatalogInput.LocalTool(
                name = trimmedName,
                description = "",
                toolNames = tools,
            )
        }
    }
}

internal fun tasksIn(tasks: List<WorkTaskView>, state: WorkTaskState): List<WorkTask> =
    tasks.map { it.task }.filter { it.state == state }

internal fun traceText(event: TranscriptEvent): String = when (event) {
    is TranscriptEvent.User -> event.text
    is TranscriptEvent.Wake -> event.text
    is TranscriptEvent.Assistant -> event.parts.joinToString("\n\n") { part ->
        when (part) {
            is AssistantPart.Thinking -> part.text
            is AssistantPart.Text -> part.text
            is AssistantPart.ToolCallPart -> part.name + "\n" + part.arguments.entries.joinToString { "${it.key}=${it.value}" }
        }
    }
    is TranscriptEvent.Tool -> event.name + "\n" + event.content
    is TranscriptEvent.Message -> event.type
    is TranscriptEvent.Compact -> event.summary
    is TranscriptEvent.Profile -> event.name ?: event.type
}

internal fun chatBody(event: WorkEvent): WorkEventBody.ChatPosted? =
    event.body as? WorkEventBody.ChatPosted
