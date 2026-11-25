/// WP-13 acceptance catalog. The simulator script lives in `ios/docs/acceptance/`.
/// This library does not boot a simulator, read Keychain, or write a secret file.
public enum NuumAcceptanceModule {
    public static let name = "NuumAcceptance"

    /// `main` when this checklist was written. WP-12 is that commit.
    public static let baselineCommit = "061033920588ca502d5874e3451f2e9c5878cc54"

    /// Stable Xcode named by the architecture. Not a beta, and not probed on Linux.
    public static let xcodeVersion = "27.2"
    public static let xcodeBuild = "27B52"
}
