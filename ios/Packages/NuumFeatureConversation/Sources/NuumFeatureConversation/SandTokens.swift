import Foundation

/// CSS px taken as pt. Eight-digit colors are `#RRGGBBAA`, alpha in the last byte.
struct SandColor: Equatable, Sendable {
    var light: String
    var dark: String

    func hex(dark: Bool) -> String { dark ? self.dark : light }
}

enum SandToken: Sendable {
    static let bgEditor = SandColor(light: "#fcfcfc", dark: "#070707")
    static let textPrimary = SandColor(light: "#141414", dark: "#fcfcfc")
    static let textSecondary = SandColor(light: "#14141499", dark: "#fcfcfc99")
    static let textTertiary = SandColor(light: "#14141466", dark: "#fcfcfc66")
    static let textOnColor = SandColor(light: "#fcfcfc", dark: "#fcfcfc")
    static let textOnPrimary = SandColor(light: "#fcfcfc", dark: "#141414")
    static let textLink = SandColor(light: "#0c64c1", dark: "#459ffe")
    static let textDanger = SandColor(light: "#c21d2e", dark: "#ff5667")
    static let bgElevated = SandColor(light: "#fcfcfc", dark: "#181818")
    static let bgInput = SandColor(light: "#fcfcfc", dark: "#2f2f2f")
    static let bgTertiary = SandColor(light: "#77777717", dark: "#7777772c")
    static let borderSubtle = SandColor(light: "#1414140d", dark: "#fcfcfc0d")
    static let borderDefault = SandColor(light: "#14141426", dark: "#fcfcfc26")
    static let borderStrong = SandColor(light: "#1414144d", dark: "#fcfcfc4d")
    static let borderFocus = SandColor(light: "#14141466", dark: "#fcfcfc66")
    static let borderDanger = SandColor(light: "#ff5667", dark: "#c21d2e")
    static let fillPrimary = SandColor(light: "#070707", dark: "#fafafa")
    static let fillPrimaryHover = SandColor(light: "#2f2f2f", dark: "#d5d5d5")
    static let fillSecondary = SandColor(light: "#77777717", dark: "#7777772c")
    static let fillElevated = SandColor(light: "#fcfcfc", dark: "#2f2f2f")
    static let fillGhostHover = SandColor(light: "#77777717", dark: "#7777772c")
    static let fillGhostSelected = SandColor(light: "#7777772b", dark: "#77777752")
    static let fillDangerSubtle = SandColor(light: "#ff263c17", dark: "#ff263c2c")
    static let fillBubbleAgent = SandColor(light: "#eeeeee", dark: "#262626")
    static let fillWarning = SandColor(light: "#ff9800", dark: "#ff9800")
    static let fillDanger = SandColor(light: "#ff263c", dark: "#ff263c")
    static let fillAccent = SandColor(light: "#1084fe", dark: "#1084fe")
    static let bgScrim = SandColor(light: "#14141480", dark: "#141414b2")
    static let shimmerBase = SandColor(light: "#14141466", dark: "#fcfcfc66")
    static let shimmerHighlight = SandColor(light: "#141414", dark: "#fcfcfc")
}

enum SandMetrics {
    static let spacing0_5 = 2.0
    static let spacing1 = 4.0
    static let spacing1_5 = 6.0
    static let spacing2 = 8.0
    static let spacing3 = 12.0
    static let spacing4 = 16.0
    static let spacing7 = 28.0
    static let spacing8 = 32.0
    static let spacing11 = 44.0
    static let spacing12 = 48.0
    static let spacing14 = 56.0
    static let fontXS = 11.0
    static let fontSM = 12.0
    static let fontBase = 13.0
    static let fontLG = 14.0
    static let lineLG = 22.0
    static let radiusSM = 4.0
    static let radiusLG = 10.0
    static let radius2XL = 16.0
    static let radius3XL = 18.0
    static let radius4XL = 18.0
    static let toolRadius = 12.0
    static let heightBase = 28.0
    static let durationSlow = 0.2
    static let wordmark = 28.0
    static let wordmarkTracking = -0.04 * 28.0
    static let fade = 46.0
    static let composerMax = 120.0
    static let imageMax = 320.0
    static let peerMax = 0.88
    static let emptyMin = 0.42
}

struct RGBA: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double
}

func parseSandHex(_ hex: String) -> RGBA? {
    var text = hex
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.count == 6 || text.count == 8, let value = UInt32(text, radix: 16) else { return nil }
    let expanded = text.count == 6 ? (value << 8) | 0xff : value
    return RGBA(
        r: Double((expanded >> 24) & 0xff) / 255,
        g: Double((expanded >> 16) & 0xff) / 255,
        b: Double((expanded >> 8) & 0xff) / 255,
        a: Double(expanded & 0xff) / 255
    )
}
