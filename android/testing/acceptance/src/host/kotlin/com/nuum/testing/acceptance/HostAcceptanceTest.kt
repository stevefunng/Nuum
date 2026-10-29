package com.nuum.testing.acceptance

import android.app.Application
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.nuum.contracts.AgentCreateParams
import com.nuum.contracts.AgentSendParams
import com.nuum.contracts.AgentStatus
import com.nuum.contracts.AttachmentUpload
import com.nuum.contracts.HostErrorCode
import com.nuum.contracts.HostEvent
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.Language
import com.nuum.contracts.MessageRole
import com.nuum.contracts.ModelPort
import com.nuum.contracts.NormalizedChatRequest
import com.nuum.contracts.NormalizedChunk
import com.nuum.contracts.NuumException
import com.nuum.contracts.NuumPaths
import com.nuum.contracts.OutboundMessage
import com.nuum.contracts.ProactiveConfigureParams
import com.nuum.contracts.SecretStore
import com.nuum.contracts.Secrets
import com.nuum.contracts.SettingsPatch
import com.nuum.contracts.ThemePreference
import com.nuum.contracts.ToolResolution
import com.nuum.contracts.TranscriptEvent
import com.nuum.contracts.TranscriptQuery
import com.nuum.contracts.WorkCreateParams
import com.nuum.contracts.WorkEventBody
import com.nuum.contracts.WorkKind
import com.nuum.contracts.WorkMemberAttachParams
import com.nuum.contracts.WorkPostMessageParams
import com.nuum.contracts.WorkRole
import com.nuum.contracts.WorkUpdateParams
import com.nuum.graph.AppGraph
import java.io.File
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Host-driven acceptance. These run on the JVM with Robolectric because the
 * emulator on this machine cannot install a package (see the acceptance log).
 * The fake [ModelPort] is passed into [AppGraph]; production leaves that null.
 */
@RunWith(RobolectricTestRunner::class)
@Config(application = Application::class, sdk = [34])
class HostAcceptanceTest {
    @Test
    fun scenario1_coldStartHasNoRunningNunu() = runAcceptance {
        assertTrue(graph.agentPort.list().isEmpty())
        val created = graph.agentPort.create(AgentCreateParams(name = "Idle"))
        assertEquals(AgentStatus.IDLE, graph.agentPort.get(created.profile.id).view.runtime.status)
        assertTrue(graph.agentPort.list().none { it.runtime.status == AgentStatus.RUNNING })
    }

    @Test
    fun scenario2_profileSurvivesReopen() = runAcceptance {
        val created = graph.agentPort.create(
            AgentCreateParams(
                name = "Pebble",
                avatarColor = "honey",
                avatarShape = "droplet",
                avatarMaterial = "glass"
            )
        )
        val id = created.profile.id
        close()
        val again = AppGraph(context, model, secrets)
        try {
            again.awaitReady()
            val profile = again.agentPort.get(id).view.profile
            assertEquals("Pebble", profile.name)
            assertEquals("honey", profile.avatarColor)
            assertEquals("droplet", profile.avatarShape)
            assertEquals("glass", profile.avatarMaterial)
            val file = File(context.filesDir, "nuum/${NuumPaths.profilePath(id)}")
            val text = file.readText()
            assertTrue(text.contains("Pebble"))
            assertTrue(text.contains("honey"))
            assertTrue(text.contains("droplet"))
            assertTrue(text.contains("glass"))
        } finally {
            again.close()
        }
    }

    @Test
    fun scenario3_missingKeyIsUnderstandableAndStaysOutOfTheTranscript() = runAcceptance {
        val created = graph.agentPort.create(AgentCreateParams(name = "Locked"))
        try {
            graph.agentPort.send(AgentSendParams(created.profile.id, "hello $PLANTED_KEY"))
            fail("expected 2004")
        } catch (error: NuumException) {
            assertEquals(HostErrorCode.NO_API_KEY, error.code)
            assertTrue(error.message.contains("API key"))
            assertFalse(error.message.contains(PLANTED_KEY))
        }
        val text = transcriptFile(created.profile.id)
        assertFalse(text.contains(PLANTED_KEY))
        assertFalse(text.contains("sk-"))
        assertTrue(graph.agentPort.transcript(TranscriptQuery(created.profile.id)).entries.isEmpty())
    }

