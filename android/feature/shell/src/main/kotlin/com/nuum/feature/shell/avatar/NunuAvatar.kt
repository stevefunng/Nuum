package com.nuum.feature.shell.avatar

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.Dp
import com.nuum.feature.shell.theme.LocalSand
import com.nuum.feature.shell.theme.css
import com.nuum.protocol.resolveAgentAvatarColor
import com.nuum.protocol.resolveAgentAvatarMaterial
import com.nuum.protocol.resolveAgentAvatarShape

/** SVG `d` from `nunu-appearance.ts`. Avatar viewBox is `18 8 196 196`; full body is `0 0 232 232`. */
internal val NUNU_SHAPES: Map<String, String> = mapOf(
    "blob" to "M42 174C32 153 40 112 49 86C54 64 53 26 78 20C105 12 116 31 114 65C138 32 169 43 176 74C182 102 203 143 191 174C179 201 60 203 42 174Z",
    "circle" to "M34 158C29 131 44 106 54 84C56 53 64 32 84 31C108 28 119 45 118 64C141 40 165 54 173 79C191 100 207 132 199 158C190 207 47 208 34 158Z",
    "droplet" to "M43 169C38 144 55 108 64 78C65 48 64 18 85 15C110 10 122 34 116 65C139 41 158 53 164 80C173 111 198 147 188 174C174 203 58 204 43 169Z",
    "cloud" to "M29 167C23 142 36 113 46 99C43 65 62 43 86 49C101 51 109 65 109 77C133 48 159 55 170 83C195 92 211 130 202 162C191 200 45 204 29 167Z",
    "tablet" to "M32 171C26 150 31 119 38 96C39 61 54 36 80 38C105 37 112 57 111 74C137 43 168 54 178 83C190 109 203 148 195 174C184 194 46 198 32 171Z"
)

internal val COLOR_LABEL_KEYS: Map<String, String> = mapOf(
    "cream" to "Cream",
    "green" to "Sage",
    "orange" to "Peach",
    "violet" to "Lilac",
    "blue" to "Mist blue",
    "magenta" to "Rose",
    "honey" to "Honey",
    "black" to "black"
)

internal data class ResolvedAvatar(
    val colorId: String,
    val shape: String,
    val material: String,
    val value: Color,
    val dark: Color,
    val chat: Color
)

internal fun resolveAvatar(agentId: String, color: String?, shape: String?, material: String?): ResolvedAvatar {
    val pigment = resolveAgentAvatarColor(agentId, color)
    return ResolvedAvatar(
        colorId = pigment.id,
        shape = resolveAgentAvatarShape(agentId, shape),
        material = resolveAgentAvatarMaterial(material),
        value = css(pigment.value),
        dark = css(pigment.dark),
        chat = css(pigment.chat)
    )
}

@Composable
internal fun NunuAvatar(
    agentId: String,
    color: String?,
    shape: String?,
    material: String?,
    size: Dp,
    fullBody: Boolean,
    modifier: Modifier = Modifier
) {
    val avatar = resolveAvatar(agentId, color, shape, material)
    val path = remember(avatar.shape) {
        PathParser().parsePathString(NUNU_SHAPES.getValue(avatar.shape)).toPath()
    }
    val sand = LocalSand.current
    Canvas(modifier.size(size)) {
        val box = if (fullBody) 232f else 196f
        val originX = if (fullBody) 0f else 18f
        val originY = if (fullBody) 0f else 8f
        val scale = this.size.minDimension / box
        withTransform({
            scale(scale, scale, pivot = Offset.Zero)
            translate(-originX, -originY)
        }) {
            drawBody(path, avatar, sand.textPrimary, sand.textOnColor, sand.supplementary4)
        }
    }
}

private fun DrawScope.drawBody(
    path: Path,
    avatar: ResolvedAvatar,
    textPrimary: Color,
    highlight: Color,
    aurora: Color
) {
    val fill = pigment(avatar.value, avatar.material)
    when (avatar.material) {
        "plush" -> drawPath(
            path,
            brush = Brush.verticalGradient(listOf(fill, avatar.dark))
        )
        "glass", "aurora" -> {
            drawPath(path, fill)
            drawPath(
                path,
                brush = Brush.radialGradient(
                    colors = listOf(highlight.copy(alpha = 0.55f), highlight.copy(alpha = 0f)),
                    center = Offset(90f, 70f),
                    radius = 80f
                )
            )
            if (avatar.material == "aurora") {
                drawPath(
                    path,
                    brush = Brush.linearGradient(
                        colors = listOf(aurora.copy(alpha = 0.28f), Color.Transparent)
                    )
                )
            }
        }
        else -> drawPath(path, fill)
    }
    if (avatar.material == "felt") {
        val dot = textPrimary.copy(alpha = 0.08f)
        var y = 30f
        while (y < 200f) {
            var x = 30f
            while (x < 200f) {
                drawCircle(dot, radius = 1.4f, center = Offset(x, y))
                x += 9f
            }
            y += 9f
        }
    }
}

/** Glass and aurora keep 0.38 of the distance from white. Cream glass stays white, matching `resolveNunuPigment`. */
internal fun pigment(value: Color, material: String): Color {
    val glass = material == "glass" || material == "aurora"
    if (glass && value.red > 0.94f && value.green > 0.90f && value.blue > 0.80f) return Color.White
    val strength = if (glass) 0.38f else 1f
    return Color(
        red = 1f + (value.red - 1f) * strength,
        green = 1f + (value.green - 1f) * strength,
        blue = 1f + (value.blue - 1f) * strength,
        alpha = 1f
    )
}
