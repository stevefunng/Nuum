import NuumContracts

public enum SandScheme: String, Equatable, Sendable {
    case light
    case dark
}

/// Resolved sand roles the shell paints. Values are the installed CSS variables, not system colors.
public enum SandToken: String, Equatable, Sendable {
    case bgChrome
    case bgEditor
    case bgElevated
    case bgInput
    case bgSecondary
    case fillSecondary
    case fillSelected
    case fillHover
    case fillPrimary
    case fillPrimaryHover
    case fillPrimaryDisabled
    case textOnPrimary
    case textOnColor
    case textPrimary
    case textSecondary
    case textTertiary
    case textDanger
    case borderSubtle
    case borderDefault
    case borderFocus
    case fillAccent
    case fillWarning
    case fillDanger
    case fillSupplementary4
    case scrim
    case shadowPopover
}

public struct SandTheme: Equatable, Sendable {
    public var scheme: SandScheme

    public init(scheme: SandScheme) {
        self.scheme = scheme
    }

    public static let dark = SandTheme(scheme: .dark)
    public static let light = SandTheme(scheme: .light)

    /// Settings not read yet resolve to dark, which is also `DEFAULT_SETTINGS.theme`.
    public static func resolve(preference: ThemePreference?, systemIsDark: Bool) -> SandTheme {
        switch preference {
        case .light:
            .light
        case .dark:
            .dark
        case .system:
            systemIsDark ? .dark : .light
        case nil:
            .dark
        }
    }

    public func color(_ token: SandToken) -> SandColor {
        let hex = (scheme == .dark ? SandPalette.dark : SandPalette.light)[token] ?? "#000000"
        return SandColor(css: hex)
    }
}

/// Effective colors after the runtime installer order. Names in comments are the CSS variables.
enum SandPalette {
    static let light: [SandToken: String] = [
        .bgChrome: "#f7f7f7", // --nuum-bg-chrome / --sand-bg-subtle
        .bgEditor: "#fcfcfc", // --nuum-bg-editor / --sand-bg-base
        .bgElevated: "#fcfcfc", // --nuum-bg-elevated
        .bgInput: "#fcfcfc", // --nuum-bg-input / --sand-fill-elevated
        .bgSecondary: "#7777772b", // --nuum-bg-secondary / --sand-fill-ghost-selected
        .fillSecondary: "#77777717", // --sand-fill-secondary
        .fillSelected: "#7777772b", // --sand-fill-ghost-selected
        .fillHover: "#77777717", // --sand-fill-ghost-hover
        .fillPrimary: "#070707", // --sand-fill-primary
        .fillPrimaryHover: "#2f2f2f",
        .fillPrimaryDisabled: "#14141426",
        .textOnPrimary: "#fcfcfc", // --sand-text-on-primary
        .textOnColor: "#fcfcfc",
        .textPrimary: "#141414", // --nuum-text-primary
        .textSecondary: "#14141499",
        .textTertiary: "#14141466",
        .textDanger: "#c21d2e", // --sand-text-danger
        .borderSubtle: "#1414140d",
        .borderDefault: "#14141426",
        .borderFocus: "#14141466",
        .fillAccent: "#1084fe",
        .fillWarning: "#ff9800",
        .fillDanger: "#ff263c",
        .fillSupplementary4: "#9159fe",
        .scrim: "#14141480", // --sand-bg-scrim
        .shadowPopover: "#0000001a",
    ]

