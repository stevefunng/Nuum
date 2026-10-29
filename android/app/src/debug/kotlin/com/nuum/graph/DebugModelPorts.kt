package com.nuum.graph

import android.content.Context
import android.os.Bundle
import com.nuum.contracts.MessageRole
import com.nuum.contracts.ModelPort
import com.nuum.contracts.NormalizedChatRequest
import com.nuum.contracts.NormalizedChunk
import com.nuum.model.OkHttpModelPort
import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Debug-only model switch. Off unless instrumentation passes
 * `nuum.fakeModel=router`. There is no settings UI for it, and this file is
 * not in the release variant.
 *
 * The router keys off the tool list and the user text so one process can run
 * every acceptance scenario:
 * - tools include `CreateTask` → one CreateTask named "Lane card"
 * - user text contains `acceptance-secrets` → `write` of `noBackupFilesDir/secrets.bin`
 * - user text contains `acceptance-write` → `write` of `filesDir/nuum/outside-scratch.txt`
 * - otherwise a scratchpad text chunk plus one `SendMessage`
 *
 * A tool result is answered with `SendMessage`, and the following round is empty
 * so the turn ends. `SendMessage` arguments are `{type:text, content}` so both
 * the direct parser and the work parser accept them.
 */
internal object DebugModelPorts {
    const val ARGUMENT = "nuum.fakeModel"
    const val ROUTER = "router"
    const val VISIBLE_REPLY = "Visible from SendMessage"
    const val SCRATCHPAD = "scratchpad-not-the-body"
    const val LANE_CARD = "Lane card"
    const val NOTE_TEXT = "accepted-note"

    fun select(context: Context): ModelPort {
        val mode = instrumentationArgument(ARGUMENT)
        if (mode.isNullOrBlank()) return OkHttpModelPort()
        if (mode == ROUTER) return AcceptanceRouterModel(context.applicationContext)
        error("Unknown $ARGUMENT value")
    }

    private fun instrumentationArgument(name: String): String? = runCatching {
        val registry = Class.forName("androidx.test.platform.app.InstrumentationRegistry")
        val bundle = registry.getMethod("getArguments").invoke(null) as Bundle
        bundle.getString(name)
    }.getOrNull()
}

internal class AcceptanceRouterModel(context: Context) : ModelPort {
    private val note = File(context.filesDir, "nuum/outside-scratch.txt").absolutePath
    private val secrets = File(context.noBackupFilesDir, "secrets.bin").absolutePath
    private val ids = AtomicInteger()

    override fun streamChat(request: NormalizedChatRequest): Flow<NormalizedChunk> = flow {
        val names = request.tools.map { it.name }.toSet()
        val last = request.messages.lastOrNull()
        if (names.isEmpty()) {
            emit(NormalizedChunk.Text("summary"))
            return@flow
        }
        if (last?.role == MessageRole.TOOL) {
            if (last.name == "SendMessage" || last.name == "CreateTask") return@flow
            emit(send("model saw: ${last.content.take(180)}"))
            return@flow
        }
        val user = request.messages.filter { it.role == MessageRole.USER }.joinToString("\n") { it.content }
        when {
            "CreateTask" in names -> emit(
                tool(
                    "CreateTask",
                    mapOf(
                        "title" to DebugModelPorts.LANE_CARD,
                        "description" to "Created by the acceptance router"
                    )
                )
            )
            "acceptance-secrets" in user -> emit(
                tool("write", mapOf("path" to secrets, "content" to DebugModelPorts.NOTE_TEXT))
            )
            "acceptance-write" in user && "write" in names -> emit(
                tool("write", mapOf("path" to note, "content" to DebugModelPorts.NOTE_TEXT))
            )
            else -> {
                emit(NormalizedChunk.Text(DebugModelPorts.SCRATCHPAD))
                emit(send(DebugModelPorts.VISIBLE_REPLY))
            }
        }
    }

    private fun send(content: String): NormalizedChunk = tool(
        "SendMessage",
        mapOf("type" to "text", "content" to content)
    )

    private fun tool(name: String, arguments: Map<String, Any?>): NormalizedChunk.ToolCallChunk =
        NormalizedChunk.ToolCallChunk("call-${ids.incrementAndGet()}", name, arguments)
}
