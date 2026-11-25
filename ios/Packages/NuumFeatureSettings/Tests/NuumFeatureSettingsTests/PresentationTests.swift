import Foundation
import NuumContracts
import Testing
@testable import NuumFeatureSettings

@Test func copyMatchesMessagesWhereEnglishIsNotTheKey() {
    #expect(SettingsCopy.text(.en, "Used for new chats until you change the session model.") == "Used by new Nunu until their model is changed.")
    #expect(SettingsCopy.text(.zhCN, "Used for new chats until you change the session model.") == "新建 Nunu 默认使用此服务商。")
    #expect(SettingsCopy.text(.en, "Stored in the OS keychain and injected into Host memory only.") == "Encrypted on this device using OS protection and provided to the service at runtime.")
    #expect(SettingsCopy.text(.en, "Agent actions") == "Nunu actions")
    #expect(SettingsCopy.text(.zhCN, "Agent actions") == "Nunu 行动")
    #expect(SettingsCopy.text(.zhCN, "Proactive mode") == "Proactive mode")
    #expect(SettingsCopy.text(.zhCN, "General") == "通用")
    #expect(SettingsCopy.text(.en, "Could not change language. Please try again.") == "Could not change language. Please try again.")
    #expect(SettingsCopy.format(.zhCN, "Resumes at {time}", ["time": "08:30"]) == "将在 08:30 恢复")
    #expect(displayLanguage(nil, localeIdentifier: "zh-Hans-CN") == .zhCN)
    #expect(displayLanguage(nil, localeIdentifier: "en-US") == .en)
    #expect(displayLanguage(.en, localeIdentifier: "zh-CN") == .en)
}

@Test func paletteFollowsSystemOnlyWhileThePreferenceSaysSo() {
    #expect(settingsPalette(preference: nil, systemIsDark: false).modeName == "nuum-dark")
    #expect(settingsPalette(preference: .dark, systemIsDark: false).modeName == "nuum-dark")
    #expect(settingsPalette(preference: .light, systemIsDark: true).modeName == "nuum-light")
    #expect(settingsPalette(preference: .system, systemIsDark: true).isDark)
    #expect(!settingsPalette(preference: .system, systemIsDark: false).isDark)
    #expect(SettingsPalette.light.textPrimary.css == "#141414")
    #expect(SettingsPalette.light.textSecondary.css == "#14141499")
    #expect(SettingsPalette.dark.bgEditor.css == "#070707")
    #expect(SettingsPalette.dark.scrim.css == "#141414b2")
    #expect(SettingsPalette.light.bgInput.css == "#fcfcfc")
    #expect(SandRGBA(css: "#14141499").alpha == Double(0x99) / 255)
}

@Test func settingsFrameFollowsCompactAndThe900PointDialog() {
    let phone = settingsFrame(widthClass: .compact, windowWidth: 390, windowHeight: 844)
    #expect(phone.kind == .page)
    #expect(!phone.showsScrim)
    #expect(!phone.sideNavigation)
    #expect(phone.backgroundToken == "--nuum-bg-editor")

    let narrow = settingsFrame(widthClass: .regular, windowWidth: 800, windowHeight: 700)
    #expect(narrow.kind == .dialog(width: 768, height: 668, maxHeight: 668))
    #expect(narrow.showsScrim)
    #expect(!narrow.sideNavigation)

    let boundary = settingsFrame(widthClass: .regular, windowWidth: 899, windowHeight: 800)
    #expect(!boundary.sideNavigation)

    let wide = settingsFrame(widthClass: .regular, windowWidth: 1000, windowHeight: 800)
    #expect(wide.kind == .dialog(width: 860, height: nil, maxHeight: 720))
    #expect(wide.sideNavigation)
    #expect(wide.backgroundToken == "--nuum-bg-elevated")
    #expect(apiKeyFieldMetrics(compact: true) == APIKeyFieldMetrics(fixedWidth: nil, minWidth: 160))
    #expect(apiKeyFieldMetrics(compact: false).fixedWidth == 175)
}

