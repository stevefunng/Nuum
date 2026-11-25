#if canImport(SwiftUI)
import SwiftUI
import NuumContracts

final class SettingsSession: Sendable {
    let model: SettingsModel
    init(settings: any SettingsPort, secrets: any SecretWriter) {
        model = SettingsModel(settings: settings, secrets: secrets)
    }
}

/// General and Models.
///
/// The shell passes `widthClass`. Compact is a page pushed from the sidebar; regular is a dialog.
/// API key fields start empty and are written through `SecretWriter` on blur. They are never filled
/// from Keychain, and this view never reads a stored key back. Execution preferences are not here.
public struct SettingsScreen: View {
    @State private var session: SettingsSession
    @State private var ui = SettingsUiState()
    @State private var section = SettingsSection.general
    @State private var drafts: [ProviderId: String] = [
        .deepseek: "",
        .openai: "",
        .anthropic: "",
    ]
    @FocusState private var focusedKey: ProviderId?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let widthClass: SettingsWidthClass
    private let onClose: () -> Void
    private let onOpenProactive: () -> Void

    public init(
        settings: any SettingsPort,
        secrets: any SecretWriter,
        widthClass: SettingsWidthClass,
        onClose: @escaping () -> Void,
        onOpenProactive: @escaping () -> Void
    ) {
        _session = State(initialValue: SettingsSession(settings: settings, secrets: secrets))
        self.widthClass = widthClass
        self.onClose = onClose
        self.onOpenProactive = onOpenProactive
    }

