package com.nuum.feature.settings

import com.nuum.contracts.Language
import java.util.Locale

/**
 * Copy from `packages/ui/src/i18n/messages.ts`. The map key is the messages.ts
 * key. English and zh-CN are that entry's `en` and `zh-CN`, which are not
 * always identical to the key.
 */
internal object SettingsCopy {
    private data class Row(val en: String, val zh: String)

    private fun same(key: String, zh: String) = key to Row(key, zh)

    private val table: Map<String, Row> = mapOf(
        same("Settings sections", "设置分类"),
        same("General", "通用"),
        same("Models", "模型"),
        same("Close", "关闭"),
        same("Appearance", "外观"),
        same("Language", "界面语言"),
        same("Choose the language used throughout Nuum.", "选择 Nuum 界面使用的语言。"),
        same("Could not change language. Please try again.", "语言设置保存失败，请重试。"),
        same("Theme", "主题"),
        same("Keep the current dark shell, or switch to the light palette.", "在深色与浅色界面之间切换。"),
        same("Follow system", "跟随系统"),
        same("Light", "浅色"),
        same("Dark", "深色"),
        same("Proactive mode", "Proactive mode"),
        same("Manage your proactive companion from the menu bar.", "在菜单栏管理主动陪伴你的 Nunu。"),
        same("Open menu bar panel", "打开菜单栏面板"),
        same("Model preferences", "模型偏好"),
        same("Default provider", "默认模型服务商"),
        "Used for new chats until you change the session model." to Row(
            "Used by new Nunu until their model is changed.",
            "新建 Nunu 默认使用此服务商。"
        ),
        same("DeepSeek model", "DeepSeek 模型"),
        same(
            "deepseek-chat for everyday use. deepseek-reasoner for longer reasoning.",
            "日常使用 deepseek-chat，较复杂的推理使用 deepseek-reasoner。"
        ),
        same("API keys", "API 密钥"),
        same("DeepSeek API key", "DeepSeek API 密钥"),
        "Stored in the OS keychain and injected into Host memory only." to Row(
            "Encrypted on this device using OS protection and provided to the service at runtime.",
            "使用系统加密能力保存在本机，仅在运行时提供给服务。"
        ),
        same("OpenAI API key", "OpenAI API 密钥"),
        same("Optional. Used when the default provider is OpenAI.", "可选。使用 OpenAI 作为服务商时需要。"),
        same("Anthropic API key", "Anthropic API 密钥"),
        same(
            "Optional. Used when the default provider is Anthropic.",
            "可选。使用 Anthropic 作为服务商时需要。"
        ),
        same("Proactive is off", "尚未开启"),
        same("Taking a pause", "暂停中"),
        same("Waiting for context", "等待接入上下文"),
        same("Ready to check", "已就绪"),
        same("Checking context", "正在检查上下文"),
        same("Check needs attention", "检查遇到问题"),
        same("Proactive enabled", "已开启 proactive mode"),
        same("Proactive disabled", "已关闭 proactive mode"),
        same("Paused", "已暂停"),
        same("Resumed", "已恢复"),
        same("Configuration updated", "已更新配置"),
        same("No context sources connected", "尚未接入上下文来源"),
        same("Context ready; actions not connected", "上下文已就绪，行动能力尚未接入"),
        same("No new context", "暂无新的上下文"),
        same("Context check failed", "上下文检查失败"),
        same("Connecting to Nuum…", "正在连接 Nuum…"),
        same("Your companion will resume after this break.", "休息一下，到时会自动恢复。"),
        same("A quieter kind of help, at the right moment.", "在合适的时候，主动帮上一点忙。"),
        same("Enable proactive mode", "开启 proactive mode"),
        same("Resume now", "立即恢复"),
        same("Pause proactive mode", "暂停 proactive mode"),
        same("Pause…", "暂停…"),
        same("For 30 minutes", "暂停 30 分钟"),
        same("For 1 hour", "暂停 1 小时"),
        same("Check setup", "检查基座"),
        same("Resumes at {time}", "将在 {time} 恢复"),
        same("Connections", "连接状态"),
        same("Context sources", "上下文来源"),
        same("Available", "可用"),
        same("Not connected", "尚未接入"),
        "Agent actions" to Row("Nunu actions", "Nunu 行动"),
        same(
            "Setup is ready. Context collection and autonomous actions are not enabled in this version.",
            "基座已就绪。本版暂不采集上下文，也不自动执行行动。"
        ),
        same("Recent activity", "最近活动"),
        same("Activity will appear here when you turn it on.", "开启后，活动记录会显示在这里。"),
        same("Could not update proactive mode.", "暂时无法更新 proactive mode。"),
        same("Open Nunu", "打开 Nunu"),
        same("Open Nuum", "打开 Nuum"),
        same("Retry", "重试")
    )

