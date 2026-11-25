#if canImport(SwiftUI)
import SwiftUI
import NuumContracts

/// Command execution for one Nunu. The caller saves through `AgentPort`.
/// `ExecutionPreferences` has no `externalGrants` list, so the local-computer fold stays hidden
/// until a later contracts change adds that field.
public struct ExecutionPreferencesForm: View {
    private var execution: ExecutionPreferences?
    private var projectRoot: String?
    private var workspaceRevoked: Bool
    private var saving: Bool
    private var error: CopyLine?
    private var onCommands: (CommandPermission) -> Void
    private var onRevokeCommand: (CommandGrant) -> Void
    private var onRevokeNetwork: (NetworkGrant) -> Void
    private var onOpenFolder: () -> Void

    @Environment(\.sandTheme) private var theme
    @Environment(\.shellCopy) private var copy

    public init(
        execution: ExecutionPreferences?,
        projectRoot: String?,
        workspaceRevoked: Bool,
        saving: Bool,
        error: CopyLine?,
        onCommands: @escaping (CommandPermission) -> Void,
        onRevokeCommand: @escaping (CommandGrant) -> Void,
        onRevokeNetwork: @escaping (NetworkGrant) -> Void,
        onOpenFolder: @escaping () -> Void
    ) {
        self.execution = execution
        self.projectRoot = projectRoot
        self.workspaceRevoked = workspaceRevoked
        self.saving = saving
        self.error = error
        self.onCommands = onCommands
        self.onRevokeCommand = onRevokeCommand
        self.onRevokeNetwork = onRevokeNetwork
        self.onOpenFolder = onOpenFolder
    }

    public var body: some View {
        let commands = execution?.commands ?? .ask
        VStack(alignment: .leading, spacing: SandMetric.spacing2) {
            Text(copy.text("Workspace and permissions"))
                .font(sandFont(SandMetric.fontBase, weight: .semibold))
                .foregroundStyle(theme.color(.textPrimary).color)
            HStack {
                Text(copy.text("Personal workspace"))
                    .font(sandFont(SandMetric.fontBase))
                    .foregroundStyle(theme.color(.textPrimary).color)
                Spacer()
                PillButton(title: copy.text("Open folder"), primary: false, enabled: !saving, action: onOpenFolder)
            }
            Text(pathLine)
                .font(sandFont(SandMetric.fontSM, design: .monospaced))
                .foregroundStyle(theme.color(.textSecondary).color)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(copy.text("Room tasks use the shared room workspace."))
                .font(sandFont(SandMetric.fontSM))
                .foregroundStyle(theme.color(.textSecondary).color)
            Text(copy.text("Command execution"))
                .font(sandFont(SandMetric.fontBase))
                .foregroundStyle(theme.color(.textPrimary).color)
                .accessibilityLabel(copy.text("Command execution"))
            HStack(spacing: SandMetric.spacing2) {
                choice(copy.text("Allow inside sandbox"), selected: commands != .never, enabled: !saving) {
                    if commands != .ask { onCommands(.ask) }
                }
                choice(copy.text("Deny"), selected: commands == .never, enabled: !saving) {
                    if commands != .never { onCommands(.never) }
                }
            }
            Text(copy.text("Permission applies only to this Nunu and workspace."))
                .font(sandFont(SandMetric.fontSM))
                .foregroundStyle(theme.color(.textTertiary).color)
            if let grants = execution?.commandGrants, !grants.isEmpty {
                Text(copy.text("Remembered commands ({count})", ["count": grants.count]))
                    .font(sandFont(SandMetric.fontBase))
                    .foregroundStyle(theme.color(.textPrimary).color)
                ForEach(Array(grants.enumerated()), id: \.offset) { _, grant in
                    grantRow(title: grant.command, detail: grantDetail(grant.workspaceId), enabled: !saving) {
                        onRevokeCommand(grant)
                    }
                }
            }
            HStack {
                Text(copy.text("Tool network"))
                    .font(sandFont(SandMetric.fontBase))
                    .foregroundStyle(theme.color(.textPrimary).color)
                Spacer()
                Text(copy.text("Denied by default"))
                    .font(sandFont(SandMetric.fontSM))
                    .foregroundStyle(theme.color(.textSecondary).color)
            }
            if let grants = execution?.networkGrants, !grants.isEmpty {
                ForEach(Array(grants.enumerated()), id: \.offset) { _, grant in
                    grantRow(title: grant.target, detail: grantDetail(grant.workspaceId), enabled: !saving) {
                        onRevokeNetwork(grant)
                    }
                }
            } else {
                Text(copy.text("Network access requires your approval."))
                    .font(sandFont(SandMetric.fontSM))
                    .foregroundStyle(theme.color(.textSecondary).color)
            }
            if let error {
                Text(copy.text(error))
                    .font(sandFont(SandMetric.fontSM))
                    .foregroundStyle(theme.color(.textDanger).color)
            }
        }
        .padding(.horizontal, SandMetric.spacing4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.text("Workspace and permissions"))
    }

    private var pathLine: String {
        if workspaceRevoked { return copy.text("No workspace selected") }
        if let projectRoot, !projectRoot.isEmpty { return projectRoot }
        return copy.text("No workspace selected")
    }

    private func grantDetail(_ workspaceID: String) -> String {
        if workspaceID == execution?.workspaceId { return copy.text("Personal workspace") }
        return copy.text("Former room")
    }

    private func choice(_ title: String, selected: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(sandFont(SandMetric.fontSM, weight: .medium))
                .foregroundStyle(theme.color(.textPrimary).color)
                .padding(.horizontal, SandMetric.spacing3)
                .frame(height: SandMetric.heightLG)
                .background(
                    Capsule().fill(theme.color(selected ? .fillSelected : .fillSecondary).color)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func grantRow(title: String, detail: String, enabled: Bool, revoke: @escaping () -> Void) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(sandFont(SandMetric.fontSM, design: .monospaced))
                    .foregroundStyle(theme.color(.textPrimary).color)
                Text(detail)
                    .font(sandFont(SandMetric.fontXS))
                    .foregroundStyle(theme.color(.textTertiary).color)
            }
            Spacer()
            Button(copy.text("Revoke"), action: revoke)
                .font(sandFont(SandMetric.fontSM))
                .disabled(!enabled)
                .buttonStyle(.plain)
        }
    }
}
#endif
