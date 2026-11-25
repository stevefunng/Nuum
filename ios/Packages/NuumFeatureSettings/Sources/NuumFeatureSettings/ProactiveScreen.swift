#if canImport(SwiftUI)
import SwiftUI
import NuumContracts

final class ProactiveSession: Sendable {
    let model: ProactiveModel
    init(settings: any SettingsPort, proactive: any ProactivePort, clock: any Clock) {
        model = ProactiveModel(settings: settings, proactive: proactive, clock: clock)
    }
}

/// In-app Proactive panel opened from Settings. Back returns to General.
/// There is no tray and no Quit control. Agent actions follow `ProactiveSnapshot.actionsAvailable`.
public struct ProactiveScreen: View {
    @State private var session: ProactiveSession
    @State private var ui = ProactiveUiState()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onBack: () -> Void
    private let onOpenAgent: (String) -> Void
    private let onOpenShell: () -> Void

    public init(
        settings: any SettingsPort,
        proactive: any ProactivePort,
        clock: any Clock,
        onBack: @escaping () -> Void,
        onOpenAgent: @escaping (String) -> Void,
        onOpenShell: @escaping () -> Void
    ) {
        _session = State(initialValue: ProactiveSession(settings: settings, proactive: proactive, clock: clock))
        self.onBack = onBack
        self.onOpenAgent = onOpenAgent
        self.onOpenShell = onOpenShell
    }

