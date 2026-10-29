package com.nuum.kernel

import com.nuum.contracts.ChatMessage
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.KernelEvent
import com.nuum.contracts.LocalToolAction
import com.nuum.contracts.MessagePart
import com.nuum.contracts.MessageRole
import com.nuum.contracts.ModelImage
import com.nuum.contracts.ModelPort
import com.nuum.contracts.ModelRef
import com.nuum.contracts.NormalizedChatRequest
import com.nuum.contracts.NormalizedChunk
import com.nuum.contracts.NuumException
import com.nuum.contracts.PermissionDecision
import com.nuum.contracts.PermissionVerdict
import com.nuum.contracts.ProviderId
import com.nuum.contracts.RunEndStatus
import com.nuum.contracts.Secrets
import com.nuum.contracts.SummarizeRunParams
import com.nuum.contracts.ToolApproval
import com.nuum.contracts.ToolBackend
import com.nuum.contracts.ToolCall
import com.nuum.contracts.ToolDefinition
import com.nuum.contracts.ToolExecutionResult
import com.nuum.contracts.ToolPermission
import com.nuum.contracts.ToolResolution
import com.nuum.contracts.ToolRoots
import com.nuum.contracts.TurnContextResult
import com.nuum.contracts.TurnStartParams
import com.nuum.contracts.TurnToolDecision
import com.nuum.contracts.TurnToolResult
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class KernelTest {
    @Test
    fun noToolsEndsIdleAndEveryEventCarriesRunId() = exercise(scripted(listOf(listOf(
        NormalizedChunk.Thinking("hm"),
        NormalizedChunk.Text("hi")
    )))) {
        start(startParams(runId = "run-xyz"))
        awaitEnd()
        assertTrue(events.isNotEmpty())
        for (event in events) {
            assertEquals("run-xyz", event.runId())
        }
        assertEquals(RunEndStatus.IDLE, ended().status)
        assertFalse(events.any { it is KernelEvent.Error })
        assertFalse(events.any { it.name.startsWith("turn.tool") })
        val deltas = events.filterIsInstance<KernelEvent.Delta>()
        assertEquals(listOf(MessagePart.THINKING, MessagePart.TEXT), deltas.map { it.part })
        assertEquals(listOf("hm", "hi"), deltas.map { it.delta })
        assertEquals(1, modelRequests())
    }

    @Test
    fun delegatedToolWaitsAndFeedsTheNextRound() = exercise(
        scripted(
            listOf(
                listOf(NormalizedChunk.ToolCallChunk("c1", "send_message", mapOf("text" to "hi"))),
                listOf(NormalizedChunk.Text("done"))
            )
        ),
        tools = FakeTools()
    ) {
        start(startParams(delegatedTools = listOf(sendMessage)))
        await("delegate") { events.any { it is KernelEvent.ToolDelegate } }
        assertEquals(listOf("send_message"), requests()[0].tools.map { it.name })
        val delegate = events.filterIsInstance<KernelEvent.ToolDelegate>().single()
        assertEquals("run-1", delegate.runId)
        assertEquals("c1", delegate.toolCallId)
        assertEquals("send_message", delegate.toolName)
        assertEquals(mapOf("text" to "hi"), delegate.arguments)
        assertFalse(events.any { it is KernelEvent.ToolStarted })
        kernel.provideToolResult(TurnToolResult("run-1", "c1", ok = true, output = "delivered"))
        awaitEnd()
        val completed = events.filterIsInstance<KernelEvent.ToolCompleted>().single()
        assertEquals("run-1", completed.runId)
        assertEquals("c1", completed.toolCallId)
        assertEquals("send_message", completed.toolName)
        assertTrue(completed.ok)
        assertEquals("delivered", completed.output)
        val second = requests()[1].messages
        assertEquals(MessageRole.TOOL, second.last().role)
        assertEquals("delivered", second.last().content)
        assertEquals(RunEndStatus.IDLE, ended().status)
        assertTrue(tools.executions.isEmpty())
    }

    @Test
    fun failedDelegationReachesTheModelInsteadOfFailingTheTurn() = exercise(
        scripted(
            listOf(
                listOf(NormalizedChunk.ToolCallChunk("c1", "send_message", emptyMap())),
                listOf(NormalizedChunk.Text("ok, noted"))
            )
        )
    ) {
        start(startParams(delegatedTools = listOf(sendMessage)))
        await("delegate") { events.any { it is KernelEvent.ToolDelegate } }
        kernel.provideToolResult(TurnToolResult("run-1", "c1", ok = false, output = "target agent not found"))
        awaitEnd()
        assertFalse(events.any { it is KernelEvent.Error })
        assertFalse(events.filterIsInstance<KernelEvent.ToolCompleted>().single().ok)
        assertEquals("target agent not found", requests()[1].messages.last().content)
        assertEquals(RunEndStatus.IDLE, ended().status)
    }

    @Test
    fun endTurnStopsBeforeAnotherToolOrModelCall() = exercise(
        scripted(
            listOf(
                listOf(
                    NormalizedChunk.ToolCallChunk("handoff", "send_message", emptyMap()),
                    NormalizedChunk.ToolCallChunk("later", "send_message", emptyMap())
                )
            )
        )
    ) {
        start(startParams(delegatedTools = listOf(sendMessage)))
        await("handoff") { events.any { it is KernelEvent.ToolDelegate } }
        kernel.provideToolResult(
            TurnToolResult("run-1", "handoff", ok = true, output = "returned to owner", endTurn = true)
        )
        awaitEnd()
        assertEquals(1, requests().size)
        assertEquals(1, events.filterIsInstance<KernelEvent.ToolDelegate>().size)
        assertEquals(RunEndStatus.IDLE, ended().status)
        assertFalse(events.any { it is KernelEvent.Error })
    }

    @Test
    fun roundExhaustionSaysSo() = exercise(
        scripted(
            List(20) { index ->
                listOf(NormalizedChunk.ToolCallChunk("c$index", "send_message", emptyMap()))
            }
        )
    ) {
        start(startParams(delegatedTools = listOf(sendMessage)))
        var answered = 0
        while (events.none { it is KernelEvent.Ended }) {
            val delegated = events.filterIsInstance<KernelEvent.ToolDelegate>()
            if (delegated.size > answered) {
                val callId = delegated[answered].toolCallId
                kernel.provideToolResult(TurnToolResult("run-1", callId, ok = true, output = "ok"))
                answered += 1
            }
            delay(2)
            assertTrue("the round limit must stop the loop", answered <= 16)
        }
        assertEquals(16, answered)
        assertEquals(16, requests().size)
        val notice = events.filterIsInstance<KernelEvent.Delta>().last()
        assertEquals("Stopped after 16 tool rounds without a final answer.", notice.delta)
        assertEquals(MessagePart.TEXT, notice.part)
        assertEquals(RunEndStatus.IDLE, ended().status)
        assertFalse(events.any { it is KernelEvent.Error })
    }

    @Test
    fun cancelDuringDelegateEndsCancelledWithoutError() = exercise(
        scripted(listOf(listOf(NormalizedChunk.ToolCallChunk("c1", "send_message", emptyMap()))))
    ) {
        start(startParams(delegatedTools = listOf(sendMessage)))
        await("delegate") { events.any { it is KernelEvent.ToolDelegate } }
        kernel.cancel("run-1")
        awaitEnd()
        assertEquals(RunEndStatus.CANCELLED, ended().status)
        assertFalse(events.any { it is KernelEvent.Error })
        assertFalse(events.any { it is KernelEvent.ToolCompleted })
    }

    @Test
    fun cancelMidStreamEndsCancelledWithoutError() = exercise(HangingModel()) {
        start(startParams())
        await("stream") { (model as HangingModel).started.isCompleted }
        kernel.cancel("run-1")
        awaitEnd()
        assertEquals(RunEndStatus.CANCELLED, ended().status)
        assertFalse(events.any { it is KernelEvent.Error })
        assertEquals("partial", events.filterIsInstance<KernelEvent.Delta>().single().delta)
    }

    @Test
    fun cancelDuringApprovalEndsCancelledWithoutError() {
        val tools = FakeTools(
            defs = listOf(writeTool),
            verdict = { _, target -> PermissionVerdict(PermissionDecision.ASK, target) }
        )
        exercise(
            scripted(
                listOf(
                    listOf(NormalizedChunk.ToolCallChunk("c1", "write", mapOf("path" to "/tmp/needs-approval.txt")))
                )
            ),
            tools
        ) {
            start(startParams(localToolNames = listOf("write"), toolPermission = ToolPermission.ASK))
            await("approval") { events.any { it is KernelEvent.ToolPending } }
            kernel.cancel("run-1")
            awaitEnd()
            assertEquals(RunEndStatus.CANCELLED, ended().status)
            assertFalse(events.any { it is KernelEvent.Error })
            assertTrue(tools.executions.isEmpty())
            assertTrue(tools.releases.contains("run-1"))
        }
    }

    @Test
    fun missingKeyEndsTheTurnWithInvalidAndDoesNotCallTheModel() = exercise(scripted(emptyList())) {
        start(startParams(secrets = Secrets()))
        awaitEnd()
        val error = events.filterIsInstance<KernelEvent.Error>().single()
        assertEquals(KernelErrorCode.INVALID, error.code)
        assertEquals("API key missing for deepseek", error.message)
        assertEquals(RunEndStatus.ERROR, ended().status)
        assertTrue(requests().isEmpty())
        assertTrue(tools.binds.isEmpty())
    }

    @Test
    fun emptyKeyIsAlsoMissing() = exercise(scripted(emptyList())) {
        start(startParams(secrets = Secrets(deepseekApiKey = "")))
        awaitEnd()
        assertEquals("API key missing for deepseek", events.filterIsInstance<KernelEvent.Error>().single().message)
        assertEquals(1007, events.filterIsInstance<KernelEvent.Error>().single().code)
    }

    @Test
    fun summarizeKeepsTheSystemPromptAndOnlyText() = exercise(
        scriptedChunks(listOf(NormalizedChunk.Thinking("let me think"), NormalizedChunk.Text("  a summary  ")))
    ) {
        val result = kernel.summarize(summarizeParams())
        assertEquals("a summary", result.text)
        assertEquals(
            listOf(MessageRole.SYSTEM to "You summarize.", MessageRole.USER to "long history"),
            requests().single().messages.map { it.role to it.content }
        )
        assertTrue(events.isEmpty())
    }

    @Test
    fun summarizeGetsNoTools() = exercise(scriptedChunks(listOf(NormalizedChunk.Text("x")))) {
        kernel.summarize(summarizeParams())
        val request = requests().single()
        assertTrue(request.tools.isEmpty())
        assertEquals(2048, request.maxOutputTokens)
        assertEquals("k", request.apiKey)
    }

    @Test
    fun summarizeEmptyModelYieldsEmptyString() = exercise(scriptedChunks(emptyList())) {
        assertEquals("", kernel.summarize(summarizeParams()).text)
    }

    @Test
    fun summarizeMissingKeyThrowsInvalid() = exercise(scriptedChunks(listOf(NormalizedChunk.Text("x")))) {
        try {
            kernel.summarize(summarizeParams(secrets = Secrets(deepseekApiKey = "")))
            fail("expected missing key")
        } catch (error: NuumException) {
            assertEquals(KernelErrorCode.INVALID, error.code)
            assertEquals("API key missing for deepseek", error.message)
        }
        assertTrue(requests().isEmpty())
        assertTrue(events.isEmpty())
    }

    @Test
    fun contextWatermarkFailureSentenceIsUnchanged() = exercise(scripted(emptyList())) {
        start(startParams(contextWindow = 10))
        await("context") { events.any { it is KernelEvent.Context } }
        val context = events.filterIsInstance<KernelEvent.Context>().single()
        kernel.provideContext(TurnContextResult("run-1", context.requestId))
        awaitEnd()
        val error = events.filterIsInstance<KernelEvent.Error>().single()
        assertEquals("Context capacity exhausted; execution paused without replaying tools.", error.message)
        assertEquals(KernelErrorCode.INTERNAL, error.code)
        assertEquals(RunEndStatus.ERROR, ended().status)
        assertTrue(requests().isEmpty())
    }

    @Test
    fun contextFailureAndCancellationDoNotCallTheModel() {
        for (cancel in listOf(false, true)) {
            exercise(scripted(emptyList())) {
                start(startParams(contextWindow = 10_000))
                await("context") { events.any { it is KernelEvent.Context } }
                if (cancel) {
                    kernel.cancel("run-1")
                } else {
                    val requestId = events.filterIsInstance<KernelEvent.Context>().single().requestId
                    kernel.provideContext(TurnContextResult("run-1", requestId, error = "Compaction failed"))
                }
                awaitEnd()
                assertTrue(requests().isEmpty())
                if (cancel) {
                    assertFalse(events.any { it is KernelEvent.Error })
                    assertEquals(RunEndStatus.CANCELLED, ended().status)
                } else {
                    assertEquals("Compaction failed", events.filterIsInstance<KernelEvent.Error>().single().message)
                    assertEquals(RunEndStatus.ERROR, ended().status)
                }
            }
        }
    }

    @Test
    fun turnsThatOpenWithToolsGetOneAckThenOneSilence() {
        val rounds = List(7) { index ->
            listOf(NormalizedChunk.ToolCallChunk("c$index", "step", emptyMap()))
        } + listOf(listOf(NormalizedChunk.Text("done")))
        val tools = FakeTools(defs = listOf(stepTool)) { ToolExecutionResult(ok = true, output = "ok") }
        exercise(scripted(rounds), tools) {
            start(startParams(localToolNames = listOf("step")))
            awaitEnd()
            assertEquals(2, firstOf("ack"))
            assertEquals(7, firstOf("silence"))
            val last = reminderKinds(requests().last())
            assertEquals(1, last.count { it == "ack" })
            assertEquals(1, last.count { it == "silence" })
            assertEquals(8, requests().size)
            val ack = requests().last().messages.first { it.id.startsWith("reminder-ack-") }
            assertEquals(ackSentence("SendMessage"), ack.content)
            val silence = requests().last().messages.first { it.id.startsWith("reminder-silence-") }
            assertEquals(silenceSentence("SendMessage"), silence.content)
        }
    }

    @Test
    fun voiceCallResetsTheStreakAndResultReminderReplacesFurtherAcks() {
        val tools = FakeTools(defs = listOf(stepTool)) { ToolExecutionResult(ok = true, output = "ok") }
        exercise(
            scripted(
                listOf(
                    listOf(
                        NormalizedChunk.ToolCallChunk("c1", "step", emptyMap()),
                        NormalizedChunk.ToolCallChunk("c2", "step", emptyMap())
                    ),
                    listOf(NormalizedChunk.ToolCallChunk("c3", "send_message", emptyMap())),
                    listOf(
                        NormalizedChunk.ToolCallChunk("c4", "step", emptyMap()),
                        NormalizedChunk.ToolCallChunk("c5", "step", emptyMap())
                    ),
                    listOf(NormalizedChunk.Text("done"))
                )
            ),
            tools
        ) {
            start(
                startParams(
                    localToolNames = listOf("step"),
                    delegatedTools = listOf(sendMessage),
                    voiceToolNames = listOf("send_message")
                )
            )
            await("delegate") { events.any { it is KernelEvent.ToolDelegate } }
            kernel.provideToolResult(TurnToolResult("run-1", "c3", ok = true, output = "delivered"))
            awaitEnd()
            assertEquals(1, firstOf("ack"))
            assertEquals(reminderKinds(requests()[2]), reminderKinds(requests()[1]))
            assertEquals(3, firstOf("result"))
            val last = reminderKinds(requests().last())
            assertEquals(1, last.count { it == "ack" })
            assertEquals(1, last.count { it == "result" })
            assertEquals(4, requests().size)
            val result = requests().last().messages.first { it.id.startsWith("reminder-result-") }
            assertEquals(resultSentence("send_message"), result.content)
        }
    }

    @Test
    fun voiceToolNamesSuppressTheAckReminder() = exercise(
        scripted(
            listOf(
                listOf(
                    NormalizedChunk.ToolCallChunk("c1", "send_message", emptyMap()),
                    NormalizedChunk.ToolCallChunk("c2", "send_message", emptyMap())
                ),
                listOf(NormalizedChunk.Text("done"))
            )
        )
    ) {
        start(startParams(delegatedTools = listOf(sendMessage), voiceToolNames = listOf("send_message")))
        for (id in listOf("c1", "c2")) {
            val needed = if (id == "c1") 1 else 2
            await(id) { events.filterIsInstance<KernelEvent.ToolDelegate>().size >= needed }
            kernel.provideToolResult(TurnToolResult("run-1", id, ok = true, output = "delivered"))
        }
        awaitEnd()
        for (request in requests()) assertTrue(reminderKinds(request).isEmpty())
    }

    @Test
    fun compactedContextDropsHostImagesAndKeepsTheSummary() = exercise(
        scripted(
            listOf(
                listOf(NormalizedChunk.ToolCallChunk("c", "send_message", emptyMap())),
                listOf(NormalizedChunk.Text("done"))
            )
        )
    ) {
        start(
            startParams(
                contextWindow = 10_000,
                delegatedTools = listOf(sendMessage),
                messages = listOf(
                    ChatMessage(
                        id = "uploaded-image",
                        role = MessageRole.USER,
                        content = "Look at this",
                        seq = 1,
                        createdAt = 0,
                        images = listOf(ModelImage("image/png", "aGVsbG8="))
                    )
                )
            )
        )
        await("first context") { events.any { it is KernelEvent.Context } }
        assertTrue(requests().isEmpty())
        kernel.provideContext(
            TurnContextResult("run-1", events.filterIsInstance<KernelEvent.Context>().single().requestId)
        )
        await("tool") { events.any { it is KernelEvent.ToolDelegate } }
        kernel.provideToolResult(TurnToolResult("run-1", "c", ok = true, output = "delivered"))
        await("next context") { events.filterIsInstance<KernelEvent.Context>().size == 2 }
        kernel.provideContext(
            TurnContextResult(
                runId = "run-1",
                requestId = events.filterIsInstance<KernelEvent.Context>()[1].requestId,
                messages = listOf(
                    ChatMessage(id = "summary", role = MessageRole.USER, content = "compacted history", seq = 1, createdAt = 0)
                )
            )
        )
        awaitEnd()
        assertEquals(2, requests().size)
        assertEquals(1000, requests()[0].maxOutputTokens)
        assertTrue(requests()[1].messages.any { it.id == "summary" })
        assertFalse(requests()[1].messages.any { it.id == "uploaded-image" })
        assertFalse(requests()[1].messages.any { !it.toolCalls.isNullOrEmpty() })
    }

    @Test
    fun localImageResultReachesTheNextRoundButNotTheToolOutput() {
        val tools = FakeTools(defs = listOf(readTool)) {
            ToolExecutionResult(
                ok = true,
                output = "Read image file: /tmp/pixel.png",
                images = listOf(ModelImage("image/png", "aGVsbG8="))
            )
        }
        exercise(
            scripted(
                listOf(
                    listOf(NormalizedChunk.ToolCallChunk("c-image", "read", mapOf("path" to "/tmp/pixel.png"))),
                    listOf(NormalizedChunk.Text("I can see it"))
                )
            ),
            tools
        ) {
            start(startParams(localToolNames = listOf("read")))
            awaitEnd()
            val second = requests()[1].messages
            assertEquals(MessageRole.TOOL, second[second.lastIndex - 1].role)
            assertEquals("Read image file: /tmp/pixel.png", second[second.lastIndex - 1].content)
            assertEquals(MessageRole.USER, second.last().role)
            assertEquals(listOf(ModelImage("image/png", "aGVsbG8=")), second.last().images)
            assertTrue(second.last().id.startsWith("tool-images-"))
            assertEquals(
                "Read image file: /tmp/pixel.png",
                events.filterIsInstance<KernelEvent.ToolCompleted>().single().output
            )
        }
    }

    @Test
    fun shellIdInspectionAsksToReadTheTerminalFile() {
        val shellId = "00000000-0000-4000-8000-000000000001"
        val tools = FakeTools(defs = listOf(shellTool)) { ToolExecutionResult(ok = true, output = "inspected") }
        exercise(
            scripted(
                listOf(
                    listOf(NormalizedChunk.ToolCallChunk("c-shell", "shell", mapOf("shell_id" to shellId))),
                    listOf(NormalizedChunk.Text("done"))
                )
            ),
            tools
        ) {
            start(startParams(localToolNames = listOf("shell"), toolPermission = ToolPermission.NEVER))
            awaitEnd()
            assertEquals(ToolPermission.NEVER, tools.boundPermission)
            assertEquals(
                listOf(LocalToolAction.READ_FILE to "/tmp/nuum-loop/agents/a1/terminals/$shellId.txt"),
                tools.authorizations
            )
            assertFalse(events.any { it is KernelEvent.ToolPending })
            assertEquals("shell", events.filterIsInstance<KernelEvent.ToolStarted>().single().toolName)
            assertEquals(listOf("shell"), tools.executions.map { it.name })
        }
    }

    @Test
    fun unknownToolFailsTheTurn() = exercise(
        scripted(listOf(listOf(NormalizedChunk.ToolCallChunk("c1", "ghost", emptyMap()))))
    ) {
        start(startParams())
        awaitEnd()
        val error = events.filterIsInstance<KernelEvent.Error>().single()
        assertEquals(KernelErrorCode.TOOL, error.code)
        assertTrue(error.message.contains("Unknown tool: ghost"))
        assertEquals(RunEndStatus.ERROR, ended().status)
    }

    @Test
    fun cancelSummaryDoesNotEmitATurnError() = exercise(HangingModel()) {
        coroutineScope {
            val result = async { kernel.summarize(summarizeParams()) }
            await("summary stream") { (model as HangingModel).started.isCompleted }
            kernel.cancelSummary("run-1")
            try {
                result.await()
                fail("expected cancellation")
            } catch (cancelled: CancellationException) {
                assertTrue(events.isEmpty())
            }
        }
    }

    @Test
    fun deniedPermissionIsAFailedToolResult() {
        val tools = FakeTools(
            defs = listOf(writeTool),
            verdict = { _, target -> PermissionVerdict(PermissionDecision.DENY, target) }
        ) { ToolExecutionResult(ok = true, output = "written") }
        exercise(
            scripted(
                listOf(
                    listOf(NormalizedChunk.ToolCallChunk("c1", "write", mapOf("path" to "/tmp/secret.txt"))),
                    listOf(NormalizedChunk.Text("ok"))
                )
            ),
            tools
        ) {
            start(startParams(localToolNames = listOf("write")))
            awaitEnd()
            assertEquals(
                "Permission denied for write-file /tmp/secret.txt",
                events.filterIsInstance<KernelEvent.ToolCompleted>().single().output
            )
            assertTrue(tools.executions.isEmpty())
            assertFalse(events.any { it is KernelEvent.ToolStarted })
            assertEquals(RunEndStatus.IDLE, ended().status)
        }
    }

    @Test
    fun neverRefusalSetsPermissionAndSkipsExecute() {
        val tools = FakeTools(
            defs = listOf(writeTool),
            verdict = { _, target -> PermissionVerdict(PermissionDecision.ASK, target) }
        ) { ToolExecutionResult(ok = true, output = "written") }
        exercise(
            scripted(
                listOf(
                    listOf(NormalizedChunk.ToolCallChunk("c1", "write", mapOf("path" to "/tmp/needs-approval.txt"))),
                    listOf(NormalizedChunk.Text("ok"))
                )
            ),
            tools
        ) {
            start(startParams(localToolNames = listOf("write"), toolPermission = ToolPermission.ASK))
            await("approval") { events.any { it is KernelEvent.ToolPending } }
            kernel.approveTool(TurnToolDecision("run-1", "c1", ToolResolution.NEVER))
            awaitEnd()
            assertEquals(listOf(ToolPermission.NEVER), tools.permissionUpdates)
            assertEquals(listOf(LocalToolAction.WRITE_FILE to "/tmp/needs-approval.txt"), tools.refusals)
            assertTrue(tools.executions.isEmpty())
            assertEquals("User denied this tool call.", events.filterIsInstance<KernelEvent.ToolCompleted>().single().output)
            assertEquals(RunEndStatus.IDLE, ended().status)
        }
    }

    @Test
    fun userDenialIsAFailedToolResult() {
        val tools = FakeTools(
            defs = listOf(writeTool),
            verdict = { _, target -> PermissionVerdict(PermissionDecision.ASK, target) }
        )
        exercise(
            scripted(
                listOf(
                    listOf(NormalizedChunk.ToolCallChunk("c1", "write", mapOf("path" to "/tmp/needs-approval.txt"))),
                    listOf(NormalizedChunk.Text("ok"))
                )
            ),
            tools
        ) {
            start(startParams(localToolNames = listOf("write"), toolPermission = ToolPermission.ASK))
            await("approval") { events.any { it is KernelEvent.ToolPending } }
            val pending = events.filterIsInstance<KernelEvent.ToolPending>().single()
            assertEquals(LocalToolAction.WRITE_FILE, pending.action)
            assertEquals("/tmp/needs-approval.txt", pending.target)
            assertTrue(pending.mutating)
            kernel.denyTool(TurnToolDecision("run-1", "c1", ToolResolution.DENY))
            awaitEnd()
            assertEquals("User denied this tool call.", events.filterIsInstance<KernelEvent.ToolCompleted>().single().output)
            assertTrue(tools.executions.isEmpty())
            assertEquals(listOf(LocalToolAction.WRITE_FILE to "/tmp/needs-approval.txt"), tools.refusals)
            assertEquals(RunEndStatus.IDLE, ended().status)
            assertFalse(events.any { it is KernelEvent.Error })
        }
    }

    @Test
    fun aSecondStartWhileRunningIsBusy() = exercise(HangingModel()) {
        start(startParams())
        await("stream") { (model as HangingModel).started.isCompleted }
        try {
            kernel.start(startParams())
            fail("expected busy")
        } catch (error: NuumException) {
            assertEquals(KernelErrorCode.TURN_BUSY, error.code)
            assertEquals("Run run-1 is already running", error.message)
        }
        kernel.cancel("run-1")
        awaitEnd()
    }

    @Test
    fun estimateModelTokensMatchesTheMacBudget() {
        val message = ChatMessage(id = "u1", role = MessageRole.USER, content = "go", seq = 0, createdAt = 1)
        assertEquals(30, estimateModelTokens(listOf(message)))
        val wide = message.copy(content = "你好")
        assertEquals(33, estimateModelTokens(listOf(wide)))
        val withImage = message.copy(images = listOf(ModelImage("image/png", "aGVsbG8=")))
        assertEquals(30 + 8192, estimateModelTokens(listOf(withImage)))
    }
}

