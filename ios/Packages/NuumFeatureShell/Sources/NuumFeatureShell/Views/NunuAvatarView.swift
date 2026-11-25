#if canImport(SwiftUI)
import SwiftUI

struct NunuAvatarView: View {
    var appearance: NunuAppearance
    var size: Double
    var fullBody: Bool
    var running: Bool = false
    @Environment(\.sandTheme) private var theme

    var body: some View {
        let box = fullBody
            ? CGRect(x: 0, y: 0, width: NunuViewBox.bodySide, height: NunuViewBox.bodySide)
            : CGRect(x: NunuViewBox.avatarX, y: NunuViewBox.avatarY, width: NunuViewBox.avatarSide, height: NunuViewBox.avatarSide)
        let shape = NunuVectorShape(data: NunuPaths.data(for: appearance.shape), viewBox: box)
        ZStack(alignment: .bottomTrailing) {
            avatarFill(shape)
            if running {
                Circle()
                    .fill(theme.color(.fillAccent).color)
                    .frame(width: SandMetric.statusDot, height: SandMetric.statusDot)
                    .overlay(Circle().stroke(theme.color(.bgChrome).color, lineWidth: 1))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func avatarFill(_ shape: NunuVectorShape) -> some View {
        switch materialStyle(appearance) {
        case .matte(let color):
            shape.fill(color.color)
        case .felt(let color):
            shape.fill(color.color)
                .overlay(feltDots.mask(shape))
        case .plush(let value, let dark):
            shape.fill(LinearGradient(colors: [value.color, dark.color], startPoint: .top, endPoint: .bottom))
        case .glass(let pigment):
            shape.fill(pigment.color)
                .overlay(highlight.mask(shape))
        case .aurora(let pigment):
            shape.fill(pigment.color)
                .overlay(highlight.mask(shape))
                .overlay(auroraSweep.mask(shape))
        }
    }

    private var feltDots: some View {
        Canvas { context, size in
            let step = max(4, size.width / 8)
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    let rect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                    context.fill(Path(ellipseIn: rect), with: .color(theme.color(.textPrimary).color.opacity(0.08)))
                    x += step
                }
                y += step
            }
        }
    }

    private var highlight: some View {
        Ellipse()
            .fill(theme.color(.textOnColor).color.opacity(0.28))
            .frame(width: 18, height: 10)
            .offset(y: -8)
    }

    private var auroraSweep: some View {
        Rectangle()
            .fill(theme.color(.fillSupplementary4).color.opacity(0.22))
            .frame(width: 14)
            .rotationEffect(.degrees(24))
    }
}

struct NunuVectorShape: Shape {
    var data: String
    var viewBox: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / max(viewBox.width, 1)
        let scaleY = rect.height / max(viewBox.height, 1)
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(
                x: rect.minX + (x - viewBox.minX) * scaleX,
                y: rect.minY + (y - viewBox.minY) * scaleY
            )
        }
        for verb in parseSVGPath(data) {
            switch verb {
            case .move(let x, let y):
                path.move(to: point(x, y))
            case .curve(let x1, let y1, let x2, let y2, let x, let y):
                path.addCurve(to: point(x, y), control1: point(x1, y1), control2: point(x2, y2))
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }
}

struct WorkMark: View {
    var initial: String
    var members: [NunuAppearance]
    var size: Double
    @Environment(\.sandTheme) private var theme

    var body: some View {
        if members.isEmpty {
            Text(initial)
                .font(sandFont(SandMetric.fontBase, weight: .semibold))
                .foregroundStyle(theme.color(.textPrimary).color)
                .frame(width: size, height: size)
                .background(theme.color(.bgSecondary).color)
                .clipShape(RoundedRectangle(cornerRadius: SandMetric.radiusWorkMark))
                .overlay(
                    RoundedRectangle(cornerRadius: SandMetric.radiusWorkMark)
                        .stroke(theme.color(.borderSubtle).color, lineWidth: 1)
                )
        } else {
            ZStack {
                ForEach(Array(members.enumerated()), id: \.offset) { index, member in
                    NunuAvatarView(appearance: member, size: size * 0.62, fullBody: false)
                        .offset(memberOffset(index: index, count: members.count, size: size))
                }
            }
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: SandMetric.radiusWorkMark)
                    .stroke(theme.color(.borderSubtle).color, lineWidth: 1)
            )
        }
    }

    private func memberOffset(index: Int, count: Int, size: Double) -> CGSize {
        let shift = size * 0.16
        switch (index, count) {
        case (0, 1): return .zero
        case (0, _): return CGSize(width: -shift, height: -shift)
        case (1, _): return CGSize(width: shift, height: -shift)
        case (2, _): return CGSize(width: -shift, height: shift)
        default: return CGSize(width: shift, height: shift)
        }
    }
}
#endif
