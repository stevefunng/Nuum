import Foundation

/// Persisted avatar ids. SVG paths stay in the UI; this module only rolls and resolves ids.
/// Ported from `packages/ui/src/conversation/nunu-appearance.ts` because creation binds the roll.
public struct AgentAvatarColor: Sendable, Equatable {
    public var id: String
    public var chat: String
    public var value: String
    public var dark: String

    public init(id: String, chat: String, value: String, dark: String) {
        self.id = id
        self.chat = chat
        self.value = value
        self.dark = dark
    }
}

public let agentAvatarColors: [AgentAvatarColor] = [
    AgentAvatarColor(id: "cream", chat: "#806444", value: "#f3e8d4", dark: "#c8af8b"),
    AgentAvatarColor(id: "green", chat: "#526c43", value: "#bac8a8", dark: "#7e9270"),
    AgentAvatarColor(id: "orange", chat: "#ad5c30", value: "#f4c2a1", dark: "#ce8e6a"),
    AgentAvatarColor(id: "violet", chat: "#79569d", value: "#d5c6eb", dark: "#a28dbd"),
    AgentAvatarColor(id: "blue", chat: "#39738c", value: "#bedce7", dark: "#7cabbf"),
    AgentAvatarColor(id: "magenta", chat: "#a4526c", value: "#eec3cc", dark: "#bd899b"),
    AgentAvatarColor(id: "honey", chat: "#8c6b22", value: "#efdb9b", dark: "#c1a456"),
]

public let agentAvatarShapes = ["circle", "blob", "droplet", "cloud", "tablet"]
public let agentAvatarMaterials = ["plush", "felt", "matte", "glass"]
public let agentAvatarMaterialHidden = "aurora"

public struct AgentAvatarRoll: Sendable, Equatable {
    public var color: String
    public var shape: String
    public var material: String

    public init(color: String, shape: String, material: String) {
        self.color = color
        self.shape = shape
        self.material = material
    }
}

public let nunuEditions: [AgentAvatarRoll] = agentAvatarColors.flatMap { color in
    agentAvatarMaterials.flatMap { material in
        agentAvatarShapes.map { shape in AgentAvatarRoll(color: color.id, shape: shape, material: material) }
    }
}

/// Shape and material are bound at creation. The user only picks a color afterwards.
public func rollAgentAvatar<R: RandomNumberGenerator>(using random: inout R) -> AgentAvatarRoll {
    nunuEditions[Int.random(in: 0..<nunuEditions.count, using: &random)]
}

public func rollAgentAvatar() -> AgentAvatarRoll {
    var random = SystemRandomNumberGenerator()
    return rollAgentAvatar(using: &random)
}

public func resolveAgentAvatarColor(agentId: String, requested: String? = nil) -> AgentAvatarColor {
    if requested == "black" {
        return AgentAvatarColor(id: "black", chat: "#3b4140", value: "#a7aaa8", dark: "#707873")
    }
    if let match = agentAvatarColors.first(where: { $0.id == requested }) { return match }
    let index = Int(avatarHash(agentId) % UInt32(agentAvatarColors.count))
    return agentAvatarColors[index]
}

public func resolveAgentAvatarShape(agentId: String, requested: String? = nil) -> String {
    if let requested, agentAvatarShapes.contains(requested) { return requested }
    return agentAvatarShapes[Int(avatarHash(agentId + "shape") % 5)]
}

public func resolveAgentAvatarMaterial(requested: String? = nil) -> String {
    if let requested, agentAvatarMaterials.contains(requested) || requested == agentAvatarMaterialHidden {
        return requested
    }
    return "plush"
}

/// FNV-1a 32-bit, matching `Math.imul` + `>>> 0` in nunu-appearance.ts.
func avatarHash(_ value: String) -> UInt32 {
    var result: UInt32 = 2_166_136_261
    for unit in value.utf16 {
        result ^= UInt32(unit)
        result = result &* 16_777_619
    }
    return result
}
