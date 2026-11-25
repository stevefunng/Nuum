import NuumContracts
import NuumProtocol

/// Scaffold marker. Product tools live beside this type.
public enum NuumToolsModule {
    public static let name = "NuumTools"
    public static let notImplemented = UnimplementedToolMessage.iosClient
    public static let protocolModule = NuumProtocolModule.name
}