    public var body: some View {
        let palette = settingsPalette(preference: ui.theme, systemIsDark: colorScheme == .dark)
        let language = displayLanguage(ui.language)
        let presentation = presentProactive(ui, language: language)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backRow(language: language, palette: palette)
                wordmark(palette: palette)
                statusCard(presentation: presentation, language: language, palette: palette)
                actions(presentation: presentation, language: language, palette: palette)
                if let resumesAt = presentation.resumesAt {
                    Text(resumesAt)
                        .font(.system(size: SandMetric.fontXS))
                        .foregroundStyle(Color(palette.textSecondary))
                        .frame(maxWidth: .infinity)
                        .padding(.top, SandMetric.spacing2)
                        .accessibilityIdentifier("resumes-at")
                }
                connections(presentation: presentation, language: language, palette: palette)
                activity(presentation: presentation, language: language, palette: palette)
                if let failure = presentation.failureKey {
                    failureRow(language: language, key: failure)
                }
                footer(presentation: presentation, language: language, palette: palette)
            }
            .padding(SandMetric.spacing5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(palette.bgElevated))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(palette.modeName)
        .animation(settingsAnimation(reduceMotion: reduceMotion), value: presentation.phase)
        .task { await session.model.run() }
        .task {
            for await next in session.model.updates {
                ui = next
            }
        }
    }

    private func backRow(language: Language, palette: SettingsPalette) -> some View {
        let label = SettingsCopy.text(language, "Back")
        return HStack {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    SettingsIcon(name: "chevron-right", tint: Color(palette.textSecondary))
                        .rotationEffect(.degrees(180))
                    Text(label)
                        .font(.system(size: SandMetric.fontSM))
                        .foregroundStyle(Color(palette.textSecondary))
                }
                .frame(minHeight: SandMetric.spacing11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityIdentifier("proactive-back")
            Spacer()
        }
    }

    private func wordmark(palette: SettingsPalette) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Nuum")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(Color(palette.textPrimary))
            Spacer()
            Text("Proactive mode")
                .font(.system(size: SandMetric.fontXS))
                .foregroundStyle(Color(palette.textSecondary))
        }
        .padding(.bottom, 18)
    }

    private func statusCard(
        presentation: ProactivePresentation,
        language: Language,
        palette: SettingsPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor(presentation.dot, palette: palette))
                    .frame(width: 6, height: 6)
                Text(SettingsCopy.text(language, presentation.statusKey))
                    .font(.system(size: SandMetric.fontXS))
                    .foregroundStyle(Color(palette.textSecondary))
                    .accessibilityIdentifier("proactive-status")
            }
            .padding(.horizontal, SandMetric.spacing4)
            Text(presentation.title)
                .font(.system(size: 23, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(Color(palette.textPrimary))
                .padding(.horizontal, SandMetric.spacing4)
                .padding(.top, 10)
            Text(SettingsCopy.text(language, presentation.subtitleKey))
                .font(.system(size: SandMetric.fontSM))
                .foregroundStyle(Color(palette.textSecondary))
                .padding(.horizontal, SandMetric.spacing4)
                .padding(.top, 4)
                .padding(.bottom, SandMetric.spacing4)
            Rectangle()
                .fill(Color(palette.strokeTertiary))
                .frame(height: 1)
            HStack {
                Text(SettingsCopy.text(language, "Proactive mode"))
                    .font(.system(size: SandMetric.fontBase))
                    .tracking(SandMetric.trackingBase)
                    .foregroundStyle(Color(palette.textPrimary))
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { presentation.switchOn },
                        set: { _ in Task { await session.model.toggle() } }
                    )
                )
                .labelsHidden()
                .toggleStyle(SandToggleStyle(palette: palette))
                .disabled(!presentation.switchEnabled)
                .accessibilityLabel(SettingsCopy.text(language, "Enable proactive mode"))
                .accessibilityIdentifier("proactive-switch")
            }
            .padding(.horizontal, SandMetric.spacing4)
            .frame(minHeight: SandMetric.spacing12)
        }
        .padding(.top, 17)
        .background(
            RoundedRectangle(cornerRadius: SandMetric.radius2XL, style: .continuous)
                .fill(Color(palette.textPrimary).opacity(0.04))
        )
    }

    @ViewBuilder
    private func actions(
        presentation: ProactivePresentation,
        language: Language,
        palette: SettingsPalette
    ) -> some View {
        HStack(spacing: SandMetric.spacing2) {
            if presentation.showsResume {
                ProactiveTextButton(
                    title: SettingsCopy.text(language, "Resume now"),
                    enabled: !ui.busy,
                    identifier: "resume-now",
                    palette: palette
                ) { Task { await session.model.resume() } }
            } else {
                SettingsChoice(
                    label: SettingsCopy.text(language, "Pause proactive mode"),
                    valueLabel: SettingsCopy.text(language, "Pause…"),
                    enabled: presentation.pauseEnabled,
                    options: [
                        (String(ProactivePause.thirtyMinutes), SettingsCopy.text(language, "For 30 minutes")),
                        (String(ProactivePause.oneHour), SettingsCopy.text(language, "For 1 hour")),
                    ],
                    selected: nil,
                    identifier: "pause-select",
                    palette: palette,
                    flexible: true
                ) { value in
                    guard let duration = Int64(value) else { return }
                    Task { await session.model.pause(duration) }
                }
                .frame(maxWidth: .infinity)
            }
            ProactiveTextButton(
                title: SettingsCopy.text(language, "Check setup"),
                enabled: presentation.checkEnabled,
                identifier: "check-setup",
                palette: palette
            ) { Task { await session.model.check() } }
        }
        .padding(.top, SandMetric.spacing3)
    }

    private func connections(
        presentation: ProactivePresentation,
        language: Language,
        palette: SettingsPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            connectionLine(
                label: SettingsCopy.text(language, "Context sources"),
                value: SettingsCopy.text(language, presentation.sources.key),
                identifier: "context-sources-status",
                palette: palette
            )
            connectionLine(
                label: SettingsCopy.text(language, "Agent actions"),
                value: SettingsCopy.text(language, presentation.actions.key),
                identifier: "agent-actions-status",
                palette: palette
            )
            Text(SettingsCopy.text(
                language,
                "Setup is ready. Context collection and autonomous actions are not enabled in this version."
            ))
            .font(.system(size: SandMetric.fontXS))
            .foregroundStyle(Color(palette.textTertiary))
            .padding(.top, SandMetric.spacing2)
        }
        .padding(.top, SandMetric.spacing5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SettingsCopy.text(language, "Connections"))
        .accessibilityIdentifier("connections")
    }

    private func connectionLine(label: String, value: String, identifier: String, palette: SettingsPalette) -> some View {
        HStack {
            Text(label)
                .font(.system(size: SandMetric.fontSM))
                .foregroundStyle(Color(palette.textPrimary))
            Spacer()
            Text(value)
                .font(.system(size: SandMetric.fontXS))
                .foregroundStyle(Color(palette.textSecondary))
                .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 6)
    }

    private func activity(
        presentation: ProactivePresentation,
        language: Language,
        palette: SettingsPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(SettingsCopy.text(language, "Recent activity"))
                .font(.system(size: SandMetric.fontXS, weight: .medium))
                .foregroundStyle(Color(palette.textSecondary))
            if let empty = presentation.activityEmptyKey {
                Text(SettingsCopy.text(language, empty))
                    .font(.system(size: SandMetric.fontXS))
                    .foregroundStyle(Color(palette.textTertiary))
                    .padding(.top, SandMetric.spacing2)
            } else {
                ForEach(Array(presentation.activity.enumerated()), id: \.offset) { _, line in
                    HStack {
                        Text(line.literal ?? SettingsCopy.text(language, line.textKey))
                            .font(.system(size: SandMetric.fontXS))
                            .foregroundStyle(Color(palette.textPrimary))
                        Spacer()
                        Text(line.time)
                            .font(.system(size: SandMetric.fontXS))
                            .foregroundStyle(Color(palette.textTertiary))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    private func failureRow(language: Language, key: String) -> some View {
        let message = SettingsCopy.text(language, key)
        let retry = SettingsCopy.text(language, "Retry")
        return Button {
            Task { await session.model.retry() }
        } label: {
            HStack(spacing: SandMetric.spacing2) {
                Text(message)
                Text(retry).underline()
            }
            .font(.system(size: SandMetric.fontXS))
            .foregroundStyle(Color(SandRGBA(css: proactiveErrorCSS)))
            .frame(maxWidth: .infinity, minHeight: SandMetric.spacing11, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.top, SandMetric.spacing3)
        .accessibilityLabel(message)
        .accessibilityIdentifier("proactive-retry")
    }

    private func footer(
        presentation: ProactivePresentation,
        language: Language,
        palette: SettingsPalette
    ) -> some View {
        let label = SettingsCopy.text(language, presentation.footerKey)
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(palette.strokeTertiary))
                .frame(height: 1)
                .padding(.top, SandMetric.spacing3)
            Button {
                if let id = presentation.footerAgentId {
                    onOpenAgent(id)
                } else {
                    onOpenShell()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: SandMetric.fontSM))
                        .foregroundStyle(Color(palette.textPrimary))
                    SettingsIcon(name: "chevron-right", tint: Color(palette.textPrimary))
                    Spacer()
                }
                .frame(minHeight: SandMetric.spacing11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(presentation.footerAgentId == nil ? "open-nuum" : "open-nunu")
        }
    }

    private func dotColor(_ dot: ProactiveDot, palette: SettingsPalette) -> Color {
        if let css = dot.fixedCSS {
            return Color(SandRGBA(css: css))
        }
        return Color(palette.textTertiary)
    }
}
#endif
