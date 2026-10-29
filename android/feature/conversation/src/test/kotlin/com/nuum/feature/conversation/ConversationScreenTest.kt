package com.nuum.feature.conversation

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import com.nuum.contracts.AgentAnswerWidgetParams
import com.nuum.contracts.AgentCreateParams
import com.nuum.contracts.AgentPort
import com.nuum.contracts.AgentProfile
import com.nuum.contracts.AgentRuntime
import com.nuum.contracts.AgentSendParams
import com.nuum.contracts.AgentSettings
import com.nuum.contracts.AgentSnapshot
import com.nuum.contracts.AgentStatus
import com.nuum.contracts.AgentUpdateParams
import com.nuum.contracts.AgentView
import com.nuum.contracts.DesktopPort
import com.nuum.contracts.HostEvent
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.MessagePart
import com.nuum.contracts.ModelRef
import com.nuum.contracts.OutboundMessage
import com.nuum.contracts.PickedFile
import com.nuum.contracts.ProviderId
import com.nuum.contracts.SendResult
import com.nuum.contracts.ToolResolution
import com.nuum.contracts.TranscriptEvent
import com.nuum.contracts.TranscriptPage
import com.nuum.contracts.TranscriptQuery
import com.nuum.contracts.WidgetOption
import com.nuum.contracts.WidgetPayload
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "en-rUS-w400dp-h800dp")
class ConversationScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun emptyTranscriptShowsTheWelcomeMarkAndDoesNotDrawNunuBar() {
        val agent = FakeAgentPort(sampleAgent())
        setScreen(agent)
        waitForText("Nuum")
        composeRule.onNodeWithText("Ask anything, or drop a file.").assertIsDisplayed()
        assertEquals(0, composeRule.onAllNodesWithText("NunuBar").fetchSemanticsNodes().size)
        assertTrue(agent.sends.isEmpty())
    }

    @Test
    fun messageDeltasAppendOntoTheOpenTranscript() {
        val agent = FakeAgentPort(sampleAgent())
        setScreen(agent)
        waitForText("Nuum")
        agent.emit(HostEvent.AgentMessageDelta("ada", "run", "m1", "Hel", MessagePart.TEXT))
        waitForText("Hel")
        agent.emit(HostEvent.AgentMessageDelta("ada", "run", "m1", "lo", MessagePart.TEXT))
        waitForText("Hello")
        assertEquals(0, composeRule.onAllNodesWithText("Hel").fetchSemanticsNodes().size)
        assertEquals(0, composeRule.onAllNodesWithText("Ask anything, or drop a file.").fetchSemanticsNodes().size)
    }

    @Test
    fun approvalButtonsCallDenyOnceAndAlways() {
        val agent = FakeAgentPort(sampleAgent())
        setScreen(agent)
        waitForText("Nuum")
        repeat(3) { index ->
            agent.emit(pending("call-$index"))
            waitForText("Deny")
            val label = when (index) {
                0 -> "Deny"
                1 -> "Allow once"
                else -> "Always allow"
            }
            composeRule.onNodeWithText(label).performClick()
            composeRule.waitUntil(timeoutMillis = 5_000) {
                composeRule.onAllNodesWithText("Deny").fetchSemanticsNodes().isEmpty()
            }
        }
        assertEquals(listOf("deny", "approve", "approve"), agent.decisions.map { it.method })
        assertEquals(listOf("deny", "once", "always"), agent.decisions.map { it.resolution.wire })
        assertEquals(listOf("call-0", "call-1", "call-2"), agent.decisions.map { it.toolCallId })
    }

    @Test
    fun widgetOptionCallsAnswerWidgetOnce() {
        val agent = FakeAgentPort(
            sampleAgent(
                events = listOf(
                    TranscriptEvent.Message(
                        id = "widget-1",
                        seq = 1,
                        createdAt = 1_700_000_000_000,
                        payload = OutboundMessage.Widget(
                            WidgetPayload(
                                prompt = "Pick one",
                                options = listOf(
                                    WidgetOption(label = "Yes", value = "yes"),
                                    WidgetOption(label = "No", value = "no")
                                )
                            )
                        )
                    )
                )
            )
        )
        setScreen(agent)
        waitForText("Pick one")
        composeRule.onNodeWithText("Yes").performClick()
        composeRule.waitUntil(timeoutMillis = 5_000) { agent.answers.size == 1 }
        val answer = agent.answers.single()
        assertEquals("ada", answer.id)
        assertEquals("widget-1", answer.messageId)
        assertEquals("yes", answer.value)
    }

    @Test
    fun moreThanFiveAttachmentsDoesNotCallSend() {
        val agent = FakeAgentPort(sampleAgent())
        val desktop = FakeDesktopPort().apply {
            files = List(6) { index -> PickedFile("f$index.txt", "text/plain", byteArrayOf(1)) }
        }
        setScreen(agent, desktop)
        waitForText("Nuum")
        composeRule.onNodeWithContentDescription("Message Ada").performTextInput("hi")
        composeRule.waitForIdle()
        composeRule.onNodeWithContentDescription("Send message").assertIsEnabled()
        composeRule.onNodeWithContentDescription("Composer actions").performClick()
        composeRule.onNodeWithText("Add attachment").performClick()
        waitForText("At most 5 attachments per message.")
        composeRule.onNodeWithContentDescription("Send message").assertIsNotEnabled()
        assertTrue(agent.sends.isEmpty())
    }

    private fun setScreen(agent: FakeAgentPort, desktop: FakeDesktopPort = FakeDesktopPort()) {
        composeRule.setContent {
            ConversationScreen(agentId = "ada", ports = ConversationPorts(agent, desktop))
        }
    }

    private fun waitForText(text: String) {
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun pending(id: String) = HostEvent.AgentToolPending(
        agentId = "ada",
        runId = "run-1",
        toolCallId = id,
        toolName = "write",
        arguments = mapOf("path" to "note.txt"),
        action = LocalToolAction.WRITE_FILE,
        target = "note.txt",
        allowAlways = true
    )
}