@Test func reducedMotionSkipsTheDialogTransition() {
    #expect(settingsMotion(reduceMotion: true) == .instant)
    #expect(settingsMotion(reduceMotion: false) == .slowerOutStrong)
}

@Test func hourMinuteUsesTheAppLanguageClock() {
    let utc = TimeZone(secondsFromGMT: 0)!
    #expect(formatHourMinute(1_700_000_000_000, language: .en, timeZone: utc) == "22:13")
    #expect(formatHourMinute(1_700_000_000_000, language: .zhCN, timeZone: utc) == "22:13")
}

@Test func proactivePresentationCoversTheDesignStates() {
    let loading = presentProactive(ProactiveUiState(), language: .en)
    #expect(loading.phase == .loading)
    #expect(loading.statusKey == "Connecting to Nuum…")
    #expect(loading.dot == .tertiary)
    #expect(!loading.switchEnabled)
    #expect(!loading.pauseEnabled)
    #expect(!loading.checkEnabled)
    #expect(loading.title == "Nunu")
    #expect(loading.activityEmptyKey == "Activity will appear here when you turn it on.")
    #expect(!loading.actionsFollowSnapshot)
    #expect(loading.actions == .notConnected)
    #expect(!loading.showsQuit)
    #expect(!loading.showsNoAPIKeyBanner)
    #expect(!loading.showsPermissionDenied)
    #expect(!loading.showsDiscussionInterrupt)

    let off = presentProactive(
        ProactiveUiState(snapshot: proactiveSnapshot(agent: proactiveAgent(enabled: false, state: "disabled")), loading: false),
        language: .en
    )
    #expect(off.phase == .disabled)
    #expect(off.statusKey == "Proactive is off")
    #expect(!off.switchOn)
    #expect(!off.checkEnabled)
    #expect(off.actionsFollowSnapshot)
    #expect(off.actions == .notConnected)

    let ready = presentProactive(
        ProactiveUiState(
            snapshot: proactiveSnapshot(
                agent: proactiveAgent(enabled: true, state: "ready", name: "Mika"),
                actionsAvailable: true,
                sources: ["notes"]
            ),
            loading: false
        ),
        language: .en
    )
    #expect(ready.phase == .ready)
    #expect(ready.statusKey == "Ready to check")
    #expect(ready.dot == .ready)
    #expect(ready.dot.fixedCSS == "#80856b")
    #expect(ready.title == "Mika")
    #expect(ready.switchOn)
    #expect(ready.checkEnabled)
    #expect(ready.actions == .available)
    #expect(ready.sources == .available)
    #expect(ready.footerKey == "Open Nunu")
    #expect(ready.footerAgentId == "agent-1")
    #expect(!ready.showsQuit)

    let paused = presentProactive(
        ProactiveUiState(
            snapshot: proactiveSnapshot(
                agent: proactiveAgent(enabled: true, state: "paused", pausedUntil: 1_700_000_000_000)
            ),
            loading: false
        ),
        language: .en,
        timeZone: TimeZone(secondsFromGMT: 0)!
    )
    #expect(paused.phase == .paused)
    #expect(paused.statusKey == "Taking a pause")
    #expect(paused.subtitleKey == "Your companion will resume after this break.")
    #expect(paused.dot.fixedCSS == "#aa8a52")
    #expect(paused.showsResume)
    #expect(!paused.checkEnabled)
    #expect(paused.resumesAt == "Resumes at 22:13")

    let checking = presentProactive(
        ProactiveUiState(snapshot: proactiveSnapshot(agent: proactiveAgent(enabled: true, state: "checking")), loading: false),
        language: .en
    )
    #expect(checking.phase == .checking)
    #expect(checking.statusKey == "Checking context")
    #expect(!checking.checkEnabled)

    let attention = presentProactive(
        ProactiveUiState(snapshot: proactiveSnapshot(agent: proactiveAgent(enabled: true, state: "error")), loading: false),
        language: .en
    )
    #expect(attention.phase == .error)
    #expect(attention.statusKey == "Check needs attention")
    #expect(attention.dot.fixedCSS == "#bd615a")

    let waiting = presentProactive(
        ProactiveUiState(snapshot: proactiveSnapshot(agent: proactiveAgent(enabled: true, state: "waiting-context")), loading: false),
        language: .en
    )
    #expect(waiting.phase == .waitingContext)
    #expect(waiting.statusKey == "Waiting for context")
    #expect(waiting.checkEnabled)

    let lines = [
        ProactiveActivity(id: "a", at: 1_700_000_000_000, kind: "enabled"),
        ProactiveActivity(id: "b", at: 1_700_000_060_000, kind: "no-change"),
        ProactiveActivity(id: "c", at: 1_700_000_120_000, kind: "error"),
        ProactiveActivity(id: "d", at: 1_700_000_180_000, kind: "paused"),
    ]
    let activity = presentProactive(
        ProactiveUiState(
            snapshot: proactiveSnapshot(agent: proactiveAgent(enabled: true, state: "ready", activity: lines)),
            loading: false
        ),
        language: .en,
        timeZone: TimeZone(secondsFromGMT: 0)!
    )
    #expect(activity.activity.map(\.textKey) == ["Proactive enabled", "No new context", "Context check failed"])
    #expect(activity.activityEmptyKey == nil)
    #expect(!activity.activity.contains(where: { $0.textKey == "Paused" }))

    let failed = presentProactive(ProactiveUiState(snapshot: ready.phase == .ready ? proactiveSnapshot(agent: proactiveAgent(enabled: true, state: "ready")) : nil, loading: false, failed: true), language: .en)
    #expect(failed.failureKey == "Could not update proactive mode.")
    #expect(failed.showsNoAPIKeyBanner == false)
    #expect(!containedStrings(failed).joined().contains("2004"))
}

