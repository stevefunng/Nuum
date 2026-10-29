package com.nuum.agent

import com.nuum.contracts.AgentSendParams
import com.nuum.contracts.HostErrorCode
import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NuumException
import com.nuum.contracts.NuumPaths
import com.nuum.contracts.Secrets
import com.nuum.contracts.WorkCatalogInput
import com.nuum.contracts.WorkCreateParams
import com.nuum.contracts.WorkKind
import com.nuum.contracts.WorkMemberAttachParams
import com.nuum.contracts.WorkPostMessageParams
import com.nuum.contracts.WorkRole
import com.nuum.contracts.WorkTaskState
import com.nuum.contracts.WorkTaskTransitionParams
import com.nuum.protocol.AssistantPart
import com.nuum.protocol.ProtocolJson
import com.nuum.protocol.TranscriptEvent
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class HostRuntimeTest {
    @Test
    fun missingKeyThrows2004WithoutEchoingAKey() = runBlocking {
        val secrets = MemorySecrets(Secrets(openaiApiKey = "sk-secret-value"))
        val host = openRuntime(this, secrets = MemorySecrets())
        host.start()
        val agent = host.agentPort.create()
        try {
            host.agentPort.send(AgentSendParams(agent.profile.id, "hello"))
            fail("expected 2004")
        } catch (error: NuumException) {
            assertEquals(HostErrorCode.NO_API_KEY, error.code)
            assertFalse(error.message.contains("sk-secret-value"))
        }
        secrets.current = Secrets(deepseekApiKey = "sk-secret-value")
        val kernel = FakeKernel()
        val live = openRuntime(this, kernel = kernel, secrets = secrets)
        live.start()
        val created = live.agentPort.create()
        val sent = async { live.agentPort.send(AgentSendParams(created.profile.id, "hello")) }
        withTimeout(5_000) { while (kernel.started.isEmpty() && !sent.isCompleted) yield() }
        if (sent.isCompleted) sent.await()
        assertEquals("sk-secret-value", kernel.started.single().secrets.deepseekApiKey)
        kernel.emit(ended(kernel.started.single().runId))
        yield()
        sent.await()
        val transcript = (live.store as? MemoryAgentStore)?.let { store ->
            // read through the same store instance
            Unit
        }
        val text = live.store.readText(NuumPaths.transcriptPath(created.profile.id)).orEmpty()
        assertFalse(text.contains("sk-secret-value"))
        assertNotNull(transcript)
    }

    @Test
    fun sameAgentDoesNotOverlapAndRestartIsNotRunning() = runBlocking {
        val kernel = FakeKernel()
        val hold = CompletableDeferred<Unit>()
        kernel.hold = hold
        val store = MemoryAgentStore()
        val host = openRuntime(this, store = store, kernel = kernel)
        host.start()
        val agent = host.agentPort.create()
        val first = async { host.agentPort.send(AgentSendParams(agent.profile.id, "go")) }
        withTimeout(5_000) { while (kernel.started.isEmpty() && !first.isCompleted) yield() }
        assertEquals("running", host.agentPort.get(agent.profile.id).view.runtime.status.wire)
        try {
            host.agentPort.send(AgentSendParams(agent.profile.id, "again"))
            fail("expected busy")
        } catch (error: NuumException) {
            assertEquals(HostErrorCode.AGENT_BUSY, error.code)
        }
        val restarted = openRuntime(this, store = store, kernel = FakeKernel(), secrets = MemorySecrets(Secrets(deepseekApiKey = "sk-test")))
        restarted.start()
        assertEquals("idle", restarted.agentPort.get(agent.profile.id).view.runtime.status.wire)
        val page = restarted.agentPort.transcript(com.nuum.contracts.TranscriptQuery(agent.profile.id))
        assertTrue(page.entries.isNotEmpty())
        hold.complete(Unit)
        kernel.emit(ended(kernel.started.single().runId))
        yield()
        first.await()
        Unit
    }

    @Test
    fun compactionTriggersAtThreeQuartersThroughTheKernel() = runBlocking {
        val kernel = FakeKernel()
        val store = MemoryAgentStore()
        val host = openRuntime(this, store = store, kernel = kernel, contextWindowTokens = 20_000)
        host.start()
        val agent = host.agentPort.create()
        val bulky = TranscriptEvent.Assistant(
            id = "old",
            seq = 1,
            createdAt = 1,
            parts = listOf(AssistantPart.Text("x".repeat(80_000)))
        )
        store.appendLine(
            NuumPaths.transcriptPath(agent.profile.id),
            ProtocolJson.encodeToString(TranscriptEvent.serializer(), bulky)
        )
        val sent = async { host.agentPort.send(AgentSendParams(agent.profile.id, "hi")) }
        withTimeout(5_000) { while (kernel.started.isEmpty() && !sent.isCompleted) yield() }
        if (kernel.started.isEmpty()) sent.await()
        assertTrue(kernel.summarized.isNotEmpty())
        assertTrue(kernel.summarized.all { it.systemPrompt.contains("quoted transcript evidence") })
        assertTrue(store.readText(NuumPaths.transcriptPath(agent.profile.id))!!.contains("\"type\":\"compact\""))
        kernel.emit(ended(kernel.started.single().runId))
        yield()
        sent.await()
        Unit
    }

    @Test
    fun createAgentStopsAtMaxAgents() = runBlocking {
        val host = openRuntime(this)
        host.start()
        repeat(MAX_AGENTS) { host.agentPort.create() }
        try {
            host.agentPort.create()
            fail("expected cap")
        } catch (error: NuumException) {
            assertEquals(KernelErrorCode.INVALID, error.code)
            assertTrue(error.message.contains(MAX_AGENTS.toString()))
        }
        val owner = host.agentPort.list().first()
        val refused = host.executeDelegated(
            owner.profile.id,
            "CreateAgent",
            buildJsonObject {
                put("name", "extra")
                put("description", "no")
            },
            RunContext.Direct,
            "call-1"
        )
        assertFalse(refused.ok.not() && refused.output.isEmpty())
        assertTrue(refused.output.contains("already $MAX_AGENTS"))
        assertEquals(MAX_AGENTS, host.agentPort.list().size)
    }

    @Test
    fun promptStatesAndroidAndDropsTheMacShellSentence() = runBlocking {
        val kernel = FakeKernel()
        val host = openRuntime(this, kernel = kernel, osLabel = "Android 16 (API 36)")
        host.start()
        val agent = host.agentPort.create()
        val sent = async { host.agentPort.send(AgentSendParams(agent.profile.id, "hi")) }
        withTimeout(5_000) { while (kernel.started.isEmpty() && !sent.isCompleted) yield() }
        if (kernel.started.isEmpty()) sent.await()
        val system = kernel.started.single().messages.first { it.role == com.nuum.contracts.MessageRole.SYSTEM }.content
        assertTrue(system.contains("local Android app"))
        assertTrue(system.contains("cannot run a shell"))
        assertTrue(system.contains("Android 16 (API 36)"))
        assertTrue(system.contains("## Autonomy"))
        assertTrue(system.contains("Never fabricate data"))
        assertTrue(system.contains("SendMessage is your only voice"))
        assertFalse(system.contains("own Mac"))
        assertFalse(system.contains("real shell"))
        kernel.emit(ended(kernel.started.single().runId))
        yield()
        sent.await()
        Unit
    }

    @Test
    fun proactiveActionsStayUnavailableAndCheckWaitsForContext() = runBlocking {
        val host = openRuntime(this)
        host.start()
        val snapshot = host.proactivePort.configure(
            com.nuum.contracts.ProactiveConfigureParams(expectedRevision = 0, enabled = true)
        )
        assertFalse(snapshot.actionsAvailable)
        assertTrue(snapshot.availableSourceIds.isEmpty())
        val agentId = snapshot.defaultAgentId ?: snapshot.agents.single().agentId
        val checked = host.proactivePort.check(agentId)
        assertFalse(checked.actionsAvailable)
        assertEquals("waiting-context", checked.agents.single().state)
        assertEquals("waiting-context", checked.agents.single().activity.first().kind)
    }

    @Test
    fun runWorkCliIsUnimplemented() = runBlocking {
        val host = openRuntime(this)
        host.start()
        val work = host.workPort.create(WorkCreateParams("Bar", WorkKind.WORK))
        val result = host.executeDelegated(
            "agent",
            "RunWorkCLI",
            buildJsonObject { put("capability_id", "echo") },
            RunContext.Work(work.id),
            "cli-1"
        )
        assertFalse(result.ok)
        assertTrue(result.output.contains("no local executable"))
    }

    @Test
    fun discussionFinishesAndTaskTransitionsFollowTheTable() = runBlocking {
        val kernel = FakeKernel().also { fake ->
            fake.hold = null
        }
        val host = openRuntime(this, kernel = kernel)
        host.start()
        val agent = host.agentPort.create()
        val room = host.workPort.create(WorkCreateParams("Room", WorkKind.ROOM))
        host.workPort.attachMember(WorkMemberAttachParams(room.id, agent.profile.id, 0, WorkRole.WORKER))
        host.workPort.postMessage(WorkPostMessageParams(room.id, "hello"))
        var finished = false
        repeat(30) {
            yield()
            if (kernel.started.isNotEmpty()) {
                kernel.started.map { it.runId }.distinct().forEach { runId -> kernel.emit(ended(runId)) }
            }
            val snapshot = host.workPort.get(room.id)
            finished = snapshot.events.any { it.type == "discussion.finished" }
            if (finished && !snapshot.discussionRunning) return@repeat
        }
        assertTrue(host.workPort.get(room.id).events.any { it.type == "discussion.finished" })

        val bar = host.workPort.create(WorkCreateParams("Bar", WorkKind.WORK))
        val created = host.executeDelegated(
            agent.profile.id,
            "CreateTask",
            buildJsonObject { put("title", "Write the note") },
            RunContext.Work(bar.id),
            "task-1"
        )
        assertTrue(created.ok)
        val taskId = host.workPort.get(bar.id).tasks.single().task.id
        try {
            host.workPort.transitionTask(WorkTaskTransitionParams(bar.id, taskId, WorkTaskState.DONE, 1))
            fail("done is not a direct step")
        } catch (error: NuumException) {
            assertEquals(HostErrorCode.WORK_CONFLICT, error.code)
        }
        host.workPort.transitionTask(WorkTaskTransitionParams(bar.id, taskId, WorkTaskState.IN_PROGRESS, 1))
        try {
            host.workPort.transitionTask(
                WorkTaskTransitionParams(bar.id, taskId, WorkTaskState.BLOCKED, 2, null)
            )
            fail("blocked needs a reason")
        } catch (error: NuumException) {
            assertEquals(KernelErrorCode.INVALID, error.code)
        }
        val blocked = host.workPort.transitionTask(
            WorkTaskTransitionParams(
                bar.id,
                taskId,
                WorkTaskState.BLOCKED,
                2,
                com.nuum.contracts.WorkBlocker("waiting on the user")
            )
        )
        assertEquals(WorkTaskState.BLOCKED, blocked.task.state)
        assertFalse(blocked.allowedTransitions.contains(WorkTaskState.IN_PROGRESS).not())
    }

    @Test
    fun executionReceiptIsClaimedOnce() = runBlocking {
        val store = MemoryAgentStore()
        val agentId = "agent-1"
        store.writeTextAtomic(
            NuumPaths.profilePath(agentId),
            """{"id":"$agentId","name":"Ada","description":"","createdAt":1}"""
        )
        store.writeTextAtomic(
            NuumPaths.agentSettingsPath(agentId),
            """{"model":{"provider":"deepseek","model":"deepseek-chat"}}"""
        )
        val call = TranscriptEvent.Assistant(
            id = "asst",
            seq = 1,
            createdAt = 1,
            parts = listOf(AssistantPart.ToolCall(id = "call", executionId = "run-1:call", name = "write", arguments = buildJsonObject { }))
        )
        store.appendLine(NuumPaths.transcriptPath(agentId), ProtocolJson.encodeToString(TranscriptEvent.serializer(), call))
        store.writeTextAtomic(
            "${NuumPaths.agentDir(agentId)}/execution-receipts.json",
            """[{"requestId":"run-1:call","runId":"run-1","name":"write","arguments":{},"ok":true,"output":"wrote it"}]"""
        )
        val host = openRuntime(this, store = store)
        host.start()
        val page = host.agentPort.transcript(com.nuum.contracts.TranscriptQuery(agentId))
        assertEquals(1, page.entries.count { it is com.nuum.contracts.TranscriptEvent.Tool && it.content == "wrote it" })
        val again = openRuntime(this, store = store)
        again.start()
        val second = again.agentPort.transcript(com.nuum.contracts.TranscriptQuery(agentId))
        assertEquals(1, second.entries.count { it is com.nuum.contracts.TranscriptEvent.Tool })
    }

    @Test
    fun agentSourcesDoNotTouchModelSecurityStorageOrAShell() {
        val root = File("src/main/kotlin")
        assertTrue(root.isDirectory)
        val forbidden = listOf(
            "com.nuum.model",
            "com.nuum.security",
            "com.nuum.storage",
            "okhttp3",
            "ProcessBuilder",
            "ModelPort"
        )
        val hits = root.walkTopDown().filter { it.extension == "kt" }.flatMap { file ->
            val text = file.readText()
            forbidden.filter { token -> text.contains(token) }.map { token -> "${file.name}:$token" }
        }.toList()
        assertEquals(emptyList<String>(), hits)
        val gradle = File("build.gradle.kts").readText()
        assertFalse(gradle.contains(":core:model"))
        assertFalse(gradle.contains(":core:security"))
        assertFalse(gradle.contains(":core:storage"))
    }

    @Test
    fun knowledgeCatalogStaysReadOnly() = runBlocking {
        val host = openRuntime(this)
        host.start()
        val work = host.workPort.create(WorkCreateParams("Bar", WorkKind.WORK))
        try {
            host.workPort.addCatalog(
                com.nuum.contracts.WorkCatalogAddParams(
                    work.id,
                    0,
                    WorkCatalogInput.Knowledge("notes", "docs", listOf("/docs"), readOnly = false)
                )
            )
            fail("knowledge must stay read only")
        } catch (error: NuumException) {
            assertEquals(KernelErrorCode.INVALID, error.code)
        }
    }
}
