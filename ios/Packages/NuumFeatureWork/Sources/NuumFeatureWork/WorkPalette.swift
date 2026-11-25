import Foundation
import NuumContracts

/// CSS `#RRGGBB` or `#RRGGBBAA`. Alpha is the last byte, matching the sand token table.
struct SandColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: String) {
        var raw = hex
        if raw.hasPrefix("#") { raw.removeFirst() }
        var number: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&number)
        switch raw.count {
        case 8:
            red = Self.channel(number >> 24)
            green = Self.channel(number >> 16)
            blue = Self.channel(number >> 8)
            alpha = Self.channel(number)
        case 6:
            red = Self.channel(number >> 16)
            green = Self.channel(number >> 8)
            blue = Self.channel(number)
            alpha = 1
        default:
            red = 0
            green = 0
            blue = 0
            alpha = 1
        }
    }

    func opacity(_ factor: Double) -> SandColor {
        SandColor(red: red, green: green, blue: blue, alpha: alpha * factor)
    }

    private static func channel(_ value: UInt64) -> Double {
        Double(value & 0xFF) / 255
    }
}

/// Tokens this surface paints. Names follow the sand and nuum CSS variables.
struct WorkPalette: Equatable, Sendable {
    var editor: SandColor
    var elevated: SandColor
    var textPrimary: SandColor
    var textSecondary: SandColor
    var textTertiary: SandColor
    var textWarning: SandColor
    var textDanger: SandColor
    var textOnColor: SandColor
    var textOnPrimary: SandColor
    var borderSubtle: SandColor
    var fillPrimary: SandColor
    var fillPrimaryHover: SandColor
    var fillSecondary: SandColor
    var bubbleUser: SandColor
    var dangerSubtle: SandColor
    var fillWarning: SandColor
    var fillAccent: SandColor
    var fillDanger: SandColor
    var scrim: SandColor
    var blue: SandColor
    var orange: SandColor
    var green: SandColor
    var magenta: SandColor

    static let dark = WorkPalette(
        editor: SandColor(hex: "#070707"),
        elevated: SandColor(hex: "#181818"),
        textPrimary: SandColor(hex: "#fcfcfc"),
        textSecondary: SandColor(hex: "#fcfcfc99"),
        textTertiary: SandColor(hex: "#fcfcfc66"),
        textWarning: SandColor(hex: "#ffaf38"),
        textDanger: SandColor(hex: "#ff5667"),
        textOnColor: SandColor(hex: "#fcfcfc"),
        textOnPrimary: SandColor(hex: "#141414"),
        borderSubtle: SandColor(hex: "#fcfcfc0d"),
        fillPrimary: SandColor(hex: "#fafafa"),
        fillPrimaryHover: SandColor(hex: "#d5d5d5"),
        fillSecondary: SandColor(hex: "#7777772c"),
        bubbleUser: SandColor(hex: "#5a5a5a"),
        dangerSubtle: SandColor(hex: "#ff263c2c"),
        fillWarning: SandColor(hex: "#ff9800"),
        fillAccent: SandColor(hex: "#1084fe"),
        fillDanger: SandColor(hex: "#ff263c"),
        scrim: SandColor(hex: "#141414b2"),
        blue: SandColor(hex: "#459ffe"),
        orange: SandColor(hex: "#ff8838"),
        green: SandColor(hex: "#38d591"),
        magenta: SandColor(hex: "#ff5eb1")
    )

    static let light = WorkPalette(
        editor: SandColor(hex: "#fcfcfc"),
        elevated: SandColor(hex: "#fcfcfc"),
        textPrimary: SandColor(hex: "#141414"),
        textSecondary: SandColor(hex: "#14141499"),
        textTertiary: SandColor(hex: "#14141466"),
        textWarning: SandColor(hex: "#c27400"),
        textDanger: SandColor(hex: "#c21d2e"),
        textOnColor: SandColor(hex: "#fcfcfc"),
        textOnPrimary: SandColor(hex: "#fcfcfc"),
        borderSubtle: SandColor(hex: "#1414140d"),
        fillPrimary: SandColor(hex: "#070707"),
        fillPrimaryHover: SandColor(hex: "#2f2f2f"),
        fillSecondary: SandColor(hex: "#77777717"),
        bubbleUser: SandColor(hex: "#070707"),
        dangerSubtle: SandColor(hex: "#ff263c17"),
        fillWarning: SandColor(hex: "#ff9800"),
        fillAccent: SandColor(hex: "#1084fe"),
        fillDanger: SandColor(hex: "#ff263c"),
        scrim: SandColor(hex: "#14141480"),
        blue: SandColor(hex: "#0c64c1"),
        orange: SandColor(hex: "#c24e00"),
        green: SandColor(hex: "#009957"),
        magenta: SandColor(hex: "#c22476")
    )

    static func resolve(_ theme: ThemePreference, systemDark: Bool) -> WorkPalette {
        switch theme {
        case .dark: .dark
        case .light: .light
        case .system: systemDark ? .dark : .light
        }
    }

    /// `--nuum-text-primary` at 9%. Mac calls the same mix `--work-edge` locally.
    var edge: SandColor { textPrimary.opacity(0.09) }
}

enum WorkMetrics {
    static let radiusLG = 10.0
    static let radius2XL = 16.0
    static let radius4XL = 18.0
    static let spacing1 = 4.0
    static let spacing2 = 8.0
    static let spacing3 = 12.0
    static let spacing4 = 16.0
    static let spacing6 = 24.0
    static let spacing11 = 44.0
    static let spacing14 = 56.0
    static let fontXS = 11.0
    static let fontSM = 12.0
    static let fontBase = 13.0
    static let fontLG = 14.0
    static let fontTitle = 22.0
    /// Mac `.sand-work-task-card p`. Not a type ramp step.
    static let cardBody = 10.0
    static let heightBase = 28.0
    static let heightLG = 32.0
    static let durationNormal = 0.15
    static let laneMin = 200.0
    static let laneGap = 18.0
    static let cardMinHeight = 112.0
    static let cardPadding = 15.0
    static let avatarMember = 34.0
    static let avatarFoot = 20.0
    static let avatarWorker = 24.0
    static let createMaxWidth = 520.0
    static let inspectorDefault = 250.0
    static let dot = 6.0
    static let pagerDot = 4.0
}
