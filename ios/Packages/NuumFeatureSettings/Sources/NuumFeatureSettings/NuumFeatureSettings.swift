/// Settings and the in-app Proactive panel.
/// Views talk to `SettingsPort`, `SecretWriter`, and `ProactivePort` only.
public enum NuumFeatureSettingsModule {
    public static let name = "NuumFeatureSettings"
}

/// Shell-owned width. Compact is one column; regular is the two-column window.
/// This package does not decide which class the window is in.
public enum SettingsWidthClass: String, Sendable, Equatable {
    case compact
    case regular
}