private class Harness(
    scope: CoroutineScope,
    val model: ModelPort,
    val tools: FakeTools
) {
    val events = mutableListOf<KernelEvent>()
    val kernel = Kernel(model, tools, scope)

    init {
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            kernel.events.collect { events.add(it) }
        }
    }

    suspend fun start(params: TurnStartParams) = kernel.start(params)

    suspend fun await(what: String, predicate: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 3_000
        while (System.currentTimeMillis() < deadline) {
            if (predicate()) return
            delay(2)
        }
        error("timed out waiting for $what; events=${events.joinToString { it.name }}")
    }

    suspend fun awaitEnd() = await("turn end") { events.any { it is KernelEvent.Ended } }

    fun ended(): KernelEvent.Ended = events.filterIsInstance<KernelEvent.Ended>().last()

    fun requests(): List<NormalizedChatRequest> = when (val port = model) {
        is ScriptedModel -> port.requests
        else -> error("model does not record requests")
    }

    fun modelRequests(): Int = when (val port = model) {
        is ScriptedModel -> port.requests.size
        is HangingModel -> port.calls
        else -> error("model does not record calls")
    }

    fun firstOf(kind: String): Int = requests().indexOfFirst { kind in reminderKinds(it) }
}

private fun exercise(
    model: ModelPort,
    tools: FakeTools = FakeTools(),
    body: suspend Harness.() -> Unit
) = runBlocking {
    withTimeout(15_000) {
        val harness = Harness(this, model, tools)
        try {
            harness.body()
        } finally {
            coroutineContext.cancelChildren()
        }
    }
}

