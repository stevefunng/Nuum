import Foundation
import NuumContracts

/// Copy from `packages/ui/src/i18n/messages.ts`. The map key is the messages.ts key.
/// English and zh-CN are that entry's `en` and `zh-CN`, which are not always the key.
enum SettingsCopy {
    private struct Row {
        var en: String
        var zhCN: String
    }

    private static let table: [String: Row] = [
        "Settings sections": Row(en: "Settings sections", zhCN: "设置分类"),
        "General": Row(en: "General", zhCN: "通用"),
        "Models": Row(en: "Models", zhCN: "模型"),
        "Close": Row(en: "Close", zhCN: "关闭"),
        "Back": Row(en: "Back", zhCN: "返回"),
        "Appearance": Row(en: "Appearance", zhCN: "外观"),
        "Language": Row(en: "Language", zhCN: "界面语言"),
        "Choose the language used throughout Nuum.": Row(
            en: "Choose the language used throughout Nuum.",
            zhCN: "选择 Nuum 界面使用的语言。"
        ),
        "Could not change language. Please try again.": Row(
            en: "Could not change language. Please try again.",
            zhCN: "语言设置保存失败，请重试。"
        ),
        "Theme": Row(en: "Theme", zhCN: "主题"),
        "Keep the current dark shell, or switch to the light palette.": Row(
            en: "Keep the current dark shell, or switch to the light palette.",
            zhCN: "在深色与浅色界面之间切换。"
        ),
        "Follow system": Row(en: "Follow system", zhCN: "跟随系统"),
        "Light": Row(en: "Light", zhCN: "浅色"),
        "Dark": Row(en: "Dark", zhCN: "深色"),
        "Proactive mode": Row(en: "Proactive mode", zhCN: "Proactive mode"),
        "Manage your proactive companion from the menu bar.": Row(
            en: "Manage your proactive companion from the menu bar.",
            zhCN: "在菜单栏管理主动陪伴你的 Nunu。"
        ),
        "Open menu bar panel": Row(en: "Open menu bar panel", zhCN: "打开菜单栏面板"),
        "Model preferences": Row(en: "Model preferences", zhCN: "模型偏好"),
        "Default provider": Row(en: "Default provider", zhCN: "默认模型服务商"),
        "Used for new chats until you change the session model.": Row(
            en: "Used by new Nunu until their model is changed.",
            zhCN: "新建 Nunu 默认使用此服务商。"
        ),
        "DeepSeek model": Row(en: "DeepSeek model", zhCN: "DeepSeek 模型"),
        "deepseek-chat for everyday use. deepseek-reasoner for longer reasoning.": Row(
            en: "deepseek-chat for everyday use. deepseek-reasoner for longer reasoning.",
            zhCN: "日常使用 deepseek-chat，较复杂的推理使用 deepseek-reasoner。"
        ),
        "API keys": Row(en: "API keys", zhCN: "API 密钥"),
        "DeepSeek API key": Row(en: "DeepSeek API key", zhCN: "DeepSeek API 密钥"),
        "Stored in the OS keychain and injected into Host memory only.": Row(
            en: "Encrypted on this device using OS protection and provided to the service at runtime.",
            zhCN: "使用系统加密能力保存在本机，仅在运行时提供给服务。"
        ),
        "OpenAI API key": Row(en: "OpenAI API key", zhCN: "OpenAI API 密钥"),
        "Optional. Used when the default provider is OpenAI.": Row(
            en: "Optional. Used when the default provider is OpenAI.",
            zhCN: "可选。使用 OpenAI 作为服务商时需要。"
        ),
        "Anthropic API key": Row(en: "Anthropic API key", zhCN: "Anthropic API 密钥"),
        "Optional. Used when the default provider is Anthropic.": Row(
            en: "Optional. Used when the default provider is Anthropic.",
            zhCN: "可选。使用 Anthropic 作为服务商时需要。"
        ),
        "Proactive is off": Row(en: "Proactive is off", zhCN: "尚未开启"),
        "Taking a pause": Row(en: "Taking a pause", zhCN: "暂停中"),
        "Waiting for context": Row(en: "Waiting for context", zhCN: "等待接入上下文"),
        "Ready to check": Row(en: "Ready to check", zhCN: "已就绪"),
        "Checking context": Row(en: "Checking context", zhCN: "正在检查上下文"),
        "Check needs attention": Row(en: "Check needs attention", zhCN: "检查遇到问题"),
        "Proactive enabled": Row(en: "Proactive enabled", zhCN: "已开启 proactive mode"),
        "Proactive disabled": Row(en: "Proactive disabled", zhCN: "已关闭 proactive mode"),
        "Paused": Row(en: "Paused", zhCN: "已暂停"),
        "Resumed": Row(en: "Resumed", zhCN: "已恢复"),
        "Configuration updated": Row(en: "Configuration updated", zhCN: "已更新配置"),
        "No context sources connected": Row(en: "No context sources connected", zhCN: "尚未接入上下文来源"),
        "Context ready; actions not connected": Row(
            en: "Context ready; actions not connected",
            zhCN: "上下文已就绪，行动能力尚未接入"
        ),
        "No new context": Row(en: "No new context", zhCN: "暂无新的上下文"),
        "Context check failed": Row(en: "Context check failed", zhCN: "上下文检查失败"),
        "Connecting to Nuum…": Row(en: "Connecting to Nuum…", zhCN: "正在连接 Nuum…"),
        "Your companion will resume after this break.": Row(
            en: "Your companion will resume after this break.",
            zhCN: "休息一下，到时会自动恢复。"
        ),
        "A quieter kind of help, at the right moment.": Row(
            en: "A quieter kind of help, at the right moment.",
            zhCN: "在合适的时候，主动帮上一点忙。"
        ),
        "Enable proactive mode": Row(en: "Enable proactive mode", zhCN: "开启 proactive mode"),
        "Resume now": Row(en: "Resume now", zhCN: "立即恢复"),
        "Pause proactive mode": Row(en: "Pause proactive mode", zhCN: "暂停 proactive mode"),
        "Pause…": Row(en: "Pause…", zhCN: "暂停…"),
        "For 30 minutes": Row(en: "For 30 minutes", zhCN: "暂停 30 分钟"),
        "For 1 hour": Row(en: "For 1 hour", zhCN: "暂停 1 小时"),
        "Check setup": Row(en: "Check setup", zhCN: "检查基座"),
        "Resumes at {time}": Row(en: "Resumes at {time}", zhCN: "将在 {time} 恢复"),
        "Connections": Row(en: "Connections", zhCN: "连接状态"),
        "Context sources": Row(en: "Context sources", zhCN: "上下文来源"),
        "Available": Row(en: "Available", zhCN: "可用"),
        "Not connected": Row(en: "Not connected", zhCN: "尚未接入"),
        "Agent actions": Row(en: "Nunu actions", zhCN: "Nunu 行动"),
        "Setup is ready. Context collection and autonomous actions are not enabled in this version.": Row(
            en: "Setup is ready. Context collection and autonomous actions are not enabled in this version.",
            zhCN: "基座已就绪。本版暂不采集上下文，也不自动执行行动。"
        ),
        "Recent activity": Row(en: "Recent activity", zhCN: "最近活动"),
        "Activity will appear here when you turn it on.": Row(
            en: "Activity will appear here when you turn it on.",
            zhCN: "开启后，活动记录会显示在这里。"
        ),
        "Could not update proactive mode.": Row(
            en: "Could not update proactive mode.",
            zhCN: "暂时无法更新 proactive mode。"
        ),
        "Open Nunu": Row(en: "Open Nunu", zhCN: "打开 Nunu"),
        "Open Nuum": Row(en: "Open Nuum", zhCN: "打开 Nuum"),
        "Retry": Row(en: "Retry", zhCN: "重试"),
    ]