@Test func everyRenderedCopyKeyExists() {
    let keys = [
        "Settings sections", "General", "Models", "Close", "Back", "Appearance", "Language",
        "Choose the language used throughout Nuum.", "Could not change language. Please try again.",
        "Theme", "Keep the current dark shell, or switch to the light palette.", "Follow system",
        "Light", "Dark", "Proactive mode", "Manage your proactive companion from the menu bar.",
        "Open menu bar panel", "Model preferences", "Default provider",
        "Used for new chats until you change the session model.", "DeepSeek model",
        "deepseek-chat for everyday use. deepseek-reasoner for longer reasoning.", "API keys",
        "DeepSeek API key", "Stored in the OS keychain and injected into Host memory only.",
        "OpenAI API key", "Optional. Used when the default provider is OpenAI.", "Anthropic API key",
        "Optional. Used when the default provider is Anthropic.", "Proactive is off", "Taking a pause",
        "Waiting for context", "Ready to check", "Checking context", "Check needs attention",
        "Proactive enabled", "Proactive disabled", "Paused", "Resumed", "Configuration updated",
        "No context sources connected", "Context ready; actions not connected", "No new context",
        "Context check failed", "Connecting to Nuum…", "Your companion will resume after this break.",
        "A quieter kind of help, at the right moment.", "Enable proactive mode", "Resume now",
        "Pause proactive mode", "Pause…", "For 30 minutes", "For 1 hour", "Check setup",
        "Resumes at {time}", "Connections", "Context sources", "Available", "Not connected",
        "Agent actions",
        "Setup is ready. Context collection and autonomous actions are not enabled in this version.",
        "Recent activity", "Activity will appear here when you turn it on.",
        "Could not update proactive mode.", "Open Nunu", "Open Nuum", "Retry",
    ]
    for key in keys {
        #expect(SettingsCopy.contains(key), "missing copy \(key)")
    }
    #expect(!SettingsCopy.contains("Quit"))
}

@Test func redactSecretRemovesOnlyTheTypedKey() {
    #expect(redactSecret("keystore rejected sk-test", secret: "sk-test") == "keystore rejected …")
    #expect(redactSecret("Couldn't store secrets because encryption failed.", secret: "sk-test") == "Couldn't store secrets because encryption failed.")
    #expect(redactSecret("empty", secret: "") == "empty")
}
