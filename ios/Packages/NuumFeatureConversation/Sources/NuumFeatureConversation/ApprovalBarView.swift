#if canImport(SwiftUI)
import SwiftUI
import NuumContracts

struct ApprovalBarView: View {
    var pending: PendingTool
    var deciding: Bool
    var error: Banner?
    var onDecide: (ToolResolution) -> Void
    @Environment(\.conversationTheme) private var theme

    var body: some View {
        Group {
            if theme.compact {
                VStack(alignment: .leading, spacing: SandMetrics.spacing4) {
                    explanation
                    buttons.frame(maxWidth: .infinity, alignment: .trailing)
                    footnotes
                }
            } else {
                VStack(alignment: .leading, spacing: SandMetrics.spacing4) {
                    HStack(alignment: .center, spacing: SandMetrics.spacing4) {
                        explanation
                        buttons.fixedSize(horizontal: true, vertical: false)
                    }
                    footnotes
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: theme.compact ? .infinity : 640, alignment: .leading)
        .background(theme.color(SandToken.bgElevated), in: RoundedRectangle(cornerRadius: SandMetrics.radius2XL))
        .overlay(
            RoundedRectangle(cornerRadius: SandMetrics.radius2XL)
                .stroke(theme.color(SandToken.borderSubtle), lineWidth: 1)
        )
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
            if pending.action != .runCommand {
                Text(firstLine(pending.target))
                    .font(.system(size: SandMetrics.fontSM, design: .monospaced))
                    .foregroundStyle(theme.color(SandToken.textTertiary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            DisclosureGroup {
                Text(pending.details ?? pending.target)
                    .font(.system(size: SandMetrics.fontSM, design: .monospaced))
                    .foregroundStyle(theme.color(SandToken.textSecondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } label: {
                Text(theme.text(.executionDetails))
                    .font(.system(size: SandMetrics.fontSM, weight: .medium))
                    .foregroundStyle(theme.color(SandToken.textSecondary))
            }
        }
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !pending.alwaysEnabled {
                Text(theme.text(.dynamicCommand))
                    .font(.system(size: SandMetrics.fontXS))
                    .foregroundStyle(theme.color(SandToken.textTertiary))
            }
            if let error {
                Text(error.text(language: theme.language))
                    .font(.system(size: SandMetrics.fontXS))
                    .foregroundStyle(theme.color(SandToken.textDanger))
            }
        }
    }

    private var title: some View {
        let action = theme.text(actionCopy(pending.action))
        let base = pending.justification?.isEmpty == false
            ? pending.justification!
            : theme.text(.allowAction, ["action": action])
        return Text(base)
            .font(.system(size: SandMetrics.fontBase, weight: .semibold))
            .foregroundStyle(theme.color(SandToken.textPrimary))
    }

    private var buttons: some View {
        HStack(spacing: SandMetrics.spacing1) {
            decisionButton(.deny, label: .deny, fill: .clear, foreground: theme.color(SandToken.textSecondary), enabled: true)
            decisionButton(.once, label: .allowOnce, fill: theme.color(SandToken.fillSecondary), foreground: theme.color(SandToken.textPrimary), enabled: true)
            decisionButton(
                .always,
                label: .alwaysAllow,
                fill: theme.color(SandToken.fillPrimary),
                foreground: theme.color(SandToken.textOnPrimary),
                enabled: pending.alwaysEnabled
            )
        }
        .frame(maxWidth: theme.compact ? .infinity : nil, alignment: .trailing)
    }

    private func decisionButton(
        _ resolution: ToolResolution,
        label: CopyKey,
        fill: Color,
        foreground: Color,
        enabled: Bool
    ) -> some View {
        Button {
            onDecide(resolution)
        } label: {
            Text(theme.text(label))
                .font(.system(size: SandMetrics.fontSM, weight: .medium))
                .foregroundStyle(foreground)
                .frame(minHeight: SandMetrics.heightBase)
                .padding(.horizontal, 12)
                .frame(minHeight: SandMetrics.spacing11)
                .background(fill, in: RoundedRectangle(cornerRadius: SandMetrics.radiusLG))
        }
        .buttonStyle(ApprovalPressStyle(resolution: resolution, theme: theme, baseFill: fill, baseForeground: foreground))
        .disabled(deciding || !enabled)
        .accessibilityLabel(theme.text(label))
    }
}

private struct ApprovalPressStyle: ButtonStyle {
    var resolution: ToolResolution
    var theme: ConversationTheme
    var baseFill: Color
    var baseForeground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(pressedFill(configuration.isPressed), in: RoundedRectangle(cornerRadius: SandMetrics.radiusLG))
            .foregroundStyle(pressedForeground(configuration.isPressed))
    }

    private func pressedFill(_ pressed: Bool) -> Color {
        guard pressed else { return .clear }
        switch resolution {
        case .deny: return theme.color(SandToken.fillDangerSubtle)
        case .always: return theme.color(SandToken.fillPrimaryHover)
        case .once, .never: return baseFill
        }
    }

    private func pressedForeground(_ pressed: Bool) -> Color {
        guard pressed, resolution == .deny else { return baseForeground }
        return theme.color(SandToken.textDanger)
    }
}
#endif
