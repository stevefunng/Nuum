package com.nuum.graph

import com.nuum.contracts.ProviderId
import com.nuum.contracts.SecretStore
import com.nuum.contracts.Secrets
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GraphAdapterTest {
    @Test
    fun secretWriterMergesAndDeletesWithoutEchoingTheKey() = runBlocking {
        val store = MemorySecretStore(
            Secrets(openaiApiKey = "sk-openai-keep", anthropicApiKey = "sk-anthropic-keep")
        )
        val writer = SecretStoreWriter(store)
        writer.write(ProviderId.DEEPSEEK, "sk-deepseek-new")
        assertTrue(store.current.deepseekApiKey == "sk-deepseek-new")
        assertTrue(store.current.openaiApiKey == "sk-openai-keep")
        assertTrue(store.current.anthropicApiKey == "sk-anthropic-keep")

        writer.write(ProviderId.OPENAI, "")
        assertNull(store.current.openaiApiKey)
        assertTrue(store.current.deepseekApiKey == "sk-deepseek-new")
        assertTrue(store.current.anthropicApiKey == "sk-anthropic-keep")

        writer.write(ProviderId.ANTHROPIC, null)
        assertNull(store.current.anthropicApiKey)
        assertTrue(store.current.deepseekApiKey == "sk-deepseek-new")
        assertFalse(writer.toString().contains("sk-"))
        assertFalse(store.toString().contains("sk-"))
    }

    @Test
    fun localOnlyHasNoUserAndNoSyncDoesNothing() = runBlocking {
        assertNull(LocalOnly.userId)
        NoSync.pushAgent("agent")
        NoSync.pullAgent("agent")
        NoSync.pushWork("work")
        NoSync.pullWork("work")
    }

    @Test
    fun supervisorLaunchesWorkAndKeepsGoingAfterAFailure() = runBlocking {
        val job = SupervisorJob()
        val failed = AtomicBoolean(false)
        val scope = CoroutineScope(
            job + Dispatchers.Default + CoroutineExceptionHandler { _, _ -> failed.set(true) }
        )
        val supervisor = InProcessTurnSupervisor(scope)
        try {
            val first = CompletableDeferred<String>()
            val launched = supervisor.launch { first.complete("ran") }
            assertFalse(launched.isCancelled)
            assertTrue(withTimeout(5_000) { first.await() } == "ran")

            supervisor.launch { error("turn failed") }
            val second = CompletableDeferred<Unit>()
            supervisor.launch { second.complete(Unit) }
            withTimeout(5_000) { second.await() }
            withTimeout(5_000) {
                while (!failed.get()) delay(10)
            }
        } finally {
            job.cancel()
        }
    }
}

private class MemorySecretStore(initial: Secrets) : SecretStore {
    var current: Secrets = initial
        private set

    override suspend fun read(): Secrets = current

    override suspend fun write(secrets: Secrets) {
        current = secrets
    }

    override fun toString(): String = "MemorySecretStore"
}
