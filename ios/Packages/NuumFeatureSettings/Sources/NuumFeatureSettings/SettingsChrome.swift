#if canImport(SwiftUI)
import SwiftUI
import NuumContracts

extension Color {
    init(_ sand: SandRGBA) {
        self.init(.sRGB, red: sand.red, green: sand.green, blue: sand.blue, opacity: sand.alpha)
    }
}

func settingsAnimation(reduceMotion: Bool) -> Animation? {
    switch settingsMotion(reduceMotion: reduceMotion) {
    case .instant:
        nil
    case .slowerOutStrong:
        // `--nuum-easing-out-strong` over `--nuum-duration-slower`.
        .timingCurve(0.165, 0.84, 0.44, 1, duration: SandMetric.durationSlower)
    }
}

struct SettingsIcon: View {
    var name: String
    var tint: Color

    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            switch name {
            case "settings-gear":
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let rect = CGRect(
                    x: center.x - size.width * 0.18,
                    y: center.y - size.height * 0.18,
                    width: size.width * 0.36,
                    height: size.height * 0.36
                )
                context.stroke(Path(ellipseIn: rect), with: .color(tint), style: stroke)
                for index in 0..<8 {
                    let angle = CGFloat(index) * .pi / 4
                    let inner = size.width * 0.28
                    let outer = size.width * 0.46
                    var line = Path()
                    line.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                    line.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                    context.stroke(line, with: .color(tint), style: stroke)
                }
            case "sliders":
                let ys = [size.height * 0.22, size.height * 0.5, size.height * 0.78]
                let knobs = [0.32, 0.68, 0.45]
                for index in ys.indices {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: ys[index]))
                    line.addLine(to: CGPoint(x: size.width, y: ys[index]))
                    context.stroke(line, with: .color(tint), style: stroke)
                    let knob = CGRect(x: size.width * knobs[index] - 2.2, y: ys[index] - 2.2, width: 4.4, height: 4.4)
                    context.fill(Path(ellipseIn: knob), with: .color(tint))
                }
            case "close":
                let inset = size.width * 0.22
                var first = Path()
                first.move(to: CGPoint(x: inset, y: inset))
                first.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
                var second = Path()
                second.move(to: CGPoint(x: size.width - inset, y: inset))
                second.addLine(to: CGPoint(x: inset, y: size.height - inset))
                context.stroke(first, with: .color(tint), style: stroke)
                context.stroke(second, with: .color(tint), style: stroke)
            case "chevron-right":
                var chevron = Path()
                chevron.move(to: CGPoint(x: size.width * 0.35, y: size.height * 0.22))
                chevron.addLine(to: CGPoint(x: size.width * 0.68, y: size.height / 2))
                chevron.addLine(to: CGPoint(x: size.width * 0.35, y: size.height * 0.78))
                context.stroke(chevron, with: .color(tint), style: stroke)
            default:
                break
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

struct SettingsNavButton: View {
    var label: String
    var icon: String
    var selected: Bool
    var wide: Bool
    var palette: SettingsPalette
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SettingsIcon(name: icon, tint: Color(selected ? palette.textPrimary : palette.textSecondary))
                Text(label)
                    .font(.system(size: SandMetric.fontBase))
                    .tracking(SandMetric.trackingBase)
                    .foregroundStyle(Color(selected ? palette.textPrimary : palette.textSecondary))
                if !wide { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: wide ? .infinity : nil, alignment: .leading)
            .frame(minHeight: wide ? 32 : SandMetric.spacing11)
            .background(
                RoundedRectangle(cornerRadius: SandMetric.radiusBase, style: .continuous)
                    .fill(selected ? Color(palette.fillGhostSelected) : .clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
    }
}

struct SettingsGroup<Content: View>: View {
    var title: String
    var palette: SettingsPalette
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: SandMetric.fontSM, weight: .medium))
                .foregroundStyle(Color(palette.textSecondary))
                .padding(.bottom, SandMetric.spacing2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRow<Control: View>: View {
    var title: String
    var description: String
    var alert: String?
    var palette: SettingsPalette
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: SandMetric.spacing4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: SandMetric.fontBase, weight: .medium))
                        .tracking(SandMetric.trackingBase)
                        .foregroundStyle(Color(palette.textPrimary))
                    Text(description)
                        .font(.system(size: SandMetric.fontSM))
                        .foregroundStyle(Color(palette.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                control()
            }
            .padding(.vertical, SandMetric.spacing3)
            if let alert {
                Text(alert)
                    .font(.system(size: SandMetric.fontSM))
                    .foregroundStyle(Color(palette.textDanger))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, SandMetric.spacing2)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}

