package com.fieldbim.field_bim_viewer

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Smooths pinch and wheel dolly without changing how far a gesture travels
 * while the eye is clear of the model.
 *
 * Scroll units match Filament's orbit manipulator: negative zooms in, and
 * metres moved are `zoomSpeed * -scroll`. A command is eased out over
 * [tauSeconds] so one coarse touch sample does not jump the camera. The
 * integrated scroll still equals the command. Zooming in is scaled down as
 * the eye reaches the bounds, and one frame cannot cross a fixed fraction of
 * the remaining gap. Zooming out is not scaled.
 */
internal object Dolly {
    const val tauSeconds = 0.07f

    /** Pinch separation, in pixels, is multiplied by this before it becomes scroll. Filament uses 1/10. */
    const val pinchScrollPerPixel = 0.1f

    /** One wheel notch. The view used to pass this straight to `scroll`. */
    const val wheelScroll = 4f

    data class Step(val scroll: Float, val pending: Float)

    fun zoomInGain(gap: Float, radius: Float): Float {
        val span = max(radius * 0.5f, 0.35f)
        val t = (gap / span).coerceIn(0f, 1f)
        val smooth = t * t * (3f - 2f * t)
        return 0.07f + 0.93f * smooth
    }

    /** Distance from a point to an axis-aligned box. Zero when the point is inside. */
    fun gapToBox(
        x: Float,
        y: Float,
        z: Float,
        minX: Float,
        minY: Float,
        minZ: Float,
        maxX: Float,
        maxY: Float,
        maxZ: Float,
    ): Float {
        val dx = when {
            x < minX -> minX - x
            x > maxX -> x - maxX
            else -> 0f
        }
        val dy = when {
            y < minY -> minY - y
            y > maxY -> y - maxY
            else -> 0f
        }
        val dz = when {
            z < minZ -> minZ - z
            z > maxZ -> z - maxZ
            else -> 0f
        }
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    /**
     * [pending] is Filament scroll not yet consumed, including the samples
     * that arrived since the previous frame. Returns the scroll to apply now.
     */
    fun step(
        pending: Float,
        dt: Float,
        zoomSpeed: Float,
        gap: Float,
        radius: Float,
    ): Step {
        if (pending == 0f || zoomSpeed <= 1e-6f) return Step(0f, pending)
        val alpha = (1.0 - exp((-dt.coerceIn(0f, 0.1f) / tauSeconds).toDouble())).toFloat()
        val take = pending * alpha
        var scroll = take
        val metres = -take * zoomSpeed
        if (metres > 0f) {
            val gain = zoomInGain(gap, radius)
            var limited = metres * gain
            val cap = max(gap * 0.22f, radius * 0.004f)
            if (limited > cap) limited = cap
            scroll = -limited / zoomSpeed
        }
        var left = pending - take
        if (abs(left) < 1e-4f) left = 0f
        if (abs(scroll) < 1e-5f) scroll = 0f
        return Step(scroll, left)
    }
}
