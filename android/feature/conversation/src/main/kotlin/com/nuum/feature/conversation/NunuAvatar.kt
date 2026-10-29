package com.nuum.feature.conversation

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

internal data class Pigment(val id: String, val value: Long, val dark: Long, val chat: Long)

private val Pigments = listOf(
    Pigment("cream", 0xFFF3E8D4, 0xFFC8AF8B, 0xFF806444),
    Pigment("green", 0xFFBAC8A8, 0xFF7E9270, 0xFF526C43),
    Pigment("orange", 0xFFF4C2A1, 0xFFCE8E6A, 0xFFAD5C30),
    Pigment("violet", 0xFFD5C6EB, 0xFFA28DBD, 0xFF79569D),
    Pigment("blue", 0xFFBEDCE7, 0xFF7CABBF, 0xFF39738C),
    Pigment("magenta", 0xFFEEC3CC, 0xFFBD899B, 0xFFA4526C),
    Pigment("honey", 0xFFEFDB9B, 0xFFC1A456, 0xFF8C6B22)
)

private val BlackPigment = Pigment("black", 0xFFA7AAA8, 0xFF707873, 0xFF3B4140)

private val Shapes = mapOf(
    "blob" to "M42 174C32 153 40 112 49 86C54 64 53 26 78 20C105 12 116 31 114 65C138 32 169 43 176 74C182 102 203 143 191 174C179 201 60 203 42 174Z",
    "circle" to "M34 158C29 131 44 106 54 84C56 53 64 32 84 31C108 28 119 45 118 64C141 40 165 54 173 79C191 100 207 132 199 158C190 207 47 208 34 158Z",
    "droplet" to "M43 169C38 144 55 108 64 78C65 48 64 18 85 15C110 10 122 34 116 65C139 41 158 53 164 80C173 111 198 147 188 174C174 203 58 204 43 169Z",
    "cloud" to "M29 167C23 142 36 113 46 99C43 65 62 43 86 49C101 51 109 65 109 77C133 48 159 55 170 83C195 92 211 130 202 162C191 200 45 204 29 167Z",
    "tablet" to "M32 171C26 150 31 119 38 96C39 61 54 36 80 38C105 37 112 57 111 74C137 43 168 54 178 83C190 109 203 148 195 174C184 194 46 198 32 171Z"
)

private val Materials = setOf("plush", "felt", "matte", "glass", "aurora")

internal fun pigmentFor(agentId: String, requested: String?): Pigment {
    if (requested == "black") return BlackPigment
    Pigments.firstOrNull { it.id == requested }?.let { return it }
    return Pigments[(fnv(agentId) % Pigments.size.toUInt()).toInt()]
}

internal fun shapeFor(agentId: String, requested: String?): String {
    if (requested != null && requested in Shapes) return requested
    val names = Shapes.keys.toList()
    return names[(fnv(agentId + "shape") % names.size.toUInt()).toInt()]
}

internal fun materialFor(requested: String?): String {
    return if (requested != null && requested in Materials) requested else "plush"
}

internal fun chatColor(agentId: String, requested: String?): Color = Color(pigmentFor(agentId, requested).chat)

private fun fnv(value: String): UInt {
    var result = 0x811C9DC5.toInt()
    for (char in value) {
        result = result xor char.code
        result *= 16777619
    }
    return result.toUInt()
}

@Composable
internal fun NunuAvatar(
    agentId: String,
    colorId: String?,
    shapeId: String?,
    materialId: String?,
    size: Dp,
    activity: String,
    modifier: Modifier = Modifier
) {
    val pigment = pigmentFor(agentId, colorId)
    val shape = shapeFor(agentId, shapeId)
    val material = materialFor(materialId)
    val path = remember(shape) { svgPath(Shapes.getValue(shape)) }
    val body = Color(pigment.value)
    val shade = Color(pigment.dark)
    Box(modifier.size(size)) {
        Canvas(Modifier.size(size)) {
            val scale = this.size.minDimension / 232f
            scale(scale, scale) {
                val fill = when (material) {
                    "glass", "aurora" -> glassPigment(body)
                    else -> body
                }
                drawPath(path, fill)
                if (material == "plush") {
                    drawPath(path, androidx.compose.ui.graphics.Brush.verticalGradient(listOf(body, shade)))
                }
                if (material == "felt") {
                    val dot = Color(0x14141414)
                    var y = 24f
                    while (y < 210f) {
                        var x = 24f
                        while (x < 210f) {
                            drawCircle(dot, radius = 1.2f, center = Offset(x, y))
                            x += 8f
                        }
                        y += 8f
                    }
                }
                if (material == "glass" || material == "aurora") {
                    drawOval(
                        color = Color.White.copy(alpha = 0.28f),
                        topLeft = Offset(70f, 36f),
                        size = Size(70f, 28f)
                    )
                }
                if (material == "aurora") {
                    drawPath(path, Color(0x339159FE))
                }
            }
        }
        val dot = when (activity) {
            "waiting" -> SandFillWarning
            "error" -> SandFillDanger
            "thinking", "working" -> SandFillAccent
            else -> Color.Transparent
        }
        if (dot != Color.Transparent) {
            Canvas(Modifier.size(size)) {
                val radius = 4.dp.toPx()
                drawCircle(dot, radius, Offset(this.size.width - radius, this.size.height - radius))
            }
        }
    }
}

