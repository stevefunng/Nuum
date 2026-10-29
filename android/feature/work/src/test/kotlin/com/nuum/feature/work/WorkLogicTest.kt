package com.nuum.feature.work

import com.nuum.contracts.AgentProfile
import com.nuum.contracts.AgentRuntime
import com.nuum.contracts.AgentSettings
import com.nuum.contracts.AgentStatus
import com.nuum.contracts.AgentView
import com.nuum.contracts.ModelRef
import com.nuum.contracts.ProviderId
import com.nuum.contracts.WorkActor
import com.nuum.contracts.WorkBlocker
import com.nuum.contracts.WorkCatalog
import com.nuum.contracts.WorkCatalogInput
import com.nuum.contracts.WorkEvent
import com.nuum.contracts.WorkEventBody
import com.nuum.contracts.WorkKind
import com.nuum.contracts.WorkProfile
import com.nuum.contracts.WorkSnapshot
import com.nuum.contracts.WorkTask
import com.nuum.contracts.WorkTaskPriority
import com.nuum.contracts.WorkTaskState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkLogicTest {
    @Test
    fun displayTitleStripsWorkPrefixOnly() {
        assertEquals("Design review", workDisplayTitle("NunuBar · Design review"))
        assertEquals("Design review", workDisplayTitle("Work Bar · Design review"))
        assertEquals("Design review", workDisplayTitle("WorkBar: Design review"))
        assertEquals("Build the NunuBar", workDisplayTitle("Build the NunuBar"))
        assertEquals("NunuBar", workDisplayTitle("NunuBar"))
    }

    @Test
    fun blockedTransitionCarriesExistingReason() {
        val task = task(WorkTaskState.BLOCKED, WorkBlocker("Waiting for assets"))
        val blocker = blockerForTransition(task, WorkTaskState.IN_PROGRESS)
        assertEquals("Waiting for assets", blocker?.reason)
        assertEquals("Waiting for assets", blockerForTransition(task, WorkTaskState.CANCELLED)?.reason)
        assertNull(blockerForTransition(task.copy(state = WorkTaskState.REVIEW), WorkTaskState.DONE))
    }

    @Test
    fun catalogInputIsOnlyTheFourProtocolKinds() {
        val skill = catalogInput(CatalogKind.SKILL, " Review ", " /skill/SKILL.md ", "")
        assertTrue(skill is WorkCatalogInput.Skill)
        assertEquals("/skill/SKILL.md", (skill as WorkCatalogInput.Skill).manifestPath)
        assertEquals("", skill.description)

        val cli = catalogInput(CatalogKind.CLI, "Git", "/usr/bin/git", "status, diff log")
        assertTrue(cli is WorkCatalogInput.Cli)
        assertEquals(listOf("status", "diff", "log"), (cli as WorkCatalogInput.Cli).allowedSubcommands)

        val knowledge = catalogInput(CatalogKind.KNOWLEDGE, "Docs", "/docs", "") as WorkCatalogInput.Knowledge
        assertEquals(listOf("/docs"), knowledge.roots)
        assertTrue(knowledge.readOnly)

        val tools = catalogInput(CatalogKind.LOCAL_TOOL, "Files", "read, write", "")
        assertTrue(tools is WorkCatalogInput.LocalTool)
        assertEquals(listOf("read", "write"), (tools as WorkCatalogInput.LocalTool).toolNames)

        assertNull(catalogInput(CatalogKind.LOCAL_TOOL, "Files", " , ", ""))
        assertNull(catalogInput(CatalogKind.SKILL, " ", "/skill", ""))
        assertEquals(4, CATALOG_KINDS.size)
    }

    @Test
    fun historyWindowUsesTheFirstKeptSequence() {
        val chat = listOf(chat(3), chat(4), chat(8))
        assertEquals(3, inputAfterSeq(chat, 2))
        assertEquals(0, inputAfterSeq(emptyList(), 4))
    }

    @Test
    fun runningWithoutAnActiveRunIsElsewhere() {
        val agent = agent(AgentStatus.RUNNING, activeRunId = null)
        assertTrue(memberActivity(agent, emptySnapshot()) is MemberActivity.Elsewhere)
        assertTrue(memberActivity(agent.copy(runtime = agent.runtime.copy(status = AgentStatus.IDLE)), emptySnapshot()) is MemberActivity.Idle)
    }

    private fun chat(seq: Int) = WorkEvent(
        type = "chat.posted",
        id = "e$seq",
        workId = "w",
        seq = seq,
        createdAt = 0L,
        actor = WorkActor.User("local-user"),
        body = WorkEventBody.ChatPosted("m$seq", "hi", emptyList()),
    )

    private fun task(state: WorkTaskState, blocker: WorkBlocker?) = WorkTask(
        id = "t",
        title = "Card",
        description = "",
        acceptanceCriteria = emptyList(),
        state = state,
        assigneeIds = emptyList(),
        dependencyIds = emptyList(),
        priority = WorkTaskPriority.NORMAL,
        revision = 2,
        deliverables = emptyList(),
        createdAt = 0L,
        updatedAt = 0L,
        blocker = blocker,
    )

    private fun agent(status: AgentStatus, activeRunId: String?) = AgentView(
        profile = AgentProfile("a", "Ada", "", 0L),
        settings = AgentSettings(model = ModelRef(ProviderId.DEEPSEEK, "deepseek-chat")),
        runtime = AgentRuntime(status = status, unread = false, lastActivityAt = 0L, activeRunId = activeRunId),
    )

    private fun emptySnapshot() = WorkSnapshot(
        discussionRunning = false,
        interruptions = emptyList(),
        throughSeq = 0,
        profile = WorkProfile("w", "Launch", "", null, 0L, WorkKind.WORK),
        members = emptyList(),
        catalog = WorkCatalog(0, emptyList()),
        events = emptyList(),
        tasks = emptyList(),
        chat = emptyList(),
    )
}
