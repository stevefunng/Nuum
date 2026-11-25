import NuumContracts

/// Placeholder product. WP-02 replaces this file with `KeychainSecretStore`.
/// One generic-password item, this device only: service `nuum.secrets`, account `api-keys`.
public enum NuumSecurityModule {
    public static let name = "NuumSecurity"
    public static let service = KeychainSecretItem.service
    public static let account = KeychainSecretItem.account
}
