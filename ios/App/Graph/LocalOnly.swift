import NuumContracts

/// This client has no account. Transcript records do not gain a user field.
struct LocalOnly: IdentityContext {
    var userId: String? { nil }
}