    @Test
    fun scenario4_sendMessageIsTheVisibleTranscriptBody() = runAcceptance {
        secrets.current = Secrets(deepseekApiKey = PLANTED_KEY)
        model.respond = { request ->
            val last = request.messages.lastOrNull()
            when {
                last?.role == MessageRole.TOOL && last.name == "SendMessage" -> emptyList()
                last?.role == MessageRole.TOOL -> listOf(model.send("ack"))
                else -> listOf(
                    NormalizedChunk.Text(SCRATCHPAD),
                    model.send(VISIBLE_REPLY)
                )
            }
        }
        val id = graph.agentPort.create(AgentCreateParams(name = "Voice")).profile.id
        graph.agentPort.send(AgentSendParams(id, "hello"))
        waitIdle(id)
        val entries = graph.agentPort.transcript(TranscriptQuery(id)).entries
        val bodies = entries.filterIsInstance<TranscriptEvent.Message>().map { it.payload }
        val texts = bodies.filterIsInstance<OutboundMessage.Text>().map { it.content }
        assertEquals(listOf(VISIBLE_REPLY), texts)
        assertFalse(texts.contains(SCRATCHPAD))
        assertFalse(transcriptFile(id).contains(PLANTED_KEY))
    }

    @Test
    fun scenario5_denyThenAlwaysAndSecretsStaySealed() = runAcceptance {
        secrets.current = Secrets(deepseekApiKey = PLANTED_KEY)
        val note = File(context.filesDir, "nuum/outside-scratch.txt")
        val sealed = File(context.noBackupFilesDir, "secrets.bin")
        model.respond = { request ->
            val last = request.messages.lastOrNull()
            val user = request.messages.filter { it.role == MessageRole.USER }.joinToString("\n") { it.content }
            when {
                last?.role == MessageRole.TOOL && last.name == "SendMessage" -> emptyList()
                last?.role == MessageRole.TOOL -> listOf(model.send("model saw: ${last.content}"))
                "acceptance-secrets" in user -> listOf(model.tool("write", mapOf("path" to sealed.absolutePath, "content" to NOTE_TEXT)))
                else -> listOf(model.tool("write", mapOf("path" to note.absolutePath, "content" to NOTE_TEXT)))
            }
        }
        val id = graph.agentPort.create(AgentCreateParams(name = "Writer")).profile.id
        graph.agentPort.send(AgentSendParams(id, "acceptance-write the note"))
        val denied = awaitPending()
        graph.agentPort.deny(id, denied.toolCallId, ToolResolution.DENY)
        waitIdle(id)
        assertTrue(model.requests.any { request ->
            request.messages.any { it.role == MessageRole.TOOL && it.content.contains("User denied this tool call.") }
        })
        assertFalse(note.exists() && note.readText().contains(NOTE_TEXT))

        val beforeAlways = pendingCount()
        graph.agentPort.send(AgentSendParams(id, "acceptance-write the note again"))
        val allowed = awaitPending(after = beforeAlways)
        graph.agentPort.approve(id, allowed.toolCallId, ToolResolution.ALWAYS)
        waitIdle(id)
        assertEquals(NOTE_TEXT, note.readText())

        val beforeRepeat = pendingCount()
        graph.agentPort.send(AgentSendParams(id, "acceptance-write the note once more"))
        waitIdle(id)
        assertEquals(beforeRepeat, pendingCount())
        assertTrue(note.readText().contains(NOTE_TEXT))

        graph.agentPort.send(AgentSendParams(id, "acceptance-secrets now"))
        waitIdle(id)
        assertFalse(sealed.exists() && sealed.readBytes().decodeToString().contains(NOTE_TEXT))
        assertTrue(model.requests.any { request ->
            request.messages.any { message ->
                message.role == MessageRole.TOOL && (
                    message.content.contains("protected") ||
                        message.content.contains("outside") ||
                        message.content.contains("Permission denied")
                    )
            }
        })
        assertFalse(transcriptFile(id).contains(PLANTED_KEY))
    }