private class ScriptedModel(private val rounds: List<List<NormalizedChunk>>) : ModelPort {
    val requests = mutableListOf<NormalizedChatRequest>()
    private var round = 0

    override fun streamChat(request: NormalizedChatRequest): Flow<NormalizedChunk> = flow {
        requests += request.copy(messages = request.messages.toList(), tools = request.tools.toList())
        val chunks = rounds.getOrElse(round) { listOf(NormalizedChunk.Text("")) }
        round += 1
        for (chunk in chunks) emit(chunk)
    }
}

private class HangingModel : ModelPort {
    val started = CompletableDeferred<Unit>()
    var calls = 0

    override fun streamChat(request: NormalizedChatRequest): Flow<NormalizedChunk> = flow {
        calls += 1
        emit(NormalizedChunk.Text("partial"))
        if (!started.isCompleted) started.complete(Unit)
        suspendCancellableCoroutine<Unit> { }
    }
}

private class FakeTools(
    private val defs: List<ToolDefinition> = emptyList(),
    private val verdict: (LocalToolAction, String) -> PermissionVerdict = { _, target ->
        PermissionVerdict(PermissionDecision.ALLOW, target)
    },
    private val onExecute: (ToolCall) -> ToolExecutionResult = {
        error("unexpected execute ${it.name}")
    }
) : ToolBackend {
    val binds = mutableListOf<String>()
    val releases = mutableListOf<String>()
    val authorizations = mutableListOf<Pair<LocalToolAction, String>>()
    val executions = mutableListOf<ToolCall>()
    val refusals = mutableListOf<Pair<LocalToolAction, String>>()
    val permissionUpdates = mutableListOf<ToolPermission>()
    var boundPermission: ToolPermission? = null

    override fun definitions(): List<ToolDefinition> = defs

    override fun bind(
        runId: String,
        roots: ToolRoots,
        permission: ToolPermission,
        approvals: List<ToolApproval>,
        refused: List<ToolApproval>
    ) {
        binds += runId
        boundPermission = permission
    }

    override suspend fun authorize(runId: String, action: LocalToolAction, target: String): PermissionVerdict {
        authorizations += action to target
        return verdict(action, target)
    }

    override fun grantOnce(runId: String, action: LocalToolAction, target: String) = Unit

    override fun refuse(runId: String, action: LocalToolAction, target: String) {
        refusals += action to target
    }

    override fun setPermission(runId: String, permission: ToolPermission) {
        permissionUpdates += permission
    }

    override suspend fun execute(runId: String, call: ToolCall): ToolExecutionResult {
        executions += call
        return onExecute(call)
    }

    override fun release(runId: String) {
        releases += runId
    }
}