internal class FakeAgentPort(var snapshot: AgentSnapshot) : AgentPort {
    private val eventsFlow = MutableSharedFlow<HostEvent>(extraBufferCapacity = 32)
    override val events: Flow<HostEvent> = eventsFlow
    val sends = mutableListOf<AgentSendParams>()
    val answers = mutableListOf<AgentAnswerWidgetParams>()
    val decisions = mutableListOf<Decision>()

    fun emit(event: HostEvent) {
        check(eventsFlow.tryEmit(event)) { "event dropped: ${event.name}" }
    }

    override suspend fun list(): List<AgentView> = listOf(snapshot.view)
    override suspend fun get(id: String): AgentSnapshot = snapshot
    override suspend fun create(params: AgentCreateParams): AgentView = snapshot.view
    override suspend fun update(params: AgentUpdateParams): AgentView = snapshot.view
    override suspend fun delete(id: String) = Unit
    override suspend fun transcript(query: TranscriptQuery): TranscriptPage = TranscriptPage(query.id, snapshot.events)
    override suspend fun send(params: AgentSendParams): SendResult {
        sends += params
        return SendResult("run-send", queued = false)
    }

    override suspend fun answerWidget(params: AgentAnswerWidgetParams): SendResult {
        answers += params
        return SendResult("run-widget", queued = false)
    }

    override suspend fun cancel(id: String) = Unit
    override suspend fun approve(id: String, toolCallId: String, resolution: ToolResolution) {
        decisions += Decision("approve", toolCallId, resolution)
    }

    override suspend fun deny(id: String, toolCallId: String, resolution: ToolResolution) {
        decisions += Decision("deny", toolCallId, resolution)
    }
}

internal data class Decision(val method: String, val toolCallId: String, val resolution: ToolResolution)

internal class FakeDesktopPort : DesktopPort {
    var files: List<PickedFile> = emptyList()
    override suspend fun pickDirectory(): String? = null
    override suspend fun pickFiles(): List<PickedFile> = files
    override suspend fun openAttachment(path: String) = Unit
    override suspend fun share(path: String) = Unit
}

internal fun sampleAgent(
    name: String = "Ada",
    events: List<TranscriptEvent> = emptyList()
): AgentSnapshot {
    val view = AgentView(
        profile = AgentProfile(id = "ada", name = name, description = "", createdAt = 0L, avatarColor = "blue"),
        settings = AgentSettings(model = ModelRef(ProviderId.DEEPSEEK, "deepseek-chat")),
        runtime = AgentRuntime(status = AgentStatus.IDLE, unread = false, lastActivityAt = 0L)
    )
    return AgentSnapshot(view = view, events = events, blocks = emptyList(), live = null)
}
