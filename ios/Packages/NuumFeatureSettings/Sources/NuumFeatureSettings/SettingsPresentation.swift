import Foundation
import NuumContracts

// MARK: - Settings chrome

/// How this package lays out the settings surface once the shell has chosen a width class.
struct SettingsFrame: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Compact column. Background `--nuum-bg-editor`. Close returns to the sidebar.
        case page
        /// Regular dialog. `height == nil` means the panel hugs its content.
        case dialog(width: CGFloat, height: CGFloat?, maxHeight: CGFloat)
    }

    var kind: Kind
    /// Regular dialogs dismiss when the scrim is tapped.
    var showsScrim: Bool
    /// Regular and window `≥ 900 pt` uses the Mac side column. Narrower windows put the sections under the title.
    var sideNavigation: Bool
    /// CSS variable for the panel background.
    var backgroundToken: String
}

func settingsFrame(widthClass: SettingsWidthClass, windowWidth: CGFloat, windowHeight: CGFloat) -> SettingsFrame {
    switch widthClass {
    case .compact:
        return SettingsFrame(
            kind: .page,
            showsScrim: false,
            sideNavigation: false,
            backgroundToken: "--nuum-bg-editor"
        )
    case .regular:
        let sideNavigation = windowWidth >= 900
        if sideNavigation {
            return SettingsFrame(
                kind: .dialog(
                    width: min(860, windowWidth - 32),
                    height: nil,
                    maxHeight: windowHeight * 0.9
                ),
                showsScrim: true,
                sideNavigation: true,
                backgroundToken: "--nuum-bg-elevated"
            )
        }
        return SettingsFrame(
            kind: .dialog(
                width: windowWidth - 32,
                height: windowHeight - 32,
                maxHeight: windowHeight - 32
            ),
            showsScrim: true,
            sideNavigation: false,
            backgroundToken: "--nuum-bg-elevated"
        )
    }
}

/// Regular key fields are about 175 pt. Compact fields use the row's remaining width, at least 160 pt.
struct APIKeyFieldMetrics: Equatable, Sendable {
    var fixedWidth: CGFloat?
    var minWidth: CGFloat
}

func apiKeyFieldMetrics(compact: Bool) -> APIKeyFieldMetrics {
    if compact {
        return APIKeyFieldMetrics(fixedWidth: nil, minWidth: 160)
    }
    return APIKeyFieldMetrics(fixedWidth: 175, minWidth: 175)
}

enum SettingsSection: String, Equatable, Sendable {
    case general
    case models

    var titleKey: String {
        switch self {
        case .general: "General"
        case .models: "Models"
        }
    }
}

enum SettingsSurfacePhase: Equatable, Sendable {
    /// `settings.get` has not returned. Selectors stay disabled and no provider is shown.
    case loading
    /// The page can edit. Key fields still start empty; that is not an error.
    case ready
    /// The initial read failed. Selectors stay disabled.
    case loadFailed
}

/// Key fields always open empty. This page does not warn when no key is stored.
enum SettingsKeyNotice: Equatable, Sendable {
    case fieldsStartEmpty
    case missingKeyNotShown
}

struct SettingsPresentation: Equatable, Sendable {
    var phase: SettingsSurfacePhase
    var navigationEnabled: Bool
    var languageEnabled: Bool
    var themeEnabled: Bool
    var providerEnabled: Bool
    var deepSeekEnabled: Bool
    var showDeepSeekModel: Bool
    var languageValue: String?
    var themeValueKey: String?
    var providerValue: String?
    var modelValue: String?
    var languageAlertKey: String?
    var themeAlert: String?
    var providerAlert: String?
    var deepSeekAlert: String?
    var keyAlerts: [ProviderId: String]
    var loadError: String?
    var keyNotice: SettingsKeyNotice
    var missingKeyNotice: SettingsKeyNotice
    /// This surface does not show `2004`.
    var showsNoAPIKeyBanner: Bool
}

