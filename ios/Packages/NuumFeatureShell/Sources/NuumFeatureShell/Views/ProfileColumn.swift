#if canImport(SwiftUI)
import SwiftUI

struct ProfileColumn: View {
    var session: ShellSession
    var agentID: String
    @Environment(\.sandTheme) private var theme
    @Environment(\.shellCopy) private var copy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let agent = session.agents.first { $0.profile.id == agentID }
        VStack(spacing: 0) {
            header
            if let agent {
                ScrollView {
                    badge(agent)
                    ExecutionPreferencesForm(
                        execution: agent.settings.execution,
                        projectRoot: agent.settings.workspace?.projectRoot,
                        workspaceRevoked: session.workspaceRevoked.contains(agentID),
                        saving: session.executionSaving,
                        error: session.executionError,
                        onCommands: { permission in Task { await session.setCommands(agentID: agentID, commands: permission) } },
                        onRevokeCommand: { grant in Task { await session.revokeCommand(agentID: agentID, grant: grant) } },
                        onRevokeNetwork: { grant in Task { await session.revokeNetwork(agentID: agentID, grant: grant) } },
                        onOpenFolder: { Task { await session.openFolder(agentID: agentID) } }
                    )
                    .padding(.bottom, SandMetric.spacing6)
                }
            } else {
                Spacer()
            }
        }
        .background(theme.color(.bgEditor).color)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.text("Nunu identity"))
        .overlay {
            if session.identityOpen, let agent {
                IdentityDialog(session: session, agent: agent)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(copy.text("Nunu identity"))
                .font(sandFont(SandMetric.fontBase, weight: .semibold))
                .foregroundStyle(theme.color(.textPrimary).color)
            Spacer()
            IconButton(systemName: "chevron.right", label: copy.text("Close profile")) {
                session.closeProfile()
            }
        }
        .padding(.leading, SandMetric.spacing4)
        .padding(.trailing, SandMetric.spacing2)
        .frame(height: SandMetric.spacing14)
    }

    private func badge(_ agent: AgentView) -> some View {
        BadgeFace(session: session, agent: agent, reduceMotion: reduceMotion) {
            session.openIdentity()
        }
        .padding(SandMetric.spacing4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.text("Click to edit profile"))
    }
}

private struct BadgeFace: View {
    var session: ShellSession
    var agent: AgentView
    var reduceMotion: Bool
    var onEdit: () -> Void
    @Environment(\.sandTheme) private var theme
    @Environment(\.shellCopy) private var copy
    @State private var waving = false

    var body: some View {
        let appearance = NunuAppearance.resolve(
            agentID: agent.profile.id,
            color: agent.profile.avatarColor,
            shape: agent.profile.avatarShape,
            material: agent.profile.avatarMaterial
        )
        VStack(spacing: SandMetric.spacing3) {
            seal(appearance)
            Text(agent.profile.name)
                .font(sandFont(24, weight: .semibold))
                .tracking(-0.7)
                .foregroundStyle(BadgePaper.ink.color)
                .lineLimit(1)
            if !agent.profile.tags.isEmpty {
                FlowTags(tags: agent.profile.tags)
            }
            Text(agent.profile.description.isEmpty ? copy.text("What should this Agent do?") : agent.profile.description)
                .font(sandFont(SandMetric.fontBase))
                .foregroundStyle(agent.profile.description.isEmpty ? BadgePaper.muted.color : BadgePaper.ink.color)
                .multilineTextAlignment(.center)
            HStack {
                Text("\(copy.text("Created on")) \(createdOnDate(agent.profile.createdAt))")
                    .font(sandFont(SandMetric.fontXS))
                    .foregroundStyle(BadgePaper.muted.color)
                Spacer()
                Text("Nuum")
                    .font(sandFont(SandMetric.fontBase, weight: .semibold))
                    .foregroundStyle(BadgePaper.ink.color)
                    .accessibilityLabel("Nuum")
            }
        }
        .padding(EdgeInsets(top: 28, leading: 24, bottom: 16, trailing: 24))
        .frame(maxWidth: .infinity, minHeight: 390)
        .background(badgePaper)
        .clipShape(RoundedRectangle(cornerRadius: SandMetric.radiusBadge))
        .contentShape(RoundedRectangle(cornerRadius: SandMetric.radiusBadge))
        .onTapGesture(perform: onEdit)
        .accessibilityAddTraits(.isButton)
        .overlay(
            RoundedRectangle(cornerRadius: SandMetric.radiusBadge)
                .stroke(theme.color(.textSecondary).color, lineWidth: 2)
                .padding(-4)
                .opacity(0)
        )
    }

    private func seal(_ appearance: NunuAppearance) -> some View {
        ZStack {
            SealRing()
            Button {
                session.greet(agent.profile.id)
                guard !reduceMotion else { return }
                withAnimation(.timingCurve(0.165, 0.84, 0.44, 1, duration: SandMetric.durationSlower)) {
                    waving = true
                }
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(SandMetric.durationSlower * 1_000_000_000))
                    withAnimation(.timingCurve(0.165, 0.84, 0.44, 1, duration: SandMetric.durationSlower)) {
                        waving = false
                    }
                }
            } label: {
                NunuAvatarView(
                    appearance: appearance,
                    size: 112 * (reduceMotion ? 1 : (waving ? 1.04 : 1)),
                    fullBody: true,
                    running: agent.runtime.status == .running
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copy.text("Greet {name}", ["name": agent.profile.name]))
        }
        .frame(height: 168)
    }

    private var badgePaper: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: BadgePaper.top.color, location: 0),
                    .init(color: BadgePaper.mid.color, location: 0.55),
                    .init(color: BadgePaper.bottom.color, location: 1),
                ],
                startPoint: UnitPoint(x: 0.15, y: 0),
                endPoint: UnitPoint(x: 0.85, y: 1)
            )
            Canvas { context, size in
                var y = 0.0
                while y < size.height {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    context.fill(Path(rect), with: .color(BadgePaper.line.color))
                    y += 2.5
                }
            }
        }
    }
}