private val SandFillWarning = Color(0xFFFF9800)
private val SandFillDanger = Color(0xFFFF263C)
private val SandFillAccent = Color(0xFF1084FE)

private fun glassPigment(color: Color): Color {
    if (color == Color(0xFFF3E8D4)) return Color.White
    return Color(
        red = 0.62f + 0.38f * color.red,
        green = 0.62f + 0.38f * color.green,
        blue = 0.62f + 0.38f * color.blue
    )
}

private fun svgPath(data: String): Path {
    val path = Path()
    val tokens = Regex("[MCZ]|-?\\d*\\.?\\d+").findAll(data).map { it.value }.toList()
    var index = 0
    while (index < tokens.size) {
        when (tokens[index]) {
            "M" -> {
                path.moveTo(tokens[index + 1].toFloat(), tokens[index + 2].toFloat())
                index += 3
            }
            "C" -> {
                path.cubicTo(
                    tokens[index + 1].toFloat(),
                    tokens[index + 2].toFloat(),
                    tokens[index + 3].toFloat(),
                    tokens[index + 4].toFloat(),
                    tokens[index + 5].toFloat(),
                    tokens[index + 6].toFloat()
                )
                index += 7
            }
            "Z" -> {
                path.close()
                index += 1
            }
            else -> index += 1
        }
    }
    return path
}

@Composable
internal fun SandIcon(
    name: String,
    modifier: Modifier = Modifier,
    tint: Color = Sand.textPrimary
) {
    Canvas(modifier) {
        val stroke = Stroke(width = 1.6.dp.toPx())
        when (name) {
            "plus" -> {
                drawLine(tint, Offset(size.width / 2f, size.height * 0.2f), Offset(size.width / 2f, size.height * 0.8f), strokeWidth = stroke.width)
                drawLine(tint, Offset(size.width * 0.2f, size.height / 2f), Offset(size.width * 0.8f, size.height / 2f), strokeWidth = stroke.width)
            }
            "arrow-up" -> {
                drawLine(tint, Offset(size.width / 2f, size.height * 0.82f), Offset(size.width / 2f, size.height * 0.22f), strokeWidth = stroke.width)
                drawLine(tint, Offset(size.width * 0.22f, size.height * 0.46f), Offset(size.width / 2f, size.height * 0.18f), strokeWidth = stroke.width)
                drawLine(tint, Offset(size.width * 0.78f, size.height * 0.46f), Offset(size.width / 2f, size.height * 0.18f), strokeWidth = stroke.width)
            }
            "stop" -> drawRoundRect(
                tint,
                topLeft = Offset(size.width * 0.28f, size.height * 0.28f),
                size = Size(size.width * 0.44f, size.height * 0.44f),
                cornerRadius = CornerRadius(1.dp.toPx())
            )
            "close" -> {
                drawLine(tint, Offset(size.width * 0.25f, size.height * 0.25f), Offset(size.width * 0.75f, size.height * 0.75f), strokeWidth = stroke.width)
                drawLine(tint, Offset(size.width * 0.75f, size.height * 0.25f), Offset(size.width * 0.25f, size.height * 0.75f), strokeWidth = stroke.width)
            }
            "chevron-right" -> {
                drawLine(tint, Offset(size.width * 0.35f, size.height * 0.22f), Offset(size.width * 0.68f, size.height * 0.5f), strokeWidth = stroke.width)
                drawLine(tint, Offset(size.width * 0.68f, size.height * 0.5f), Offset(size.width * 0.35f, size.height * 0.78f), strokeWidth = stroke.width)
            }
            else -> {
                drawLine(tint, Offset(size.width * 0.55f, size.height * 0.2f), Offset(size.width * 0.42f, size.height * 0.78f), strokeWidth = stroke.width)
                drawCircle(tint, radius = size.minDimension * 0.16f, center = Offset(size.width * 0.48f, size.height * 0.42f), style = Stroke(stroke.width))
            }
        }
    }
}