    /** Resource ids mirror [table] for `values/strings.xml`. */
    val resourceIds: Map<String, Int> = mapOf(
        "Settings sections" to R.string.settings_sections,
        "General" to R.string.general,
        "Models" to R.string.models,
        "Close" to R.string.close,
        "Appearance" to R.string.appearance,
        "Language" to R.string.language,
        "Choose the language used throughout Nuum." to R.string.language_description,
        "Could not change language. Please try again." to R.string.language_error,
        "Theme" to R.string.theme,
        "Keep the current dark shell, or switch to the light palette." to R.string.theme_description,
        "Follow system" to R.string.follow_system,
        "Light" to R.string.light,
        "Dark" to R.string.dark,
        "Proactive mode" to R.string.proactive_mode,
        "Manage your proactive companion from the menu bar." to R.string.proactive_description,
        "Open menu bar panel" to R.string.open_menu_bar_panel,
        "Model preferences" to R.string.model_preferences,
        "Default provider" to R.string.default_provider,
        "Used for new chats until you change the session model." to R.string.default_provider_description,
        "DeepSeek model" to R.string.deepseek_model,
        "deepseek-chat for everyday use. deepseek-reasoner for longer reasoning." to R.string.deepseek_model_description,
        "API keys" to R.string.api_keys,
        "DeepSeek API key" to R.string.deepseek_api_key,
        "Stored in the OS keychain and injected into Host memory only." to R.string.deepseek_api_key_description,
        "OpenAI API key" to R.string.openai_api_key,
        "Optional. Used when the default provider is OpenAI." to R.string.openai_api_key_description,
        "Anthropic API key" to R.string.anthropic_api_key,
        "Optional. Used when the default provider is Anthropic." to R.string.anthropic_api_key_description,
        "Proactive is off" to R.string.proactive_off,
        "Taking a pause" to R.string.taking_a_pause,
        "Waiting for context" to R.string.waiting_for_context,
        "Ready to check" to R.string.ready_to_check,
        "Checking context" to R.string.checking_context,
        "Check needs attention" to R.string.check_needs_attention,
        "Proactive enabled" to R.string.activity_enabled,
        "Proactive disabled" to R.string.activity_disabled,
        "Paused" to R.string.activity_paused,
        "Resumed" to R.string.activity_resumed,
        "Configuration updated" to R.string.activity_configured,
        "No context sources connected" to R.string.activity_waiting_context,
        "Context ready; actions not connected" to R.string.activity_context_ready,
        "No new context" to R.string.activity_no_change,
        "Context check failed" to R.string.activity_error,
        "Connecting to Nuum…" to R.string.connecting,
        "Your companion will resume after this break." to R.string.resume_after_break,
        "A quieter kind of help, at the right moment." to R.string.quieter_help,
        "Enable proactive mode" to R.string.enable_proactive,
        "Resume now" to R.string.resume_now,
        "Pause proactive mode" to R.string.pause_proactive,
        "Pause…" to R.string.pause_ellipsis,
        "For 30 minutes" to R.string.pause_30_minutes,
        "For 1 hour" to R.string.pause_1_hour,
        "Check setup" to R.string.check_setup,
        "Resumes at {time}" to R.string.resumes_at,
        "Connections" to R.string.connections,
        "Context sources" to R.string.context_sources,
        "Available" to R.string.available,
        "Not connected" to R.string.not_connected,
        "Agent actions" to R.string.agent_actions,
        "Setup is ready. Context collection and autonomous actions are not enabled in this version." to R.string.setup_ready,
        "Recent activity" to R.string.recent_activity,
        "Activity will appear here when you turn it on." to R.string.activity_empty,
        "Could not update proactive mode." to R.string.proactive_update_error,
        "Open Nunu" to R.string.open_nunu,
        "Open Nuum" to R.string.open_nuum,
        "Retry" to R.string.retry
    )

    init {
        val missing = table.keys - resourceIds.keys
        val extra = resourceIds.keys - table.keys
        check(missing.isEmpty() && extra.isEmpty()) {
            "String resources and copy table diverged. missing=$missing extra=$extra"
        }
    }

    fun text(language: Language, key: String): String {
        val row = table.getValue(key)
        return when (language) {
            Language.ZH_CN -> row.zh
            Language.EN -> row.en
        }
    }

    fun format(language: Language, key: String, vars: Map<String, String>): String {
        var value = text(language, key)
        vars.forEach { (name, replacement) ->
            value = value.replace("{$name}", replacement)
        }
        return value
    }
}

internal fun displayLanguage(language: Language?): Language {
    if (language != null) return language
    val tag = Locale.getDefault().toLanguageTag()
    return if (tag.startsWith("zh", ignoreCase = true)) Language.ZH_CN else Language.EN
}

internal fun redactSecret(message: String, secret: String): String {
    if (secret.isEmpty() || message.isEmpty() || !message.contains(secret)) return message
    return message.replace(secret, "…")
}
