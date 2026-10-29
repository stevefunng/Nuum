package com.nuum.feature.shell.motion

import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.platform.LocalContext
import kotlin.random.Random

/**
 * Unbox playback clock. Reduced motion must not call [awaitFrame].
 * Tests replace this local and count frames.
 */
internal fun interface UnboxFrameClock {
    suspend fun awaitFrame(onFrame: (frameTimeNanos: Long) -> Unit)
}

internal object DefaultUnboxFrameClock : UnboxFrameClock {
    override suspend fun awaitFrame(onFrame: (frameTimeNanos: Long) -> Unit) {
        withFrameNanos { nanos -> onFrame(nanos) }
    }
}

/** Null reads the system animator scale. Tests pass true or false. */
internal val LocalReducedMotion = compositionLocalOf<Boolean?> { null }

internal val LocalUnboxFrameClock = staticCompositionLocalOf<UnboxFrameClock> { DefaultUnboxFrameClock }

internal val LocalAvatarRandom = staticCompositionLocalOf<Random> { Random.Default }

@Composable
internal fun isReducedMotion(): Boolean {
    LocalReducedMotion.current?.let { return it }
    val resolver = LocalContext.current.contentResolver
    return try {
        Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    } catch (_: RuntimeException) {
        false
    }
}

internal const val UNBOX_DURATION_MS = 1_500L

/** `--nuum-easing-out-strong`: cubic-bezier(0.165, 0.84, 0.44, 1). */
internal fun easeOutStrong(fraction: Float): Float {
    val x = fraction.coerceIn(0f, 1f)
    var low = 0f
    var high = 1f
    var t = x
    repeat(10) {
        t = (low + high) / 2f
        val bx = cubic(t, 0.165f, 0.44f)
        if (bx < x) low = t else high = t
    }
    return cubic(t, 0.84f, 1f)
}

private fun cubic(t: Float, p1: Float, p2: Float): Float {
    val u = 1f - t
    return (3f * u * u * t * p1) + (3f * u * t * t * p2) + (t * t * t)
}
