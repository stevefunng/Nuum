package com.nuum.feature.conversation

import com.nuum.contracts.HostEvent
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.MessagePart
import com.nuum.contracts.OutboundMessage
import com.nuum.contracts.PickedFile
import com.nuum.contracts.ToolView
import com.nuum.contracts.ViewBlock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ConversationLogicTest {
    @Test
    fun textDeltasAppendOntoTheVisibleMessage() {
        val first = ConversationUiState().reduce(
            "ada",
            HostEvent.AgentMessageDelta("ada", "run", "m1", "Hel", MessagePart.TEXT)
        )
        val second = first.reduce(
            "ada",
            HostEvent.AgentMessageDelta("ada", "run", "m1", "lo", MessagePart.TEXT)
        )
        val message = second.visibleBlocks().filterIsInstance<ViewBlock.Message>().single()
        assertEquals("Hello", (message.payload as OutboundMessage.Text).content)
    }

    @Test
    fun deltasForAnotherAgentAreIgnored() {
        val next = ConversationUiState().reduce(
            "ada",
            HostEvent.AgentMessageDelta("other", "run", "m1", "Nope", MessagePart.TEXT)
        )
        assertTrue(next.visibleBlocks().isEmpty())
    }

    @Test
    fun workScopedPendingIsNotDrawnOnTheOneToOneBar() {
        val pending = PendingTool(
            toolCallId = "t",
            name = "write",
            arguments = emptyMap(),
            action = LocalToolAction.WRITE_FILE,
            target = "a.txt",
            workId = "work-1"
        )
        assertNull(oneToOneApproval(pending))
        assertEquals(pending.toolCallId, oneToOneApproval(pending.copy(workId = null))?.toolCallId)
        assertEquals(pending.toolCallId, oneToOneApproval(pending.copy(workId = ""))?.toolCallId)
    }

    @Test
    fun sixAttachmentsAreRejectedAndFiveAreKept() {
        val five = List(5) { index -> PickedFile("f$index.txt", "text/plain", byteArrayOf(1)) }
        val accepted = validateAttachments(emptyList(), five)
        assertTrue(accepted is AttachmentDecision.Accept)
        val files = (accepted as AttachmentDecision.Accept).files
        val rejected = validateAttachments(files, listOf(PickedFile("f5.txt", "text/plain", byteArrayOf(1))))
        assertEquals(CopyKey.AtMost5, (rejected as AttachmentDecision.Reject).reason)
        assertEquals(5, files.size)
    }

    @Test
    fun consecutiveToolCallsGroupUntilAVisibleMessage() {
        fun activity(id: String) = ViewBlock.Assistant(
            id = id,
            thinking = "",
            tools = listOf(ToolView(id = id, name = "shell", arguments = emptyMap(), status = "ok"))
        )
        val blocks = listOf(
            activity("a"),
            ViewBlock.Assistant(id = "hidden", thinking = "", tools = emptyList()),
            activity("b"),
            ViewBlock.Message(id = "reply", payload = OutboundMessage.Text("Done")),
            activity("c")
        )
        val result = groupToolActivity(blocks)
        assertEquals(3, result.size)
        val grouped = result[0] as ViewBlock.Assistant
        assertEquals("a", grouped.id)
        assertEquals(listOf("a", "b"), grouped.tools.map { it.id })
        assertEquals(5, blocks.size)
    }
}
