package com.nuum.graph

import android.content.Context
import android.util.Log
import com.nuum.agent.HostRuntime
import com.nuum.agent.androidOsLabel
import com.nuum.contracts.AgentPort
import com.nuum.contracts.Clock
import com.nuum.contracts.IdentityContext
import com.nuum.contracts.ModelPort
import com.nuum.contracts.NuumPaths
import com.nuum.contracts.ProactivePort
import com.nuum.contracts.SecretStore
import com.nuum.contracts.SecretWriter
import com.nuum.contracts.SettingsPort
import com.nuum.contracts.SyncPort
import com.nuum.contracts.WorkPort
import com.nuum.feature.conversation.ConversationPorts
import com.nuum.feature.settings.SettingsDependencies
import com.nuum.feature.shell.ShellPorts
import com.nuum.feature.work.WorkPorts
import com.nuum.kernel.Kernel
import com.nuum.security.KeystoreSecretStore
import com.nuum.storage.FileAgentStore
import com.nuum.tools.LocalToolBackend
import java.io.File
import java.time.ZoneId
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Hand-built composition root. The four host facades stay separate because
 * `get` and `list` collide. [identity] and [sync] are the seams from
 * architecture §14; the PoC UI does not call them.
 *
 * [modelOverride] and [secretStoreOverride] are test seams. Production calls
 * [AppGraph] with neither: the model is `OkHttpModelPort` unless a debug
 * instrumentation argument selects the acceptance router, and secrets stay in
 * the keystore. The router class is compiled only into the debug variant.
 */
class AppGraph(
    context: Context,
    modelOverride: ModelPort? = null,
    secretStoreOverride: SecretStore? = null
) {
    private val appContext = context.applicationContext
    private val nuumRootFile = File(appContext.filesDir, "nuum")
    private val noBackupDir = appContext.noBackupFilesDir
    private val ready = CompletableDeferred<Unit>()

    val clock: Clock = Clock { System.currentTimeMillis() }
    val secretStore: SecretStore = secretStoreOverride ?: KeystoreSecretStore(appContext)
    val secretWriter: SecretWriter = SecretStoreWriter(secretStore)
    val store: FileAgentStore = FileAgentStore.create(appContext, nuumRootFile)
    val model: ModelPort = modelOverride ?: DebugModelPorts.select(appContext)
    val supervisor: InProcessTurnSupervisor = InProcessTurnSupervisor()
    val identity: IdentityContext = LocalOnly
    val sync: SyncPort = NoSync
    val desktop: AndroidDesktopPort = AndroidDesktopPort(appContext)

    internal val deniedRoots: List<String> = hostDeniedRoots(noBackupDir, nuumRootFile)
    private val sealedRoots: List<String> = listOf(
        noBackupDir.absolutePath,
        File(noBackupDir, NuumPaths.secretsFileName()).absolutePath
    )
    private val tools = CarvingToolBackend(LocalToolBackend.create(appContext), sealedRoots)
    private val kernel = Kernel(
        model = model,
        tools = tools,
        scope = supervisor.scope,
        clock = clock
    )
    private val host = HostRuntime(
        store = store,
        kernel = kernel,
        secretStore = secretStore,
        tools = tools,
        clock = clock,
        supervisor = supervisor,
        nuumRoot = nuumRootFile.absolutePath,
        osLabel = androidOsLabel(),
        timeZone = ZoneId.systemDefault().id,
        deniedRoots = deniedRoots
    )

    val settingsPort: SettingsPort = host.settingsPort
    val agentPort: AgentPort = host.agentPort
    val workPort: WorkPort = host.workPort
    val proactivePort: ProactivePort = host.proactivePort

    val shellPorts: ShellPorts = ShellPorts(
        agents = agentPort,
        settings = settingsPort,
        desktop = desktop,
        work = workPort
    )
    val workPorts: WorkPorts = WorkPorts(
        work = workPort,
        agent = agentPort,
        desktop = desktop
    )
    val conversationPorts: ConversationPorts = ConversationPorts(
        agent = agentPort,
        desktop = desktop
    )
    val settingsDependencies: SettingsDependencies = SettingsDependencies(
        settings = settingsPort,
        secrets = secretWriter,
        proactive = proactivePort,
        clock = clock
    )

    init {
        supervisor.scope.launch { openAndStart() }
    }

    /** Completes after the store open and host start have been attempted. */
    suspend fun awaitReady() {
        ready.await()
    }

    /** Stops turns and closes the local database. A new graph can reopen the same files. */
    fun close() {
        supervisor.scope.coroutineContext[Job]?.cancel()
        store.close()
        if (!ready.isCompleted) ready.complete(Unit)
    }

    private suspend fun openAndStart() {
        try {
            try {
                store.open()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                Log.e(TAG, "Couldn't open the local store (${error.javaClass.simpleName})")
            }
            try {
                host.start()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                Log.e(TAG, "Couldn't start the host (${error.javaClass.simpleName})")
            }
        } finally {
            if (!ready.isCompleted) ready.complete(Unit)
        }
    }

    private companion object {
        const val TAG = "Nuum"
    }
}
