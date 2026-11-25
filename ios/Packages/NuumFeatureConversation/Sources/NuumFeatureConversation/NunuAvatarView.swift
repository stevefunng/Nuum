#if canImport(SwiftUI)
import SwiftUI

struct NunuShape: Shape {
    var commands: [VectorCommand]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width, rect.height) / NunuSilhouette.bounds.width
        func point(_ value: VectorPoint) -> CGPoint {
            CGPoint(x: rect.minX + value.x * scale, y: rect.minY + value.y * scale)
        }
        for command in commands {
            switch command {
            case .move(let start):
                path.move(to: point(start))
            case .curve(let control1, let control2, let end):
                path.addCurve(to: point(end), control1: point(control1), control2: point(control2))
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }
}

struct NunuAvatarView: View {
    var agentId: String
    var colorId: String?
    var shapeId: String?
    var materialId: String?
    var size: CGFloat
    var activity: NunuActivity
    @Environment(\.conversationTheme) private var theme
    @State private var bob = false

    var body: some View {
        let appearance = resolveNunuAppearance(
            agentId: agentId,
            color: colorId,
            shape: shapeId,
            material: materialId
        )
        let moves = activity == .thinking || activity == .working
        ZStack(alignment: .bottomTrailing) {
            NunuShape(commands: NunuSilhouette.path(for: appearance.shape))
                .fill(Color(sand: appearance.valueHex))
                .opacity(appearance.material == "glass" || appearance.material == "aurora" ? 0.92 : 1)
                .offset(y: bob && moves && !theme.reduceMotion ? -2 : 0)
            if let dot = dotColor {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(theme.color(SandToken.bgEditor), lineWidth: 1))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear { startBobbing(moves: moves) }
        .onChange(of: moves) { _, next in
            bob = false
            startBobbing(moves: next)
        }
    }

    private var dotColor: Color? {
        switch activity {
        case .waiting: theme.color(SandToken.fillWarning)
        case .error: theme.color(SandToken.fillDanger)
        case .thinking, .working: theme.color(SandToken.fillAccent)
        case .idle, .sending, .receiving: nil
        }
    }

    private func startBobbing(moves: Bool) {
        guard moves, !theme.reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            bob = true
        }
    }
}
#endif