private struct FlowTags: View {
    var tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(sandFont(SandMetric.fontXS))
                    .foregroundStyle(BadgePaper.ink.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().stroke(BadgePaper.muted.color, lineWidth: 1))
            }
        }
    }
}

private struct SealRing: View {
    private let legend = "NUUM · A MIND OF YOUR OWN · NUUM · ALWAYS WITH YOU · "

    var body: some View {
        ZStack {
            Circle().stroke(BadgePaper.muted.color, lineWidth: 1).padding(8)
            ForEach(Array(legend.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(sandFont(8, weight: .semibold))
                    .foregroundStyle(BadgePaper.ink.color)
                    .rotationEffect(.degrees(Double(index) / Double(legend.count) * 360))
                    .offset(y: -72)
                    .rotationEffect(.degrees(Double(index) / Double(legend.count) * 360))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct IdentityDialog: View {
    var session: ShellSession
    var agent: AgentView
    @Environment(\.sandTheme) private var theme
    @Environment(\.shellCopy) private var copy
    @State private var name = ""
    @State private var tags = ""
    @State private var description = ""

    var body: some View {
        ZStack {
            theme.color(.scrim).color
                .onTapGesture { if !session.identitySaving { session.closeIdentity() } }
            VStack(alignment: .leading, spacing: SandMetric.spacing3) {
                HStack {
                    Text(copy.text("Nunu identity"))
                        .font(sandFont(SandMetric.fontBase, weight: .semibold))
                        .foregroundStyle(theme.color(.textPrimary).color)
                    Spacer()
                    IconButton(systemName: "xmark", label: copy.text("Close dialog"), enabled: !session.identitySaving) {
                        session.closeIdentity()
                    }
                }
                field(copy.text("Name"), text: $name, prompt: "")
                field(copy.text("Tags (optional)"), text: $tags, prompt: copy.text("Research, design, operations"))
                field(copy.text("Description"), text: $description, prompt: copy.text("What should this Agent do?"))
                if session.showsTemplates(agent.profile.id) {
                    Text(copy.text("Recommended templates"))
                        .font(sandFont(SandMetric.fontSM))
                        .foregroundStyle(theme.color(.textSecondary).color)
                    ForEach(identityTemplates, id: \.nameKey) { template in
                        Button {
                            let filled = applying(template, copy: copy)
                            name = filled.name
                            tags = filled.tags
                            description = filled.description
                        } label: {
                            HStack(alignment: .top, spacing: SandMetric.spacing2) {
                                NunuAvatarView(
                                    appearance: NunuAppearance.resolve(agentID: template.nameKey, color: template.colorID, shape: template.shape, material: "matte"),
                                    size: 18,
                                    fullBody: false
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(copy.text(template.nameKey))
                                        .font(sandFont(SandMetric.fontBase, weight: .semibold))
                                        .foregroundStyle(theme.color(.textPrimary).color)
                                    Text(copy.text(template.descriptionKey))
                                        .font(sandFont(SandMetric.fontXS))
                                        .foregroundStyle(theme.color(.textSecondary).color)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(session.identitySaving)
                    }
                }
                if let error = session.identityError {
                    Text(copy.text(error))
                        .font(sandFont(SandMetric.fontSM))
                        .foregroundStyle(theme.color(.textDanger).color)
                }
                HStack {
                    Spacer()
                    PillButton(title: copy.text("Cancel"), primary: false, enabled: !session.identitySaving) {
                        session.closeIdentity()
                    }
                    PillButton(title: copy.text(session.identitySaving ? "Saving…" : "Finish"), primary: true, enabled: !session.identitySaving) {
                        Task { await session.saveIdentity(id: agent.profile.id, name: name, tagsRaw: tags, description: description) }
                    }
                }
            }
            .padding(SandMetric.spacing4)
            .frame(maxWidth: 420)
            .background(theme.color(.bgElevated).color)
            .clipShape(RoundedRectangle(cornerRadius: SandMetric.radius3XL))
        }
        .onAppear(perform: load)
    }

    private func load() {
        name = agent.profile.name
        tags = agent.profile.tags.joined(separator: ", ")
        description = agent.profile.description
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(sandFont(SandMetric.fontSM))
                .foregroundStyle(theme.color(.textSecondary).color)
            TextField(prompt, text: text)
                .font(sandFont(SandMetric.fontBase))
                .foregroundStyle(theme.color(.textPrimary).color)
                .padding(SandMetric.spacing2)
                .overlay(RoundedRectangle(cornerRadius: SandMetric.radiusLG).stroke(theme.color(.borderDefault).color, lineWidth: 1))
                .disabled(session.identitySaving)
                .accessibilityLabel(label)
        }
    }
}
#endif