struct SettingsDivider: View {
    var palette: SettingsPalette

    var body: some View {
        Rectangle()
            .fill(Color(palette.borderSubtle))
            .frame(height: 1)
    }
}

struct SettingsChoice: View {
    var label: String
    var valueLabel: String
    var enabled: Bool
    var options: [(value: String, label: String)]
    var selected: String?
    var identifier: String
    var palette: SettingsPalette
    /// Proactive's pause control shares the row. Settings selects stay about 190 pt.
    var flexible: Bool = false
    var onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    onSelect(option.value)
                } label: {
                    if option.value == selected {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
                .accessibilityIdentifier("option-\(option.value)")
            }
        } label: {
            HStack(spacing: SandMetric.spacing2) {
                Text(valueLabel)
                    .font(.system(size: SandMetric.fontBase))
                    .tracking(SandMetric.trackingBase)
                    .foregroundStyle(Color(enabled ? palette.textPrimary : palette.textTertiary))
                    .lineLimit(1)
                Spacer(minLength: 8)
                SettingsIcon(name: "chevron-right", tint: Color(palette.textSecondary))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(
                minWidth: flexible ? 0 : 120,
                maxWidth: flexible ? .infinity : 190,
                minHeight: SandMetric.spacing11
            )
            .background(
                RoundedRectangle(cornerRadius: SandMetric.radiusLG, style: .continuous)
                    .fill(Color(palette.textPrimary).opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SandMetric.radiusLG, style: .continuous)
                    .strokeBorder(Color(palette.borderDefault), lineWidth: 1)
            )
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

struct APIKeyField: View {
    var label: String
    var text: Binding<String>
    var compact: Bool
    var identifier: String
    var palette: SettingsPalette
    var focus: FocusState<ProviderId?>.Binding
    var provider: ProviderId
    var onSubmit: () -> Void

    var body: some View {
        let metrics = apiKeyFieldMetrics(compact: compact)
        SecureField("", text: text)
            .textContentType(.password)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .font(.system(size: SandMetric.fontBase))
            .foregroundStyle(Color(palette.textPrimary))
            .padding(.horizontal, 9)
            .frame(minWidth: metrics.minWidth, idealWidth: metrics.fixedWidth, maxWidth: metrics.fixedWidth ?? .infinity)
            .frame(minHeight: SandMetric.spacing11)
            .background(
                RoundedRectangle(cornerRadius: SandMetric.radiusLG, style: .continuous)
                    .fill(Color(palette.bgInput))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SandMetric.radiusLG, style: .continuous)
                    .strokeBorder(Color(palette.borderDefault), lineWidth: 1)
            )
            .focused(focus, equals: provider)
            .onSubmit(onSubmit)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
    }
}

struct SandToggleStyle: ToggleStyle {
    var palette: SettingsPalette

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule(style: .continuous)
                .fill(Color(on ? palette.textPrimary : palette.fillControlTrack))
                .frame(width: 44, height: 26)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle()
                        .fill(Color(on ? palette.textOnPrimary : palette.bgElevated))
                        .frame(width: 22, height: 22)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
    }
}

struct ProactiveTextButton: View {
    var title: String
    var enabled: Bool
    var identifier: String
    var palette: SettingsPalette
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: SandMetric.fontSM))
                .foregroundStyle(Color(enabled ? palette.textPrimary : palette.textTertiary))
                .frame(maxWidth: .infinity, minHeight: 36)
                .frame(minHeight: SandMetric.spacing11)
                .overlay(
                    RoundedRectangle(cornerRadius: SandMetric.radiusLG, style: .continuous)
                        .strokeBorder(Color(palette.borderSubtle), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }
}
#endif
