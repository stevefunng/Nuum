#if canImport(SwiftUI)
import SwiftUI

extension SandColor {
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

private struct SandThemeKey: EnvironmentKey {
    static let defaultValue = SandTheme.dark
}

private struct ShellCopyKey: EnvironmentKey {
    static let defaultValue = ShellCopy.fallback
}

public extension EnvironmentValues {
    var sandTheme: SandTheme {
        get { self[SandThemeKey.self] }
        set { self[SandThemeKey.self] = newValue }
    }

    var shellCopy: ShellCopy {
        get { self[ShellCopyKey.self] }
        set { self[ShellCopyKey.self] = newValue }
    }
}

func sandFont(_ size: Double, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
    .system(size: size, weight: weight, design: design)
}

struct IconButton: View {
    var systemName: String
    var label: String
    var enabled: Bool = true
    var action: () -> Void
    @Environment(\.sandTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(sandFont(15, weight: .medium))
                .foregroundStyle(theme.color(.textPrimary).color)
                .frame(width: SandMetric.heightSM, height: SandMetric.heightSM)
                .frame(width: SandMetric.spacing11, height: SandMetric.spacing11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

struct PillButton: View {
    var title: String
    var primary: Bool
    var enabled: Bool = true
    var action: () -> Void
    @Environment(\.sandTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(sandFont(SandMetric.fontBase, weight: primary ? .semibold : .regular))
                .foregroundStyle((primary ? theme.color(.textOnPrimary) : theme.color(.textPrimary)).color)
                .padding(.horizontal, SandMetric.spacing4)
                .frame(height: SandMetric.heightLG)
                .background(
                    Capsule().fill((primary ? theme.color(.fillPrimary) : theme.color(.bgSecondary)).color)
                )
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct MenuPanel: View {
    var entries: [MenuEntry]
    var width: Double?
    var onSelect: (MenuKind) -> Void
    @Environment(\.sandTheme) private var theme
    @Environment(\.shellCopy) private var copy

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                if entry.separatorBefore {
                    Rectangle()
                        .fill(theme.color(.borderSubtle).color)
                        .frame(height: 1)
                        .padding(.vertical, 4)
                }
                Button {
                    onSelect(entry.kind)
                } label: {
                    HStack(spacing: SandMetric.spacing2) {
                        Image(systemName: icon(entry.kind))
                            .frame(width: 16)
                        Text(copy.text(entry.title))
                            .font(sandFont(SandMetric.fontBase))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(theme.color(entry.enabled ? .textPrimary : .textTertiary).color)
                    .padding(.horizontal, SandMetric.spacing3)
                    .frame(minHeight: SandMetric.spacing11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!entry.enabled)
            }
        }
        .padding(.vertical, SandMetric.spacing2)
        .frame(minWidth: width ?? 208, alignment: .leading)
        .background(theme.color(.bgElevated).color)
        .clipShape(RoundedRectangle(cornerRadius: SandMetric.radiusXL))
        .overlay(
            RoundedRectangle(cornerRadius: SandMetric.radiusXL)
                .stroke(theme.color(.borderSubtle).color, lineWidth: 1)
        )
        .shadow(color: theme.color(.shadowPopover).color, radius: 16, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.text("Sidebar actions"))
    }

    private func icon(_ kind: MenuKind) -> String {
        switch kind {
        case .pin, .unpin: "pin"
        case .moveToGroup, .group: "folder"
        case .moveToNewGroup, .newGroup, .createNunu: "plus"
        case .editProfile, .rename: "pencil"
        case .copyID: "doc.on.doc"
        case .back: "chevron.left"
        case .unassigned: "sidebar.left"
        case .moveUp: "arrow.up"
        case .moveDown: "arrow.down"
        case .ungroup: "rectangle.3.group"
        case .createWork: "person.2"
        }
    }
}

struct ShellTopBar: View {
    var title: String
    var titleLabel: String
    var showBack: Bool
    var onBack: () -> Void
    var onTitle: (() -> Void)?
    @Environment(\.sandTheme) private var theme
    @Environment(\.shellCopy) private var copy

    var body: some View {
        HStack(spacing: SandMetric.spacing2) {
            if showBack {
                IconButton(systemName: "chevron.left", label: copy.text("Agents"), action: onBack)
            }
            Spacer(minLength: 0)
            if let onTitle {
                Button(action: onTitle) {
                    Text(title)
                        .font(sandFont(SandMetric.fontBase, weight: .semibold))
                        .foregroundStyle(theme.color(.textPrimary).color)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(titleLabel)
            } else {
                Text(title)
                    .font(sandFont(SandMetric.fontBase, weight: .semibold))
                    .foregroundStyle(theme.color(.textPrimary).color)
                    .lineLimit(1)
                    .accessibilityLabel(titleLabel)
            }
            Spacer(minLength: 0)
            Color.clear.frame(width: showBack ? SandMetric.spacing11 : 0, height: 1)
        }
        .padding(.horizontal, SandMetric.spacing2)
        .frame(height: SandMetric.spacing14)
    }
}
#endif