    @Test
    fun scenario6_overLimitAttachmentDoesNotSend() = runAcceptance {
        secrets.current = Secrets(deepseekApiKey = PLANTED_KEY)
        val id = graph.agentPort.create(AgentCreateParams(name = "Clip")).profile.id
        val uploads = List(6) { index -> AttachmentUpload("f$index.txt", "text/plain", byteArrayOf(1)) }
        try {
            graph.agentPort.send(AgentSendParams(id, "too many", uploads))
            fail("expected the attachment ceiling")
        } catch (error: NuumException) {
            assertEquals(KernelErrorCode.INVALID, error.code)
            assertTrue(error.message.contains("5"))
            assertFalse(error.message.contains(PLANTED_KEY))
        }
        assertTrue(graph.agentPort.transcript(TranscriptQuery(id)).entries.isEmpty())
        assertEquals(0, model.requests.size)
    }

    @Test
    fun scenario7_roomUpgradeShowsModelCreateTaskAndNoManualControl() = runAcceptance {
        secrets.current = Secrets(deepseekApiKey = PLANTED_KEY)
        model.respond = { request ->
            val names = request.tools.map { it.name }.toSet()
            val last = request.messages.lastOrNull()
            when {
                "CreateTask" !in names -> emptyList()
                last?.role == MessageRole.TOOL -> emptyList()
                else -> listOf(
                    model.tool(
                        "CreateTask",
                        mapOf("title" to "Lane card", "description" to "from the model")
                    )
                )
            }
        }
        val agentId = graph.agentPort.create(AgentCreateParams(name = "Mason")).profile.id
        val work = graph.workPort.create(WorkCreateParams(name = "Launch", kind = WorkKind.ROOM))
        graph.workPort.attachMember(
            WorkMemberAttachParams(work.id, agentId, expectedRevision = 0, role = WorkRole.WORKER)
        )
        graph.workPort.postMessage(WorkPostMessageParams(work.id, "hello room"))
        waitUntil { discussionCount(work.id) >= 1 }
        waitIdle(agentId)
        assertTrue(graph.workPort.get(work.id).tasks.isEmpty())
        assertEquals(WorkKind.ROOM, graph.workPort.get(work.id).profile.kind)

        graph.workPort.update(WorkUpdateParams(work.id, kind = WorkKind.WORK))
        assertEquals(WorkKind.WORK, graph.workPort.get(work.id).profile.kind)
        graph.workPort.postMessage(WorkPostMessageParams(work.id, "please make a card"))
        waitUntil { graph.workPort.get(work.id).tasks.any { it.task.title == "Lane card" } }
        waitIdle(agentId)
        val titles = graph.workPort.get(work.id).tasks.map { it.task.title }
        assertEquals(listOf("Lane card"), titles)
        assertNoManualCreateTaskControl()
    }

    @Test
    fun scenario8_discussionCanStopAndThenContinue() = runAcceptance {
        secrets.current = Secrets(deepseekApiKey = PLANTED_KEY)
        val phase = AtomicInteger(0)
        model.respond = { request ->
            val last = request.messages.lastOrNull()
            if (phase.get() == 0) {
                error("hang")
            }
            when {
                last?.role == MessageRole.TOOL && last.name == "SendMessage" -> emptyList()
                else -> listOf(model.send("continued after interrupt"))
            }
        }
        model.hangUntilCancelled = true
        val agentId = graph.agentPort.create(AgentCreateParams(name = "Talker")).profile.id
        val work = graph.workPort.create(WorkCreateParams(name = "Room", kind = WorkKind.ROOM))
        graph.workPort.attachMember(WorkMemberAttachParams(work.id, agentId, 0, WorkRole.WORKER))
        graph.workPort.postMessage(WorkPostMessageParams(work.id, "discuss this"))
        waitRunning(agentId)
        graph.workPort.stopDiscussion(work.id)
        waitIdle(agentId)
        model.hangUntilCancelled = false
        phase.set(1)
        graph.workPort.postMessage(WorkPostMessageParams(work.id, "continue please"))
        waitUntil {
            graph.workPort.get(work.id).events.any { event ->
                val body = event.body
                body is WorkEventBody.ChatPosted && body.body == "continued after interrupt"
            }
        }
        waitIdle(agentId)
        val said = graph.workPort.get(work.id).events.any { event ->
            val body = event.body
            body is WorkEventBody.ChatPosted && body.body == "continued after interrupt"
        }
        assertTrue(graph.workPort.get(work.id).events.joinToString { it.body.toString() }, said)
        assertEquals(AgentStatus.IDLE, graph.agentPort.get(agentId).view.runtime.status)
    }