    public var body: some View {
        let palette = settingsPalette(preference: ui.theme, systemIsDark: colorScheme == .dark)
        let presentation = presentSettings(ui)
        let language = displayLanguage(ui.language)
        GeometryReader { proxy in
            let frame = settingsFrame(
                widthClass: widthClass,
                windowWidth: proxy.size.width,
                windowHeight: proxy.size.height
            )
            ZStack {
                if frame.showsScrim {
                    Color(palette.scrim)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onClose)
                        .accessibilityLabel(SettingsCopy.text(language, "Close"))
                        .accessibilityAddTraits(.isButton)
                }
                panel(
                    frame: frame,
                    palette: palette,
                    presentation: presentation,
                    language: language
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(settingsPalette(preference: ui.theme, systemIsDark: colorScheme == .dark).modeName)
        .task { await session.model.run() }
        .task {
            for await next in session.model.updates {
                ui = next
            }
        }
        .onChange(of: focusedKey) { previous, current in
            guard let previous, previous != current else { return }
            commit(previous)
        }
    }

    @ViewBuilder
    private func panel(
        frame: SettingsFrame,
        palette: SettingsPalette,
        presentation: SettingsPresentation,
        language: Language
    ) -> some View {
        let background = frame.backgroundToken == "--nuum-bg-editor" ? palette.bgEditor : palette.bgElevated
        let chrome = panelChrome(frame: frame, palette: palette, presentation: presentation, language: language)
        switch frame.kind {
        case .page:
            chrome
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(background))
        case .dialog(let width, let height, let maxHeight):
            chrome
                .frame(maxWidth: .infinity, maxHeight: height == nil ? maxHeight : .infinity, alignment: .top)
                .frame(width: width, height: height)
                .frame(maxHeight: maxHeight)
                .background(Color(background))
                .clipShape(RoundedRectangle(cornerRadius: SandMetric.radiusXL, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SandMetric.radiusXL, style: .continuous)
                        .strokeBorder(Color(palette.borderSubtle), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private func panelChrome(
        frame: SettingsFrame,
        palette: SettingsPalette,
        presentation: SettingsPresentation,
        language: Language
    ) -> some View {
        if frame.sideNavigation {
            HStack(spacing: 0) {
                sideNav(palette: palette, language: language)
                VStack(spacing: 0) {
                    header(palette: palette, language: language)
                    scrollingBody(presentation: presentation, palette: palette, language: language, compact: false)
                }
            }
        } else {
            VStack(spacing: 0) {
                header(palette: palette, language: language)
                topNav(palette: palette, language: language)
                scrollingBody(
                    presentation: presentation,
                    palette: palette,
                    language: language,
                    compact: widthClass == .compact
                )
            }
        }
    }

    private func header(palette: SettingsPalette, language: Language) -> some View {
        let title = SettingsCopy.text(language, section.titleKey)
        let close = SettingsCopy.text(language, "Close")
        return HStack(alignment: .center) {
            Text(title)
                .font(.system(size: SandMetric.fontBase, weight: .medium))
                .tracking(SandMetric.trackingBase)
                .foregroundStyle(Color(palette.textPrimary))
            Spacer()
            Button(action: onClose) {
                SettingsIcon(name: "close", tint: Color(palette.textSecondary))
                    .frame(minWidth: SandMetric.spacing11, minHeight: SandMetric.spacing11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(close)
            .accessibilityIdentifier("close-settings")
        }
        .padding(.leading, SandMetric.spacing4)
        .padding(.trailing, SandMetric.spacing2)
        .overlay(alignment: .bottom) { SettingsDivider(palette: palette) }
    }

    private func sideNav(palette: SettingsPalette, language: Language) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            navButtons(palette: palette, language: language, wide: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 54)
        .padding(.bottom, SandMetric.spacing3)
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(palette.textPrimary).opacity(0.02))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SettingsCopy.text(language, "Settings sections"))
        .accessibilityIdentifier("settings-sections")
    }

    private func topNav(palette: SettingsPalette, language: Language) -> some View {
        HStack(spacing: SandMetric.spacing2) {
            navButtons(palette: palette, language: language, wide: false)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SandMetric.spacing4)
        .padding(.vertical, SandMetric.spacing2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SettingsCopy.text(language, "Settings sections"))
        .accessibilityIdentifier("settings-sections")
    }

    @ViewBuilder
    private func navButtons(palette: SettingsPalette, language: Language, wide: Bool) -> some View {
        SettingsNavButton(
            label: SettingsCopy.text(language, "General"),
            icon: "settings-gear",
            selected: section == .general,
            wide: wide,
            palette: palette
        ) { section = .general }
        .accessibilityIdentifier("section-general")
        SettingsNavButton(
            label: SettingsCopy.text(language, "Models"),
            icon: "sliders",
            selected: section == .models,
            wide: wide,
            palette: palette
        ) { section = .models }
        .accessibilityIdentifier("section-models")
    }

    private func scrollingBody(
        presentation: SettingsPresentation,
        palette: SettingsPalette,
        language: Language,
        compact: Bool
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SandMetric.spacing6) {
                if let loadError = presentation.loadError {
                    Text(loadError)
                        .font(.system(size: SandMetric.fontSM))
                        .foregroundStyle(Color(palette.textDanger))
                        .accessibilityLabel(loadError)
                }
                if section == .general {
                    general(presentation: presentation, palette: palette, language: language, compact: compact)
                } else {
                    models(presentation: presentation, palette: palette, language: language, compact: compact)
                }
            }
            .padding(SandMetric.spacing6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(settingsAnimation(reduceMotion: reduceMotion), value: section)
    }

    @ViewBuilder
    private func general(
        presentation: SettingsPresentation,
        palette: SettingsPalette,
        language: Language,
        compact: Bool
    ) -> some View {
        SettingsGroup(title: SettingsCopy.text(language, "Appearance"), palette: palette) {
            SettingsRow(
                title: SettingsCopy.text(language, "Language"),
                description: SettingsCopy.text(language, "Choose the language used throughout Nuum."),
                alert: presentation.languageAlertKey.map { SettingsCopy.text(language, $0) },
                palette: palette
            ) {
                SettingsChoice(
                    label: SettingsCopy.text(language, "Language"),
                    valueLabel: presentation.languageValue ?? "",
                    enabled: presentation.languageEnabled,
                    options: [
                        (Language.zhCN.rawValue, "中文"),
                        (Language.en.rawValue, "English"),
                    ],
                    selected: ui.language?.rawValue,
                    identifier: "language-select",
                    palette: palette
                ) { value in
                    let next: Language = value == Language.en.rawValue ? .en : .zhCN
                    Task { await session.model.selectLanguage(next) }
                }
            }
            SettingsDivider(palette: palette)
            SettingsRow(
                title: SettingsCopy.text(language, "Theme"),
                description: SettingsCopy.text(language, "Keep the current dark shell, or switch to the light palette."),
                alert: presentation.themeAlert,
                palette: palette
            ) {
                SettingsChoice(
                    label: SettingsCopy.text(language, "Theme"),
                    valueLabel: presentation.themeValueKey.map { SettingsCopy.text(language, $0) } ?? "",
                    enabled: presentation.themeEnabled,
                    options: [
                        (ThemePreference.system.rawValue, SettingsCopy.text(language, "Follow system")),
                        (ThemePreference.light.rawValue, SettingsCopy.text(language, "Light")),
                        (ThemePreference.dark.rawValue, SettingsCopy.text(language, "Dark")),
                    ],
                    selected: ui.theme?.rawValue,
                    identifier: "theme-select",
                    palette: palette
                ) { value in
                    guard let theme = ThemePreference(rawValue: value) else { return }
                    Task { await session.model.selectTheme(theme) }
                }
            }
        }
        SettingsGroup(title: SettingsCopy.text(language, "Proactive mode"), palette: palette) {
            SettingsRow(
                title: "Nunu",
                description: SettingsCopy.text(language, "Manage your proactive companion from the menu bar."),
                alert: nil,
                palette: palette
            ) {
                let label = SettingsCopy.text(language, "Open menu bar panel")
                Button(action: onOpenProactive) {
                    Text(label)
                        .font(.system(size: SandMetric.fontBase, weight: .medium))
                        .tracking(SandMetric.trackingBase)
                        .foregroundStyle(Color(palette.textPrimary))
                        .padding(.horizontal, 9)
                        .frame(minHeight: SandMetric.spacing11)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityIdentifier("open-proactive")
            }
        }
    }

    @ViewBuilder
    private func models(
        presentation: SettingsPresentation,
        palette: SettingsPalette,
        language: Language,
        compact: Bool
    ) -> some View {
        SettingsGroup(title: SettingsCopy.text(language, "Model preferences"), palette: palette) {
            SettingsRow(
                title: SettingsCopy.text(language, "Default provider"),
                description: SettingsCopy.text(language, "Used for new chats until you change the session model."),
                alert: presentation.providerAlert,
                palette: palette
            ) {
                SettingsChoice(
                    label: SettingsCopy.text(language, "Default provider"),
                    valueLabel: presentation.providerValue ?? "",
                    enabled: presentation.providerEnabled,
                    options: [ProviderId.deepseek, .openai, .anthropic].map {
                        ($0.rawValue, providerLabel($0))
                    },
                    selected: ui.provider?.rawValue,
                    identifier: "provider-select",
                    palette: palette
                ) { value in
                    guard let provider = ProviderId(rawValue: value) else { return }
                    Task { await session.model.selectProvider(provider) }
                }
            }
            if presentation.showDeepSeekModel {
                SettingsDivider(palette: palette)
                SettingsRow(
                    title: SettingsCopy.text(language, "DeepSeek model"),
                    description: SettingsCopy.text(
                        language,
                        "deepseek-chat for everyday use. deepseek-reasoner for longer reasoning."
                    ),
                    alert: presentation.deepSeekAlert,
                    palette: palette
                ) {
                    SettingsChoice(
                        label: SettingsCopy.text(language, "DeepSeek model"),
                        valueLabel: presentation.modelValue ?? "",
                        enabled: presentation.deepSeekEnabled,
                        options: [DeepSeekModelID.chat, DeepSeekModelID.reasoner].map { ($0, $0) },
                        selected: ui.modelId,
                        identifier: "deepseek-model-select",
                        palette: palette
                    ) { value in
                        Task { await session.model.selectDeepSeekModel(value) }
                    }
                }
            }
        }
        SettingsGroup(title: SettingsCopy.text(language, "API keys"), palette: palette) {
            keyRow(
                .deepseek,
                title: "DeepSeek API key",
                description: "Stored in the OS keychain and injected into Host memory only.",
                presentation: presentation,
                palette: palette,
                language: language,
                compact: compact
            )
            SettingsDivider(palette: palette)
            keyRow(
                .openai,
                title: "OpenAI API key",
                description: "Optional. Used when the default provider is OpenAI.",
                presentation: presentation,
                palette: palette,
                language: language,
                compact: compact
            )
            SettingsDivider(palette: palette)
            keyRow(
                .anthropic,
                title: "Anthropic API key",
                description: "Optional. Used when the default provider is Anthropic.",
                presentation: presentation,
                palette: palette,
                language: language,
                compact: compact
            )
        }
    }

    private func keyRow(
        _ provider: ProviderId,
        title: String,
        description: String,
        presentation: SettingsPresentation,
        palette: SettingsPalette,
        language: Language,
        compact: Bool
    ) -> some View {
        SettingsRow(
            title: SettingsCopy.text(language, title),
            description: SettingsCopy.text(language, description),
            alert: presentation.keyAlerts[provider],
            palette: palette
        ) {
            APIKeyField(
                label: SettingsCopy.text(language, title),
                text: draft(provider),
                compact: compact,
                identifier: "api-key-\(provider.rawValue)",
                palette: palette,
                focus: $focusedKey,
                provider: provider,
                onSubmit: { commit(provider) }
            )
        }
    }

    private func draft(_ provider: ProviderId) -> Binding<String> {
        Binding(
            get: { drafts[provider] ?? "" },
            set: { drafts[provider] = $0 }
        )
    }

    /// Blur writes the field. The characters stay in the secure field and are not copied into any text node.
    private func commit(_ provider: ProviderId) {
        let value = drafts[provider] ?? ""
        Task { await session.model.commitAPIKey(provider: provider, value: value) }
    }
}
#endif