private fun scripted(rounds: List<List<NormalizedChunk>>): ScriptedModel = ScriptedModel(rounds)

private fun scriptedChunks(chunks: List<NormalizedChunk>): ScriptedModel = ScriptedModel(listOf(chunks))

private fun reminderKinds(request: NormalizedChatRequest): List<String> =
    request.messages.mapNotNull { message ->
        if (!message.id.startsWith("reminder-")) null else message.id.split("-")[1]
    }

private fun KernelEvent.runId(): String = when (this) {
    is KernelEvent.Context -> runId
    is KernelEvent.Delta -> runId
    is KernelEvent.ToolPending -> runId
    is KernelEvent.ToolStarted -> runId
    is KernelEvent.ToolDelegate -> runId
    is KernelEvent.ToolCompleted -> runId
    is KernelEvent.Error -> runId
    is KernelEvent.Ended -> runId
}

private val sendMessage = ToolDefinition(
    name = "send_message",
    description = "post a message",
    inputSchema = mapOf("type" to "object", "properties" to mapOf("text" to mapOf("type" to "string"))),
    mutating = false
)

private val stepTool = ToolDefinition(
    name = "step",
    description = "one unit of silent work",
    inputSchema = mapOf("type" to "object", "properties" to emptyMap<String, Any?>()),
    mutating = false,
    action = LocalToolAction.READ_FILE
)

