import Foundation
import NuumContracts
#if canImport(CoreGraphics)
import CoreGraphics
#else
typealias CGFloat = Double
#endif

/// CSS `#RRGGBB` or `#RRGGBBAA`. Alpha stays the last byte, matching sand tokens.
struct SandRGBA: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    var css: String

    init(css: String) {
        self.css = css
        let raw = css.hasPrefix("#") ? String(css.dropFirst()) : css
        let value = UInt64(raw, radix: 16) ?? 0
        if raw.count >= 8 {
            red = Double((value >> 24) & 0xff) / 255
            green = Double((value >> 16) & 0xff) / 255
            blue = Double((value >> 8) & 0xff) / 255
            alpha = Double(value & 0xff) / 255
        } else {
            red = Double((value >> 16) & 0xff) / 255
            green = Double((value >> 8) & 0xff) / 255
            blue = Double(value & 0xff) / 255
            alpha = 1
        }
    }
}

/// Sand / nuum tokens this surface actually paints. Names are the CSS variables.
struct SettingsPalette: Equatable, Sendable {
    var modeName: String
    var isDark: Bool
    /// `--nuum-bg-editor`
    var bgEditor: SandRGBA
    /// `--nuum-bg-elevated`
    var bgElevated: SandRGBA
    /// `--nuum-bg-input`
    var bgInput: SandRGBA
    /// `--nuum-text-primary`
    var textPrimary: SandRGBA
    /// `--nuum-text-secondary`
    var textSecondary: SandRGBA
    /// `--nuum-text-tertiary`
    var textTertiary: SandRGBA
    /// `--sand-text-on-primary`
    var textOnPrimary: SandRGBA
    /// `--sand-text-danger`
    var textDanger: SandRGBA
    /// `--sand-border-subtle`
    var borderSubtle: SandRGBA
    /// `--sand-border-default`
    var borderDefault: SandRGBA
    /// `--nuum-stroke-tertiary`
    var strokeTertiary: SandRGBA
    /// `--sand-fill-ghost-selected`
    var fillGhostSelected: SandRGBA
    /// `--sand-fill-ghost-hover`
    var fillGhostHover: SandRGBA
    /// `--sand-fill-control-track`
    var fillControlTrack: SandRGBA
    /// `--sand-bg-scrim`
    var scrim: SandRGBA

    static let light = SettingsPalette(
        modeName: "nuum-light",
        isDark: false,
        bgEditor: SandRGBA(css: "#fcfcfc"),
        bgElevated: SandRGBA(css: "#fcfcfc"),
        bgInput: SandRGBA(css: "#fcfcfc"),
        textPrimary: SandRGBA(css: "#141414"),
        textSecondary: SandRGBA(css: "#14141499"),
        textTertiary: SandRGBA(css: "#14141466"),
        textOnPrimary: SandRGBA(css: "#fcfcfc"),
        textDanger: SandRGBA(css: "#c21d2e"),
        borderSubtle: SandRGBA(css: "#1414140d"),
        borderDefault: SandRGBA(css: "#14141426"),
        strokeTertiary: SandRGBA(css: "#1414141a"),
        fillGhostSelected: SandRGBA(css: "#7777772b"),
        fillGhostHover: SandRGBA(css: "#77777717"),
        fillControlTrack: SandRGBA(css: "#1414141a"),
        scrim: SandRGBA(css: "#14141480")
    )

    static let dark = SettingsPalette(
        modeName: "nuum-dark",
        isDark: true,
        bgEditor: SandRGBA(css: "#070707"),
        bgElevated: SandRGBA(css: "#181818"),
        bgInput: SandRGBA(css: "#2f2f2f"),
        textPrimary: SandRGBA(css: "#fcfcfc"),
        textSecondary: SandRGBA(css: "#fcfcfc99"),
        textTertiary: SandRGBA(css: "#fcfcfc66"),
        textOnPrimary: SandRGBA(css: "#141414"),
        textDanger: SandRGBA(css: "#ff5667"),
        borderSubtle: SandRGBA(css: "#fcfcfc0d"),
        borderDefault: SandRGBA(css: "#fcfcfc26"),
        strokeTertiary: SandRGBA(css: "#fcfcfc1a"),
        fillGhostSelected: SandRGBA(css: "#77777752"),
        fillGhostHover: SandRGBA(css: "#7777772c"),
        fillControlTrack: SandRGBA(css: "#fcfcfc1a"),
        scrim: SandRGBA(css: "#141414b2")
    )
}

/// A nil preference is dark, matching the shell before `settings.get` returns.
/// `system` follows the platform appearance the shell passes in.
func settingsPalette(preference: ThemePreference?, systemIsDark: Bool) -> SettingsPalette {
    let dark = switch preference {
    case .light:
        false
    case .dark, nil:
        true
    case .system:
        systemIsDark
    }
    return dark ? .dark : .light
}

/// 1 CSS px = 1 pt. Effective radii follow `RADIUS_CSS`, not the earlier CORE_CSS values.
enum SandMetric {
    static let spacing2: CGFloat = 8
    static let spacing3: CGFloat = 12
    static let spacing4: CGFloat = 16
    static let spacing5: CGFloat = 20
    static let spacing6: CGFloat = 24
    static let spacing11: CGFloat = 44
    static let spacing12: CGFloat = 48
    static let fontXS: CGFloat = 11
    static let fontSM: CGFloat = 12
    static let fontBase: CGFloat = 13
    static let lineSM: CGFloat = 16
    static let lineBase: CGFloat = 18
    /// `--nuum-radius-base` effective value.
    static let radiusBase: CGFloat = 8
    /// `--nuum-radius-lg` effective value. Key fields and proactive buttons.
    static let radiusLG: CGFloat = 10
    /// `--nuum-radius-xl` effective value. Settings dialog.
    static let radiusXL: CGFloat = 14
    /// `--nuum-radius-2xl` effective value. Proactive status card.
    static let radius2XL: CGFloat = 16
    /// `--nuum-duration-slower`, in seconds.
    static let durationSlower: Double = 0.3
    /// `--nuum-letter-spacing-base`.
    static let trackingBase: CGFloat = -0.08
}

/// Dialogs and column changes use `--nuum-duration-slower` and `--nuum-easing-out-strong`.
/// `accessibilityReduceMotion` skips the transition.
enum SettingsMotion: Equatable, Sendable {
    case instant
    case slowerOutStrong
}

func settingsMotion(reduceMotion: Bool) -> SettingsMotion {
    reduceMotion ? .instant : .slowerOutStrong
}

/// Mac `.nuum-proactive-error`. Not a sand token.
let proactiveErrorCSS = "#b85850"

enum ProactiveDot: Equatable, Sendable {
    /// `--nuum-text-tertiary`
    case tertiary
    /// Mac paused dot, not in the sand table.
    case paused
    /// Mac ready / waiting dot, not in the sand table.
    case ready
    /// Mac error dot, not in the sand table.
    case attention

    var fixedCSS: String? {
        switch self {
        case .tertiary:
            nil
        case .paused:
            "#aa8a52"
        case .ready:
            "#80856b"
        case .attention:
            "#bd615a"
        }
    }
}