    static let dark: [SandToken: String] = [
        .bgChrome: "#111111",
        .bgEditor: "#070707",
        .bgElevated: "#181818",
        .bgInput: "#2f2f2f",
        .bgSecondary: "#77777752",
        .fillSecondary: "#7777772c",
        .fillSelected: "#77777752",
        .fillHover: "#7777772c",
        .fillPrimary: "#fafafa",
        .fillPrimaryHover: "#d5d5d5",
        .fillPrimaryDisabled: "#fcfcfc26",
        .textOnPrimary: "#141414",
        .textOnColor: "#fcfcfc",
        .textPrimary: "#fcfcfc",
        .textSecondary: "#fcfcfc99",
        .textTertiary: "#fcfcfc66",
        .textDanger: "#ff5667",
        .borderSubtle: "#fcfcfc0d",
        .borderDefault: "#fcfcfc26",
        .borderFocus: "#fcfcfc66",
        .fillAccent: "#1084fe",
        .fillWarning: "#ff9800",
        .fillDanger: "#ff263c",
        .fillSupplementary4: "#9159fe",
        .scrim: "#141414b2",
        .shadowPopover: "#00000000",
    ]
}

enum BadgePaper {
    static let top = SandColor(css: "#fafbf9")
    static let mid = SandColor(css: "#e9ece9")
    static let bottom = SandColor(css: "#f7f8f5")
    static let line = SandColor(css: "#858d8910")
    static let ink = SandColor(css: "#303432")
    static let muted = SandColor(css: "#6c716e")
}

enum SandMetric {
    static let spacing2 = 8.0
    static let spacing3 = 12.0
    static let spacing4 = 16.0
    static let spacing6 = 24.0
    static let spacing8 = 32.0
    static let spacing11 = 44.0
    static let spacing14 = 56.0
    static let radiusSM = 4.0
    static let radiusLG = 10.0
    static let radiusXL = 14.0
    static let radius2XL = 16.0
    static let radius3XL = 18.0
    static let radiusFull = 9999.0
    /// Mac `.sand-nunu-badge` is 12px, between `--nuum-radius-lg` (10) and `--nuum-radius-xl` (14).
    static let radiusBadge = 12.0
    /// Create name field. Mac writes 9px for this input.
    static let radiusName = 9.0
    /// Work mark with no members. Mac writes 11px.
    static let radiusWorkMark = 11.0
    static let heightSM = 24.0
    static let heightBase = 28.0
    static let heightLG = 32.0
    static let fontXS = 11.0
    static let fontSM = 12.0
    static let fontBase = 13.0
    static let fontLG = 14.0
    static let lineXS = 14.0
    static let lineBase = 18.0
    static let lineLG = 22.0
    static let letterBase = -0.08
    static let durationFast = 0.1
    static let durationSlow = 0.2
    static let durationSlower = 0.3
    static let sidebarDefault = 236.0
    static let sidebarMin = 220.0
    static let sidebarMax = 400.0
    static let sidebarCollapsed = 88.0
    static let sidebarCollapseBelow = 208.0
    static let sidebarFraction = 0.42
    static let unboxTall = 280.0
    static let unboxShort = 192.0
    static let unboxShortBelow = 640.0
    static let unboxBody = 190.0
    static let unboxDuration = 1.5
    static let avatar = 34.0
    static let avatarPinned = 52.0
    static let avatarRail = 40.0
    static let statusDot = 8.0
    static let holdToDrag = 0.3
    static let nameMax = 80
    static let swatch = 28.0
    static let settingsWideBelow = 900.0
    static let settingsDialog = 860.0
    static let createDialog = 440.0
    static let profileMin = 300.0
    static let profileMax = 420.0
    static let profileFraction = 0.33
    static let newMenuMin = 208.0
    static let newMenuMax = 300.0
    static let newMenuInset = 24.0
}

enum ShellPhrase {
    static let sidebarSaveFailed = "Could not save sidebar changes. Please try again."
    static let copyFailed = "Could not copy Agent ID."
    static let identitySaveFailed = "Could not save. Please try again."
    static let nameEmpty = "Name cannot be empty."
    static let noAgents = "No agents yet"
    static let noMatch = "No matching agents"
    static let newAgent = "New Agent"
    static let newWork = "New Work"
    static let pinned = "Pinned Agents"
    static let dragHere = "Drag an Agent here"
    static let pinBand = "拖到此处置顶"
}