private val readTool = ToolDefinition(
    name = "read",
    description = "read an image",
    inputSchema = mapOf("type" to "object", "properties" to mapOf("path" to mapOf("type" to "string"))),
    mutating = false,
    action = LocalToolAction.READ_FILE
)

private val writeTool = ToolDefinition(
    name = "write",
    description = "w",
    inputSchema = mapOf("type" to "object", "properties" to mapOf("path" to mapOf("type" to "string"))),
    mutating = true,
    action = LocalToolAction.WRITE_FILE
)

private val shellTool = ToolDefinition(
    name = "shell",
    description = "inspect a shell",
    inputSchema = mapOf("type" to "object", "properties" to mapOf("shell_id" to mapOf("type" to "string"))),
    mutating = true,
    action = LocalToolAction.RUN_COMMAND
)

private fun startParams(
    runId: String = "run-1",
    messages: List<ChatMessage> = listOf(ChatMessage("u1", MessageRole.USER, "go", 0, 1)),
    secrets: Secrets = Secrets(deepseekApiKey = "k"),
    contextWindow: Int? = null,
    localToolNames: List<String> = emptyList(),
    delegatedTools: List<ToolDefinition> = emptyList(),
    voiceToolNames: List<String> = listOf("SendMessage"),
    toolPermission: ToolPermission = ToolPermission.ALWAYS
) = TurnStartParams(
    runId = runId,
    messages = messages,
    model = ModelRef(ProviderId.DEEPSEEK, "deepseek-chat"),
    roots = ToolRoots(
        home = "/tmp",
        project = null,
        scratch = "/tmp/nuum-loop/agents/a1/scratch",
        terminals = "/tmp/nuum-loop/agents/a1/terminals",
        denied = emptyList()
    ),
    toolPermission = toolPermission,
    localToolNames = localToolNames,
    secrets = secrets,
    contextWindow = contextWindow,
    delegatedTools = delegatedTools,
    voiceToolNames = voiceToolNames
)

private fun summarizeParams(secrets: Secrets = Secrets(deepseekApiKey = "k")) = SummarizeRunParams(
    runId = "run-1",
    systemPrompt = "You summarize.",
    messages = listOf(ChatMessage("u1", MessageRole.USER, "long history", 1, 1)),
    model = ModelRef(ProviderId.DEEPSEEK, "deepseek-chat"),
    secrets = secrets
)

private fun ackSentence(voice: String): String =
    "<system_reminder>You opened this turn by calling tools without first acknowledging the user, " +
        "so they are watching silence and may think the app froze. Call $voice right now — a real tool " +
        "call, not text you write — with a one-line acknowledgement before any further tool call, then continue the work.</system_reminder>"

private fun silenceSentence(voice: String): String =
    "<system_reminder>You have made several tool calls without a message, so the user is currently " +
        "watching silence. Call $voice now with a brief, specific update on what you are doing or what " +
        "you just found, then continue.</system_reminder>"

private fun resultSentence(voice: String): String =
    "<system_reminder>The user cannot see tool output or your thinking — only $voice reaches them. " +
        "If you have produced a result or finished what they asked, send it with $voice before continuing " +
        "or ending the turn; if you are still mid-task, keep working and send it once you have it.</system_reminder>"
