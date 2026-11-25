import NuumProtocol

/// Keeps the scaffold edge `NuumContracts` → `NuumProtocol` live.
/// WP-01 fills `NuumProtocol`. Port types stay in this module until a scaffold change moves them.
public enum ContractModuleBoundary {
    public static let protocolModule = NuumProtocolModule.name
}
