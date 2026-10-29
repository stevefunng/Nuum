package com.nuum.feature.work

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasNoClickAction
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextReplacement
import com.nuum.contracts.WorkCatalogInput
import com.nuum.contracts.WorkKind
import com.nuum.contracts.WorkTaskState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], qualifiers = "en-rUS-w480dp-h1400dp")
class WorkUiTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun roomUpgradeRequestsWorkKind() {
        val work = FakeWorkPort(workSnapshot(WorkKind.ROOM, name = "Launch room"))
        show(work)
        compose.onNodeWithText("Enable task board").assertIsEnabled().performClick()
        compose.waitUntil { work.updates.isNotEmpty() }
        val update = work.updates.single()
        assertEquals("work-1", update.id)
        assertEquals(WorkKind.WORK, update.kind)
        assertNoCreateTaskControl()
    }

    @Test
    fun discoveryCardsAreNotClickable() {
        val work = FakeWorkPort(workSnapshot(WorkKind.WORK))
        show(work)
        compose.onNodeWithContentDescription("Add capability").performClick()
        compose.onNodeWithText("Skills").assertHasNoClickAction()
        compose.onNodeWithText("CLI tools").assertHasNoClickAction()
        val presets = compose.onAllNodesWithText("Presets on the way")
        presets.assertCountEquals(2)
        presets[0].assertHasNoClickAction()
        presets[1].assertHasNoClickAction()
        assertTrue(work.catalogAdds.isEmpty())
        assertNoCreateTaskControl()
    }

    @Test
    fun importSubmitsOnlyTheFourAllowedKinds() {
        val work = FakeWorkPort(workSnapshot(WorkKind.WORK))
        show(work)
        import(kind = "Skill", name = "Design review", path = "/skills/review/SKILL.md")
        import(kind = "CLI", name = "Git", path = "/usr/bin/git", commands = "status, diff log")
        import(kind = "Knowledge", name = "Docs", path = "/knowledge")
        import(kind = "Local tools", name = "Files", path = "read, write")

        assertEquals(4, work.catalogAdds.size)
        val entries = work.catalogAdds.map { it.entry }
        val skill = entries[0] as WorkCatalogInput.Skill
        assertEquals("Design review", skill.name)
        assertEquals("", skill.description)
        assertEquals("/skills/review/SKILL.md", skill.manifestPath)
        val cli = entries[1] as WorkCatalogInput.Cli
        assertEquals("/usr/bin/git", cli.executable)
        assertEquals(listOf("status", "diff", "log"), cli.allowedSubcommands)
        assertEquals("", cli.description)
        val knowledge = entries[2] as WorkCatalogInput.Knowledge
        assertEquals(listOf("/knowledge"), knowledge.roots)
        assertTrue(knowledge.readOnly)
        assertEquals("", knowledge.description)
        val tools = entries[3] as WorkCatalogInput.LocalTool
        assertEquals(listOf("read", "write"), tools.toolNames)
        assertEquals("", tools.description)
        assertEquals(
            setOf(
                WorkCatalogInput.Skill::class,
                WorkCatalogInput.Cli::class,
                WorkCatalogInput.Knowledge::class,
                WorkCatalogInput.LocalTool::class,
            ),
            entries.map { it::class }.toSet(),
        )
    }

    @Test
    fun blockedTransitionCarriesReasonAndThereIsNoCreateTaskControl() {
        val work = FakeWorkPort(
            workSnapshot(
                kind = WorkKind.WORK,
                tasks = listOf(blockedTask("Waiting for assets")),
                members = listOf(member("ada", "Ada", canManage = true)),
            ),
        )
        show(work)
        compose.onNodeWithContentDescription("Open task: Write spec").performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        compose.onNodeWithText("Confirm and resume").performSemanticsAction(SemanticsActions.OnClick)
        compose.waitUntil { work.transitions.isNotEmpty() }
        val transition = work.transitions.single()
        assertEquals("task-1", transition.taskId)
        assertEquals(WorkTaskState.IN_PROGRESS, transition.to)
        assertEquals(4, transition.expectedRevision)
        assertEquals("Waiting for assets", transition.blocker?.reason)
        assertNoCreateTaskControl()
    }

    private fun show(work: FakeWorkPort) {
        val ports = WorkPorts(work = work, agent = FakeAgentPort(), desktop = FakeDesktopPort())
        compose.setContent { WorkScreen(workId = "work-1", ports = ports) }
        compose.waitForIdle()
    }

    private fun import(kind: String, name: String, path: String, commands: String? = null) {
        compose.onNodeWithContentDescription("Add capability").performClick()
        compose.onAllNodesWithText("Import local")[0].performClick()
        compose.onNodeWithText(kind).performClick()
        compose.onNodeWithTag(TAG_CATALOG_NAME).performTextReplacement(name)
        compose.onNodeWithTag(TAG_CATALOG_PATH).performTextReplacement(path)
        if (commands != null) {
            compose.onNodeWithTag(TAG_CATALOG_COMMANDS).performTextReplacement(commands)
        }
        compose.onAllNodesWithTag(TAG_CATALOG_KIND).assertCountEquals(4)
        compose.onNodeWithTag(TAG_CATALOG_SUBMIT).performClick()
        compose.waitForIdle()
    }

    private fun assertNoCreateTaskControl() {
        listOf("New task", "Create task", "A new task", "新建任务", "创建任务").forEach { label ->
            compose.onAllNodesWithText(label, substring = true).assertCountEquals(0)
        }
    }
}