    @Test
    fun scenario9_reopenIsNotRunningAndKeepsTheMessage() = runAcceptance {
        secrets.current = Secrets(deepseekApiKey = PLANTED_KEY)
        model.respond = { request ->
            val last = request.messages.lastOrNull()
            when {
                last?.role == MessageRole.TOOL && last.name == "SendMessage" -> emptyList()
                else -> listOf(model.send("kept"))
            }
        }
        val id = graph.agentPort.create(AgentCreateParams(name = "Keeper")).profile.id
        graph.agentPort.send(AgentSendParams(id, "remember this"))
        waitIdle(id)
        assertTrue(transcriptFile(id).contains("kept"))
        close()
        val again = AppGraph(context, RecordingModel(), secrets)
        try {
            again.awaitReady()
            val view = again.agentPort.get(id).view
            assertEquals(AgentStatus.IDLE, view.runtime.status)
            assertFalse(view.runtime.status == AgentStatus.RUNNING)
            val texts = again.agentPort.transcript(TranscriptQuery(id)).entries
                .filterIsInstance<TranscriptEvent.Message>()
                .map { (it.payload as OutboundMessage.Text).content }
            assertEquals(listOf("kept"), texts)
        } finally {
            again.close()
        }
    }

    @Test
    fun scenario10_languageThemeAndProactiveActions() = runAcceptance {
        val before = graph.settingsPort.get()
        assertNotNull(before.language)
        val updated = graph.settingsPort.set(
            SettingsPatch(language = Language.EN, theme = ThemePreference.LIGHT)
        )
        assertEquals(Language.EN, updated.language)
        assertEquals(ThemePreference.LIGHT, updated.theme)
        assertEquals(Language.EN, graph.settingsPort.get().language)
        assertEquals(ThemePreference.LIGHT, graph.settingsPort.get().theme)
        val proactive = graph.proactivePort.get()
        assertFalse(proactive.actionsAvailable)
        val revision = proactive.agents.firstOrNull()?.policy?.revision ?: 0
        val enabled = graph.proactivePort.configure(
            ProactiveConfigureParams(expectedRevision = revision, enabled = true)
        )
        assertFalse(enabled.actionsAvailable)
        val agentId = enabled.defaultAgentId ?: enabled.agents.single().agentId
        val checked = graph.proactivePort.check(agentId)
        assertFalse(checked.actionsAvailable)
        close()
        val again = AppGraph(context, model, secrets)
        try {
            again.awaitReady()
            assertEquals(Language.EN, again.settingsPort.get().language)
            assertEquals(ThemePreference.LIGHT, again.settingsPort.get().theme)
        } finally {
            again.close()
        }
    }
}

class RecordingModel : ModelPort {
    val requests = Collections.synchronizedList(mutableListOf<NormalizedChatRequest>())
    var respond: (NormalizedChatRequest) -> List<NormalizedChunk> = { emptyList() }
    @Volatile var hangUntilCancelled: Boolean = false
    private val ids = AtomicInteger()

    override fun streamChat(request: NormalizedChatRequest): Flow<NormalizedChunk> = flow {
        requests += request
        if (hangUntilCancelled) {
            kotlinx.coroutines.awaitCancellation()
        }
        respond(request).forEach { emit(it) }
    }

