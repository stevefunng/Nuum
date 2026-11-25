import NuumProtocol

/// Pigment resolved from persisted avatar ids. Hex strings stay untyped so the
/// conversation files can keep using `NuumContracts` without a name clash.
struct ResolvedNunuAppearance: Equatable, Sendable {
    var chatHex: String
    var valueHex: String
    var shape: String
    var material: String
}

func resolveNunuAppearance(
    agentId: String,
    color: String?,
    shape: String?,
    material: String?
) -> ResolvedNunuAppearance {
    let pigment = resolveAgentAvatarColor(agentId: agentId, requested: color)
    return ResolvedNunuAppearance(
        chatHex: pigment.chat,
        valueHex: pigment.value,
        shape: resolveAgentAvatarShape(agentId: agentId, requested: shape),
        material: resolveAgentAvatarMaterial(requested: material)
    )
}

/// Mirrors `NuumProtocol.supportsImageInput` using raw provider and model ids.
func modelSupportsImageInput(providerRaw: String, model: String) -> Bool {
    guard let provider = ProviderId(rawValue: providerRaw) else { return false }
    return supportsImageInput(ModelRef(provider: provider, model: model))
}
