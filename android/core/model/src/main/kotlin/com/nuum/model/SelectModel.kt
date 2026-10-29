package com.nuum.model

import com.nuum.contracts.KernelErrorCode
import com.nuum.contracts.ModelPort
import com.nuum.contracts.ModelRef
import com.nuum.contracts.NormalizedChatRequest
import com.nuum.contracts.NormalizedChunk
import com.nuum.contracts.NuumException
import com.nuum.contracts.ProviderId
import com.nuum.contracts.Secrets
import kotlinx.coroutines.flow.Flow
import okhttp3.OkHttpClient

data class SelectedModel(val port: ModelPort, val apiKey: String)

fun secretForProvider(secrets: Secrets, provider: ProviderId): String? = when (provider) {
    ProviderId.OPENAI -> secrets.openaiApiKey
    ProviderId.ANTHROPIC -> secrets.anthropicApiKey
    ProviderId.DEEPSEEK -> secrets.deepseekApiKey
}

/**
 * 与 Mac `selectModel` 相同：选定 provider 没有 key 就抛 [KernelErrorCode.INVALID]（1007）。
 * 回退顺序 `deepseek → openai → anthropic` 属于 `resolveAvailableModel`，不在这里。
 */
fun selectModel(
    model: ModelRef,
    secrets: Secrets,
    client: OkHttpClient = defaultModelHttpClient()
): SelectedModel {
    val apiKey = secretForProvider(secrets, model.provider)
    if (apiKey.isNullOrEmpty()) {
        throw NuumException(KernelErrorCode.INVALID, "API key missing for ${model.provider.wire}")
    }
    return SelectedModel(port = providerModel(model.provider, client), apiKey = apiKey)
}

/**
 * 组合根持有的一个 [ModelPort]。按请求里的 provider 分发，Kernel 不必依赖本模块的类。
 * 三个 HTTPS 源写死。测试要换主机时用 [providerModel]，不要从这里收 base URL。
 */
class OkHttpModelPort(
    private val client: OkHttpClient = defaultModelHttpClient()
) : ModelPort {
    override fun streamChat(request: NormalizedChatRequest): Flow<NormalizedChunk> {
        return providerModel(request.model.provider, client).streamChat(request)
    }
}

internal fun providerModel(
    provider: ProviderId,
    client: OkHttpClient,
    openAiBaseUrl: String = OPENAI_BASE_URL,
    deepSeekBaseUrl: String = DEEPSEEK_BASE_URL,
    anthropicBaseUrl: String = ANTHROPIC_BASE_URL
): ModelPort = when (provider) {
    ProviderId.OPENAI -> OpenAIModel(client, openAiBaseUrl, OPENAI_LABEL)
    ProviderId.DEEPSEEK -> OpenAIModel(client, deepSeekBaseUrl, DEEPSEEK_LABEL)
    ProviderId.ANTHROPIC -> AnthropicModel(client, anthropicBaseUrl)
}
