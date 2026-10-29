package com.nuum.testing.acceptance

import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.nuum.MainActivity
import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

/**
 * UI scenarios on a device or emulator. The debug APK installs
 * [com.nuum.graph.AcceptanceRouterModel] only when this module passes
 * `nuum.fakeModel=router`. Release builds do not contain that class.
 *
 * Killing the process with `am force-stop` also kills this instrumentation,
 * so scenario 9 relaunches the activity in-process. A new process, with the
 * scheduler empty and the transcript still on disk, is the host test.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class AcceptanceScenariosTest {
    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun a_scenario1_coldStartShowsNoRunningNunu() {
        compose.waitUntil(15_000) { compose.hasText("新建 Nunu", "New Nunu") }
        assertFalse(compose.hasText("工作中", "Working"))
    }

    @Test
    fun b_scenario3_sendWithoutAKeyShowsTheHostError() {
        createNunu("Locked")
        typeMessage("hello")
        clickSend()
        compose.waitUntil(15_000) { compose.hasText("Missing API key") }
        assertFalse(transcript("Locked").contains("sk-"))
    }

    @Test
    fun c_scenario5_approvalDenyAlwaysAndSealedSecrets() {
        saveDeepSeekKey()
        createNunu("Writer")
        typeMessage("acceptance-write the note")
        clickSend()
        compose.waitUntil(20_000) { compose.hasText("拒绝", "Deny") }
        compose.clickText("拒绝", "Deny")
        compose.waitUntil(20_000) { compose.hasText("User denied this tool call.") }
        val note = File(target().filesDir, "nuum/outside-scratch.txt")
        assertFalse(note.isFile && note.readText().contains(NOTE_TEXT))

        typeMessage("acceptance-write the note again")
        clickSend()
        compose.waitUntil(20_000) { compose.hasText("始终允许", "Always allow") }
        compose.clickText("始终允许", "Always allow")
        compose.waitUntil(20_000) { note.isFile && note.readText().contains(NOTE_TEXT) }

        typeMessage("acceptance-write the note once more")
        clickSend()
        compose.waitUntil(20_000) { !compose.hasText("始终允许", "Always allow") && !compose.hasText("拒绝", "Deny") }
        assertTrue(note.readText().contains(NOTE_TEXT))

        typeMessage("acceptance-secrets now")
        clickSend()
        compose.waitUntil(20_000) { compose.hasText("protected", "outside", "Permission denied") }
        val sealed = File(target().noBackupFilesDir, "secrets.bin")
        if (sealed.isFile) {
            val bytes = sealed.readBytes().decodeToString()
            assertFalse(bytes.contains(NOTE_TEXT))
            assertFalse(bytes.contains(PLANTED_KEY))
        }
        assertFalse(transcript("Writer").contains(PLANTED_KEY))
    }

    @Test
    fun d_scenario7_roomHasNoManualCreateTaskControl() {
        compose.clickText("新建", "New")
        compose.clickText("创建 NunuBar", "Create NunuBar")
        compose.clickText("本地群聊", "Local room")
        compose.onNodeWithTag("work-create-name").performTextInput("Launch")
        compose.clickText("创建 NunuBar", "Create NunuBar")
        compose.waitUntil(15_000) { compose.hasText("Launch") }
        compose.clickText("Launch")
        compose.waitUntil(15_000) { compose.hasText("升级为 NunuBar", "Enable task board") }
        listOf("New task", "Create task", "A new task", "新建任务", "创建任务").forEach { label ->
            assertFalse(compose.hasText(label))
        }
    }

    @Test
    fun e_scenario9_relaunchKeepsTheMessageAndIsNotRunning() {
        saveDeepSeekKey()
        createNunu("Keeper")
        typeMessage("acceptance-send hello")
        clickSend()
        compose.waitUntil(20_000) { compose.hasText("Visible from SendMessage") }
        compose.activityRule.scenario.recreate()
        compose.waitUntil(15_000) { compose.hasText("Visible from SendMessage") }
        assertFalse(compose.hasText("工作中", "Working"))
        val text = transcript("Keeper")
        assertTrue(text.contains("Visible from SendMessage"))
        assertFalse(text.contains(PLANTED_KEY))
    }

    private fun saveDeepSeekKey() {
        compose.clickText("设置", "Settings")
        compose.onNodeWithTag("api-key-deepseek").performScrollTo().performTextInput(PLANTED_KEY)
        compose.onNodeWithTag("api-key-deepseek").performImeAction()
        compose.onNodeWithTag("close-settings").performClick()
    }

    private fun createNunu(name: String) {
        compose.clickText("新建 Nunu", "New Nunu")
        compose.onNodeWithTag("nunu-name").performTextInput(name)
        compose.onNodeWithTag("nunu-name").performImeAction()
        compose.waitUntil(15_000) {
            compose.hasText("尽管提问", "Ask anything", "给 $name 发消息", "Message $name")
        }
    }

    private fun typeMessage(text: String) {
        val placeholders = listOf("尽管提问，也可以拖入文件。", "Ask anything, or drop a file.")
        compose.waitUntil(10_000) { placeholders.any { compose.hasText(it) } || compose.hasText("发消息", "Message ") }
        val label = placeholders.firstOrNull { compose.hasText(it) } ?: "发消息"
        compose.onAllNodesWithText(label, substring = true)[0].performTextInput(text)
    }

    private fun clickSend() {
        compose.clickText("发送消息", "Send message")
    }

    private fun transcript(name: String): String {
        val agents = File(target().filesDir, "nuum/agents")
        val dir = agents.listFiles()?.firstOrNull { child ->
            val profile = File(child, "profile.json")
            profile.isFile && profile.readText().contains(name)
        } ?: return ""
        val file = File(dir, "transcript.jsonl")
        return if (file.isFile) file.readText() else ""
    }

    private fun target() = InstrumentationRegistry.getInstrumentation().targetContext
}

private fun androidx.compose.ui.test.junit4.AndroidComposeTestRule<*, *>.hasText(vararg labels: String): Boolean =
    labels.any { onAllNodesWithText(it, substring = true).fetchSemanticsNodes().isNotEmpty() }

private fun androidx.compose.ui.test.junit4.AndroidComposeTestRule<*, *>.clickText(vararg labels: String) {
    waitUntil(15_000) { hasText(*labels) }
    val label = labels.first { onAllNodesWithText(it, substring = true).fetchSemanticsNodes().isNotEmpty() }
    onAllNodesWithText(label, substring = true)[0].performClick()
}

private const val PLANTED_KEY = "sk-acceptance-not-a-real-key"
private const val NOTE_TEXT = "accepted-note"