func presentSettings(_ state: SettingsUiState) -> SettingsPresentation {
    let phase: SettingsSurfacePhase = if state.loaded {
        .ready
    } else if state.loadError != nil {
        .loadFailed
    } else {
        .loading
    }
    let showDeepSeek = state.loaded && state.provider == .deepseek
    return SettingsPresentation(
        phase: phase,
        navigationEnabled: true,
        languageEnabled: state.loaded && !state.languageBusy,
        themeEnabled: state.loaded,
        providerEnabled: state.loaded,
        deepSeekEnabled: state.loaded && showDeepSeek,
        showDeepSeekModel: showDeepSeek,
        languageValue: state.language.map(languageLabel),
        themeValueKey: state.theme.map(themeKey),
        providerValue: state.loaded ? state.provider.map(providerLabel) : nil,
        modelValue: showDeepSeek ? state.modelId : nil,
        languageAlertKey: state.languageFailed ? "Could not change language. Please try again." : nil,
        themeAlert: state.themeError,
        providerAlert: state.providerError,
        deepSeekAlert: state.deepSeekModelError,
        keyAlerts: state.keyErrors,
        loadError: state.loadError,
        keyNotice: .fieldsStartEmpty,
        missingKeyNotice: .missingKeyNotShown,
        showsNoAPIKeyBanner: false
    )
}

func languageLabel(_ language: Language) -> String {
    switch language {
    case .zhCN: "中文"
    case .en: "English"
    }
}

func themeKey(_ theme: ThemePreference) -> String {
    switch theme {
    case .system: "Follow system"
    case .light: "Light"
    case .dark: "Dark"
    }
}

func providerLabel(_ provider: ProviderId) -> String {
    switch provider {
    case .deepseek: "DeepSeek"
    case .openai: "OpenAI"
    case .anthropic: "Anthropic"
    }
}

func modelRefForProvider(_ provider: ProviderId) -> ModelRef {
    ModelRef(provider: provider, model: defaultModelID(for: provider))
}

// MARK: - Proactive

enum ConnectionLabel: Equatable, Sendable {
    case available
    case notConnected

    var key: String {
        switch self {
        case .available: "Available"
        case .notConnected: "Not connected"
        }
    }
}

/// Agent-actions copy is a function of the snapshot flag, not a fixed switch.
func agentActionsLabel(actionsAvailable: Bool) -> ConnectionLabel {
    actionsAvailable ? .available : .notConnected
}

func contextSourcesLabel(_ availableSourceIds: [String]) -> ConnectionLabel {
    availableSourceIds.isEmpty ? .notConnected : .available
}

func proactiveCompanion(_ snapshot: ProactiveSnapshot?) -> ProactiveAgentSnapshot? {
    guard let snapshot, let id = snapshot.defaultAgentId else { return nil }
    return snapshot.agents.first { $0.agentId == id }
}

enum ProactiveSurfacePhase: Equatable, Sendable {
    case loading
    case empty
    case disabled
    case paused
    case waitingContext
    case ready
    case checking
    case error
}

struct ProactiveActivityLine: Equatable, Sendable {
    var textKey: String
    var literal: String?
    var time: String
}

struct ProactivePresentation: Equatable, Sendable {
    var phase: ProactiveSurfacePhase
    var statusKey: String
    var title: String
    var subtitleKey: String
    var dot: ProactiveDot
    var switchOn: Bool
    var switchEnabled: Bool
    var showsResume: Bool
    var pauseEnabled: Bool
    var checkEnabled: Bool
    var resumesAt: String?
    var sources: ConnectionLabel
    var actions: ConnectionLabel
    /// True only when `actions` was read from a snapshot. Loading does not invent a flag.
    var actionsFollowSnapshot: Bool
    var activity: [ProactiveActivityLine]
    var activityEmptyKey: String?
    var failureKey: String?
    var footerKey: String
    var footerAgentId: String?
    var showsQuit: Bool
    var showsNoAPIKeyBanner: Bool
    var showsPermissionDenied: Bool
    var showsDiscussionInterrupt: Bool
}