    static func contains(_ key: String) -> Bool {
        table[key] != nil
    }

    static func text(_ language: Language, _ key: String) -> String {
        guard let row = table[key] else { return key }
        switch language {
        case .zhCN:
            return row.zhCN
        case .en:
            return row.en
        }
    }

    static func format(_ language: Language, _ key: String, _ vars: [String: String]) -> String {
        var value = text(language, key)
        for (name, replacement) in vars {
            value = value.replacingOccurrences(of: "{\(name)}", with: replacement)
        }
        return value
    }
}

/// A nil language follows the system locale until settings load.
func displayLanguage(_ language: Language?, localeIdentifier: String = Locale.current.identifier) -> Language {
    if let language { return language }
    return localeIdentifier.lowercased().hasPrefix("zh") ? .zhCN : .en
}

/// Drop key characters if a storage error echoes the value the user just typed.
func redactSecret(_ message: String, secret: String) -> String {
    guard !secret.isEmpty, !message.isEmpty, message.contains(secret) else { return message }
    return message.replacingOccurrences(of: secret, with: "…")
}

func userFacingMessage(_ error: Error, redacting secret: String = "") -> String {
    let raw: String
    if let nuum = error as? NuumError {
        raw = nuum.message
    } else {
        raw = error.localizedDescription
    }
    return redactSecret(raw, secret: secret)
}