    fun send(content: String): NormalizedChunk = tool("SendMessage", mapOf("type" to "text", "content" to content))

    fun tool(name: String, arguments: Map<String, Any?>): NormalizedChunk.ToolCallChunk =
        NormalizedChunk.ToolCallChunk("c-${ids.incrementAndGet()}", name, arguments)
}

private class MemorySecrets(initial: Secrets = Secrets()) : SecretStore {
    var current: Secrets = initial
    override suspend fun read(): Secrets = current
    override suspend fun write(secrets: Secrets) {
        current = secrets
    }
}

private class Harness(
    val context: Context,
    val model: RecordingModel,
    val secrets: MemorySecrets
) {
    val graph: AppGraph = AppGraph(context, modelOverride = model, secretStoreOverride = secrets)
    private val events = Collections.synchronizedList(mutableListOf<HostEvent>())
    private var collector: Job? = null

    suspend fun start() {
        collector = CoroutineScope(Dispatchers.Default).launch {
            graph.agentPort.events.collect { events += it }
        }
        graph.awaitReady()
        yield()
        delay(30)
    }

    fun close() {
        collector?.cancel()
        collector = null
        graph.close()
    }

    suspend fun waitIdle(agentId: String) {
        withTimeout(20_000) {
            while (graph.agentPort.get(agentId).view.runtime.status == AgentStatus.RUNNING) delay(20)
        }
    }

    suspend fun waitUntil(ready: suspend () -> Boolean) {
        withTimeout(20_000) {
            while (!ready()) delay(20)
        }
    }

    suspend fun discussionCount(workId: String): Int =
        graph.workPort.get(workId).events.count { it.body is com.nuum.contracts.WorkEventBody.DiscussionFinished }

    suspend fun waitRunning(agentId: String) {
        withTimeout(20_000) {
            while (graph.agentPort.get(agentId).view.runtime.status != AgentStatus.RUNNING) delay(20)
        }
    }

    suspend fun awaitPending(after: Int = 0): HostEvent.AgentToolPending = withTimeout(20_000) {
        while (true) {
            val pending = synchronized(events) { events.filterIsInstance<HostEvent.AgentToolPending>() }
            if (pending.size > after) return@withTimeout pending.last()
            delay(20)
        }
        error("unreachable")
    }

    fun pendingCount(): Int = synchronized(events) { events.count { it is HostEvent.AgentToolPending } }

    fun transcriptFile(agentId: String): String {
        val file = File(context.filesDir, "nuum/${NuumPaths.transcriptPath(agentId)}")
        return if (file.isFile) file.readText() else ""
    }
}

private fun runAcceptance(
    model: RecordingModel = RecordingModel(),
    secrets: MemorySecrets = MemorySecrets(),
    block: suspend Harness.() -> Unit
) = runBlocking {
    val context = ApplicationProvider.getApplicationContext<Context>()
    val harness = Harness(context, model, secrets)
    try {
        harness.start()
        harness.block()
    } finally {
        harness.close()
    }
}

private fun assertNoManualCreateTaskControl() {
    val root = File("../feature/work/src/main")
    val banned = listOf("New task", "Create task", "A new task", "新建任务", "创建任务")
    val hits = root.walkTopDown()
        .filter { it.isFile && (it.extension == "kt" || it.extension == "xml") }
        .flatMap { file ->
            file.readLines().mapIndexedNotNull { index, line ->
                val label = banned.firstOrNull { line.contains(it) } ?: return@mapIndexedNotNull null
                "${file.path}:${index + 1} $label"
            }.asSequence()
        }
        .toList()
    assertTrue(hits.joinToString(), hits.isEmpty())
}

private const val PLANTED_KEY = "sk-acceptance-not-a-real-key"
private const val VISIBLE_REPLY = "Visible from SendMessage"
private const val SCRATCHPAD = "scratchpad-not-the-body"
private const val NOTE_TEXT = "accepted-note"
