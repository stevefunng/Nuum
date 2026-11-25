#if canImport(SwiftUI)
import SwiftUI

struct CreateNunuPage: View {
    var session: ShellSession
    var card: Bool
    @Environment(\.sandTheme) private var theme
    @Environment(\.shellCopy) private var copy
    @FocusState private var nameFocused: Bool
    @State private var name = ""

    var body: some View {
        let draft = session.createDraft
        VStack(spacing: 0) {
            header
            ScrollView {
                unbox(draft)
                nameField
                palette(draft)
                if let error = session.createError {
                    Text(copy.text(error))
                        .font(sandFont(SandMetric.fontSM))
                        .foregroundStyle(theme.color(.textDanger).color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SandMetric.spacing4)
                        .padding(.top, SandMetric.spacing2)
                }
            }
            footer
        }
        .background(card ? theme.color(.bgElevated).color : theme.color(.bgEditor).color)
        .clipShape(RoundedRectangle(cornerRadius: card ? SandMetric.radius3XL : 0))
        .shadow(color: card ? theme.color(.shadowPopover).color : .clear, radius: card ? 18 : 0, y: card ? 10 : 0)
        .onAppear { nameFocused = true }
    }

    private var header: some View {
        HStack {
            Text(copy.text("Create new Nunu"))
                .font(sandFont(SandMetric.fontBase, weight: .semibold))
                .foregroundStyle(theme.color(.textPrimary).color)
            Spacer()
            IconButton(systemName: "xmark", label: copy.text("Close dialog"), enabled: !session.creating) {
                session.closeCreate()
            }
        }
        .padding(.leading, SandMetric.spacing4)
        .padding(.trailing, SandMetric.spacing2)
        .frame(minHeight: SandMetric.spacing14)
    }

    @ViewBuilder
    private func unbox(_ draft: CreateDraft?) -> some View {
        let appearance = appearance(draft)
        if session.unbox.reducedMotion || session.unbox.clockRegistrations == 0 {
            unboxArt(appearance: appearance, date: .distantFuture)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                unboxArt(appearance: appearance, date: timeline.date)
            }
        }
    }

    private func unboxArt(appearance: NunuAppearance?, date: Date) -> some View {
        let playback = session.unbox.playback(at: date)
        return ZStack {
            if playback.showsPackaging, let package = playback.package, let appearance {
                packaging(package, appearance: appearance)
                    .opacity(playback.packagingOpacity)
                    .accessibilityIdentifier("unbox-packaging")
            }
            if let appearance {
                NunuAvatarView(appearance: appearance, size: SandMetric.unboxBody * playback.avatarScale, fullBody: true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: unboxRegionHeight(windowHeight: session.windowHeight))
        .accessibilityHidden(true)
        .accessibilityIdentifier(playback.settled ? "unbox-settled" : "unbox-playing")
    }

    private func packaging(_ package: UnboxingPackage, appearance: NunuAppearance) -> some View {
        let fill = mix(SandColor(css: appearance.valueHex), onto: theme.color(.bgElevated), amount: 0.4).color
        switch package {
        case .softTray:
            RoundedRectangle(cornerRadius: SandMetric.radius3XL).fill(fill).frame(width: 168, height: 120)
        case .paperFold:
            PaperFold().fill(fill).frame(width: 168, height: 120)
        case .roundBox:
            Circle().fill(fill).frame(width: 140, height: 140)
        }
    }

    private var nameField: some View {
        TextField(copy.text("Give your Nunu a name"), text: $name)
            .focused($nameFocused)
            .multilineTextAlignment(.center)
            .font(sandFont(SandMetric.fontLG))
            .foregroundStyle(theme.color(.textPrimary).color)
            .frame(height: 36)
            .padding(.horizontal, SandMetric.spacing3)
            .overlay(RoundedRectangle(cornerRadius: SandMetric.radiusName).stroke(theme.color(.borderDefault).color, lineWidth: 1))
            .padding(.horizontal, SandMetric.spacing4)
            .disabled(session.creating)
            .onChange(of: name) { _, value in
                if value.count > SandMetric.nameMax {
                    name = String(value.prefix(SandMetric.nameMax))
                }
            }
            .accessibilityLabel(copy.text("Nunu name"))
            .accessibilityIdentifier("nunu-name")
    }

    private func palette(_ draft: CreateDraft?) -> some View {
        HStack(spacing: SandMetric.spacing2) {
            ForEach(avatarPalette(), id: \.id) { pigment in
                let selected = draft?.color == pigment.id
                Button {
                    session.selectCreateColor(pigment.id)
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(theme.color(selected ? .borderFocus : .borderSubtle).color, lineWidth: 1)
                            .frame(width: 36, height: 36)
                        Circle()
                            .fill(theme.color(.bgElevated).color)
                            .frame(width: 34, height: 34)
                        Circle()
                            .fill(SandColor(css: pigment.value).color)
                            .frame(width: SandMetric.swatch, height: SandMetric.swatch)
                    }
                    .frame(width: SandMetric.spacing11, height: SandMetric.spacing11)
                }
                .buttonStyle(.plain)
                .disabled(session.creating)
                .accessibilityLabel(copy.text(colorLabelKey(pigment.id)))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("swatch-\(pigment.id)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SandMetric.spacing4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.text("Nunu color"))
    }

    private var footer: some View {
        HStack(spacing: SandMetric.spacing2) {
            Spacer()
            PillButton(title: copy.text("Cancel"), primary: false, enabled: !session.creating) {
                session.closeCreate()
            }
            PillButton(
                title: copy.text(session.creating ? "Creating…" : "Create"),
                primary: true,
                enabled: !session.creating && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                Task { await session.submitCreate(name: name) }
            }
        }
        .padding(SandMetric.spacing4)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.color(.borderSubtle).color).frame(height: 1)
        }
    }

    private func appearance(_ draft: CreateDraft?) -> NunuAppearance? {
        guard let draft else { return nil }
        let pigment = avatarPalette().first { $0.id == draft.color }
        return NunuAppearance(
            agentID: "create",
            colorID: draft.color,
            shape: draft.shape,
            material: draft.material,
            valueHex: pigment?.value ?? "#bac8a8",
            darkHex: pigment?.dark ?? "#7e9270",
            chatHex: pigment?.chat ?? "#526c43"
        )
    }
}

private struct PaperFold: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let fold = min(rect.width, rect.height) * 0.22
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
#endif
