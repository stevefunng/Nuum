package com.nuum.protocol

import kotlin.random.Random

/**
 * Persisted avatar ids. SVG paths stay in the UI; this module only rolls and resolves ids.
 * Ported from `packages/ui/src/conversation/nunu-appearance.ts` because creation binds the roll.
 */
data class AgentAvatarColor(val id: String, val chat: String, val value: String, val dark: String)

val AGENT_AVATAR_COLORS: List<AgentAvatarColor> = listOf(
    AgentAvatarColor("cream", "#806444", "#f3e8d4", "#c8af8b"),
    AgentAvatarColor("green", "#526c43", "#bac8a8", "#7e9270"),
    AgentAvatarColor("orange", "#ad5c30", "#f4c2a1", "#ce8e6a"),
    AgentAvatarColor("violet", "#79569d", "#d5c6eb", "#a28dbd"),
    AgentAvatarColor("blue", "#39738c", "#bedce7", "#7cabbf"),
    AgentAvatarColor("magenta", "#a4526c", "#eec3cc", "#bd899b"),
    AgentAvatarColor("honey", "#8c6b22", "#efdb9b", "#c1a456")
)

val AGENT_AVATAR_SHAPES: List<String> = listOf("circle", "blob", "droplet", "cloud", "tablet")
val AGENT_AVATAR_MATERIALS: List<String> = listOf("plush", "felt", "matte", "glass")
const val AGENT_AVATAR_MATERIAL_HIDDEN = "aurora"

data class AgentAvatarRoll(val color: String, val shape: String, val material: String)

val NUNU_EDITIONS: List<AgentAvatarRoll> = AGENT_AVATAR_COLORS.flatMap { color ->
    AGENT_AVATAR_MATERIALS.flatMap { material ->
        AGENT_AVATAR_SHAPES.map { shape -> AgentAvatarRoll(color.id, shape, material) }
    }
}

/** Shape and material are bound at creation. The user only picks a color afterwards. */
fun rollAgentAvatar(random: Random = Random.Default): AgentAvatarRoll =
    NUNU_EDITIONS[random.nextInt(NUNU_EDITIONS.size)]

fun resolveAgentAvatarColor(agentId: String, requested: String? = null): AgentAvatarColor {
    if (requested == "black") return AgentAvatarColor("black", "#3b4140", "#a7aaa8", "#707873")
    return AGENT_AVATAR_COLORS.find { it.id == requested }
        ?: AGENT_AVATAR_COLORS[(avatarHash(agentId).toUInt() % AGENT_AVATAR_COLORS.size.toUInt()).toInt()]
}

fun resolveAgentAvatarShape(agentId: String, requested: String? = null): String {
    if (requested != null && requested in AGENT_AVATAR_SHAPES) return requested
    return AGENT_AVATAR_SHAPES[(avatarHash(agentId + "shape").toUInt() % 5u).toInt()]
}

fun resolveAgentAvatarMaterial(requested: String? = null): String {
    if (requested != null && (requested in AGENT_AVATAR_MATERIALS || requested == AGENT_AVATAR_MATERIAL_HIDDEN)) {
        return requested
    }
    return "plush"
}

/** FNV-1a 32-bit, matching `Math.imul` + `>>> 0` in nunu-appearance.ts. */
internal fun avatarHash(value: String): Int {
    var result = 2166136261L.toInt()
    for (ch in value) result = imul(result xor ch.code, 16777619)
    return result
}

private fun imul(a: Int, b: Int): Int = (a.toLong() * b.toLong()).toInt()
