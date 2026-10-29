package com.nuum.model

import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.NormalizedChunk
import com.nuum.contracts.NuumException
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.Headers
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okio.BufferedSource

/** PoC 工程默认。Mac 用平台 fetch，没有更细的超时。 */
internal const val MODEL_CONNECT_TIMEOUT_SECONDS = 20L
internal const val MODEL_READ_TIMEOUT_SECONDS = 60L
internal const val MODEL_WRITE_TIMEOUT_SECONDS = 60L
private const val MAX_ERROR_BODY_CHARS = 4_096

/**
 * 默认不挂日志拦截器，release 保持这样。
 * debug 要看请求时传入 [debugLog]；body 不打印，`Authorization` 和 `x-api-key` 会从日志里拿掉。
 */
fun defaultModelHttpClient(debugLog: ((String) -> Unit)? = null): OkHttpClient {
    val builder = OkHttpClient.Builder()
        .connectTimeout(MODEL_CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(MODEL_READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .writeTimeout(MODEL_WRITE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
    if (debugLog != null) {
        builder.addInterceptor(RedactingLogInterceptor(debugLog))
    }
    return builder.build()
}

internal fun headerIsSensitive(name: String): Boolean {
    return name.equals("Authorization", ignoreCase = true) ||
        name.equals("x-api-key", ignoreCase = true)
}

/** 日志夹具和拦截器共用。敏感头整行丢掉，避免名字或值留下来。 */
internal fun redactLogFixture(raw: String): String {
    return raw.lineSequence()
        .filterNot { line -> headerIsSensitive(line.substringBefore(':').trim()) }
        .joinToString("\n")
}

internal fun scrubSecrets(text: String, secrets: Collection<String>): String {
    var scrubbed = text
    for (secret in secrets) {
        if (secret.isNotEmpty()) scrubbed = scrubbed.replace(secret, "[redacted]")
    }
    return scrubbed
}

private class RedactingLogInterceptor(
    private val log: (String) -> Unit
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        log(formatExchange("--> ${request.method} ${request.url}", request.headers, "--> END ${request.method}"))
        val response = chain.proceed(request)
        log(formatExchange("<-- ${response.code} ${request.url}", response.headers, "<-- END HTTP"))
        return response
    }
}

private fun formatExchange(start: String, headers: Headers, end: String): String {
    val raw = buildString {
        append(start)
        append('\n')
        for (index in 0 until headers.size) {
            append(headers.name(index))
            append(": ")
            append(headers.value(index))
            append('\n')
        }
        append(end)
    }
    return redactLogFixture(raw)
}

internal fun joinUrl(baseUrl: String, path: String): String = baseUrl.trimEnd('/') + path

internal fun sseData(line: String): String? {
    val trimmed = line.trim()
    if (!trimmed.startsWith("data:")) return null
    return trimmed.substring(5).trim()
}

/**
 * 取消绑在收集这个 [Flow] 的协程上，对应 Mac 的 AbortSignal。
 * [awaitClose] 里关 Call，阻塞中的读会立刻断开。
 */
internal fun streamModel(
    client: OkHttpClient,
    apiKey: String,
    providerWire: String,
    label: String,
    request: () -> Request,
    read: suspend (BufferedSource, suspend (NormalizedChunk) -> Unit) -> Unit
): Flow<NormalizedChunk> = callbackFlow {
    if (apiKey.isEmpty()) {
        throw NuumException(KernelErrorCode.INVALID, "API key missing for $providerWire")
    }
    val call = client.newCall(request())
    val producer = this
    launch(Dispatchers.IO) {
        var response: Response? = null
        try {
            response = call.execute()
            if (!response.isSuccessful) {
                val body = scrubSecrets(response.body.string(), listOf(apiKey)).take(MAX_ERROR_BODY_CHARS)
                throw NuumException(KernelErrorCode.MODEL, "$label HTTP ${response.code}: $body")
            }
            read(response.body.source()) { chunk -> producer.send(chunk) }
            if (isActive) producer.close()
        } catch (e: CancellationException) {
            throw e
        } catch (e: NuumException) {
            producer.close(e)
        } catch (_: IOException) {
            if (!call.isCanceled() && isActive) {
                producer.close(NuumException(KernelErrorCode.MODEL, "$label connection failed"))
            }
        } catch (_: Exception) {
            if (!call.isCanceled() && isActive) {
                producer.close(NuumException(KernelErrorCode.MODEL, "$label stream failed"))
            }
        } finally {
            try {
                response?.close()
            } catch (_: IOException) {
                // 取消关流时的 IOException 不是一条新的模型错误。
            }
        }
    }
    awaitClose { call.cancel() }
}
