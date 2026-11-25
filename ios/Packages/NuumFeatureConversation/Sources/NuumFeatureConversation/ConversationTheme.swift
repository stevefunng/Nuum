#if canImport(SwiftUI)
import SwiftUI
import NuumContracts

extension Color {
    init(sand hex: String) {
        let parsed = parseSandHex(hex) ?? RGBA(r: 0, g: 0, b: 0, a: 1)
        self.init(.sRGB, red: parsed.r, green: parsed.g, blue: parsed.b, opacity: parsed.a)
    }
}

struct ConversationTheme: Equatable {
    var dark: Bool
    var language: Language
    var reduceMotion: Bool
    var compact: Bool

    func color(_ token: SandColor) -> Color {
        Color(sand: token.hex(dark: dark))
    }

    func text(_ key: CopyKey, _ values: [String: String] = [:]) -> String {
        ConversationCopy.text(key, language: language, values: values)
    }

    func text(_ key: String, _ values: [String: String] = [:]) -> String {
        ConversationCopy.text(key, language: language, values: values)
    }
}

private struct ConversationThemeKey: EnvironmentKey {
    static let defaultValue = ConversationTheme(dark: true, language: .zhCN, reduceMotion: false, compact: false)
}

extension EnvironmentValues {
    var conversationTheme: ConversationTheme {
        get { self[ConversationThemeKey.self] }
        set { self[ConversationThemeKey.self] = newValue }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(width: width, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indexes {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indexes: [Int]
        var height: CGFloat
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var indexes: [Int] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = rowWidth == 0 ? size.width : rowWidth + spacing + size.width
            if next > width, !indexes.isEmpty {
                rows.append(Row(indexes: indexes, height: rowHeight))
                indexes = [index]
                rowWidth = size.width
                rowHeight = size.height
            } else {
                indexes.append(index)
                rowWidth = next
                rowHeight = max(rowHeight, size.height)
            }
        }
        if !indexes.isEmpty { rows.append(Row(indexes: indexes, height: rowHeight)) }
        return rows
    }
}

func readPickedFiles(_ urls: [URL]) -> Result<[PickedFile], CopyKey> {
    var files: [PickedFile] = []
    for url in urls {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let bytes = try? Data(contentsOf: url) else { return .failure(.readFailed) }
        let name = url.lastPathComponent.isEmpty ? "attachment" : url.lastPathComponent
        files.append(PickedFile(name: name, mimeType: mimeType(forFileName: name), bytes: bytes))
    }
    return .success(files)
}
#endif