func presentProactive(
    _ state: ProactiveUiState,
    language: Language,
    timeZone: TimeZone = .current
) -> ProactivePresentation {
    let snapshot = state.snapshot
    let agent = proactiveCompanion(snapshot)
    let phase = proactivePhase(snapshot: snapshot, agent: agent)
    let statusKey = proactiveStatusKey(snapshot: snapshot, stateName: agent?.state)
    let paused = agent?.state == "paused"
    let enabled = agent?.policy.enabled == true
    let checkEnabled = snapshot != nil && enabled && !paused && agent?.state != "checking" && !state.busy
    let resumesAt: String? = if paused, let until = agent?.policy.pausedUntil {
        SettingsCopy.format(language, "Resumes at {time}", ["time": formatHourMinute(until, language: language, timeZone: timeZone)])
    } else {
        nil
    }
    let activity = Array((agent?.activity ?? []).prefix(3)).map { item in
        ProactiveActivityLine(
            textKey: activityKey(item.kind) ?? item.kind,
            literal: activityKey(item.kind) == nil ? item.kind : nil,
            time: formatHourMinute(item.at, language: language, timeZone: timeZone)
        )
    }
    let actionsFollowSnapshot = snapshot != nil
    return ProactivePresentation(
        phase: phase,
        statusKey: statusKey,
        title: agent?.name ?? "Nunu",
        subtitleKey: paused
            ? "Your companion will resume after this break."
            : "A quieter kind of help, at the right moment.",
        dot: proactiveDot(snapshot: snapshot, stateName: agent?.state),
        switchOn: enabled,
        switchEnabled: !state.busy && agent != nil,
        showsResume: paused,
        pauseEnabled: enabled && !state.busy && !paused,
        checkEnabled: checkEnabled,
        resumesAt: resumesAt,
        sources: snapshot.map { contextSourcesLabel($0.availableSourceIds) } ?? .notConnected,
        actions: snapshot.map { agentActionsLabel(actionsAvailable: $0.actionsAvailable) } ?? .notConnected,
        actionsFollowSnapshot: actionsFollowSnapshot,
        activity: activity,
        activityEmptyKey: activity.isEmpty ? "Activity will appear here when you turn it on." : nil,
        failureKey: state.failed ? "Could not update proactive mode." : nil,
        footerKey: agent == nil ? "Open Nuum" : "Open Nunu",
        footerAgentId: agent?.agentId,
        showsQuit: false,
        showsNoAPIKeyBanner: false,
        showsPermissionDenied: false,
        showsDiscussionInterrupt: false
    )
}

func proactivePhase(snapshot: ProactiveSnapshot?, agent: ProactiveAgentSnapshot?) -> ProactiveSurfacePhase {
    guard snapshot != nil else { return .loading }
    guard let agent else { return .empty }
    switch agent.state {
    case "paused":
        return .paused
    case "waiting-context":
        return .waitingContext
    case "ready":
        return .ready
    case "checking":
        return .checking
    case "error":
        return .error
    default:
        return .disabled
    }
}

func proactiveStatusKey(snapshot: ProactiveSnapshot?, stateName: String?) -> String {
    guard snapshot != nil else { return "Connecting to Nuum…" }
    switch stateName {
    case "disabled":
        return "Proactive is off"
    case "paused":
        return "Taking a pause"
    case "waiting-context":
        return "Waiting for context"
    case "ready":
        return "Ready to check"
    case "checking":
        return "Checking context"
    case "error":
        return "Check needs attention"
    default:
        return "Proactive is off"
    }
}

func proactiveDot(snapshot: ProactiveSnapshot?, stateName: String?) -> ProactiveDot {
    guard snapshot != nil else { return .tertiary }
    switch stateName {
    case "paused":
        return .paused
    case "waiting-context", "ready":
        return .ready
    case "error":
        return .attention
    default:
        return .tertiary
    }
}

func activityKey(_ kind: String) -> String? {
    switch kind {
    case "enabled": "Proactive enabled"
    case "disabled": "Proactive disabled"
    case "paused": "Paused"
    case "resumed": "Resumed"
    case "configured": "Configuration updated"
    case "waiting-context": "No context sources connected"
    case "context-ready": "Context ready; actions not connected"
    case "no-change": "No new context"
    case "error": "Context check failed"
    default: nil
    }
}

func formatHourMinute(_ epochMillis: Int64, language: Language, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language == .zhCN ? "zh-CN" : "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    formatter.timeZone = timeZone
    return formatter.string(from: Date(timeIntervalSince1970: Double(epochMillis) / 1000))
}
