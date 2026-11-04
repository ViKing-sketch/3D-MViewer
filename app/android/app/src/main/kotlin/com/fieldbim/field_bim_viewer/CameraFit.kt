package com.fieldbim.field_bim_viewer

import kotlin.math.abs
import kotlin.math.atan
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Places the orbit camera so a Y-up box stays inside the view.
 *
 * The mesh root is turned from package Z-up with `(x, y, z) -> (x, z, -y)`.
 * [pose] expects bounds that have already had that same turn applied, and
 * aims at their centre. Distance uses the bounding sphere and the narrower
 * of the vertical and horizontal fields of view, so a flat site still fits
 * on a portrait phone.
 */
object CameraFit {
    const val fovDegrees = 45.0

    data class Pose(
        val targetX: Float,
        val targetY: Float,
        val targetZ: Float,
        val eyeX: Float,
        val eyeY: Float,
        val eyeZ: Float,
        val distance: Float,
        val radius: Float,
    )

    fun direction(preset: String): FloatArray {
        return when (preset) {
            "front" -> floatArrayOf(0f, 0f, 1f)
            "back" -> floatArrayOf(0f, 0f, -1f)
            "left" -> floatArrayOf(-1f, 0f, 0f)
            "right" -> floatArrayOf(1f, 0f, 0f)
            "top" -> floatArrayOf(0f, 1f, 0.04f)
            "bottom" -> floatArrayOf(0f, -1f, 0.04f)
            else -> floatArrayOf(0.75f, 0.55f, 0.85f)
        }
    }

    fun pose(bounds: FloatArray, preset: String, aspect: Double): Pose {
        val cx = (bounds[0] + bounds[3]) * 0.5f
        val cy = (bounds[1] + bounds[4]) * 0.5f
        val cz = (bounds[2] + bounds[5]) * 0.5f
        val hx = abs(bounds[3] - bounds[0]) * 0.5f
        val hy = abs(bounds[4] - bounds[1]) * 0.5f
        val hz = abs(bounds[5] - bounds[2]) * 0.5f
        val radius = max(0.5f, sqrt(hx * hx + hy * hy + hz * hz))
        val safeAspect = aspect.coerceIn(0.2, 5.0)
        val halfV = Math.toRadians(fovDegrees * 0.5)
        val halfH = atan(tan(halfV) * safeAspect)
        val limit = sin(minOf(halfV, halfH)).coerceAtLeast(0.05)
        val distance = (radius / limit * 1.08).toFloat()
        val dir = direction(preset)
        val len = sqrt(dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2])
        return Pose(
            targetX = cx,
            targetY = cy,
            targetZ = cz,
            eyeX = cx + dir[0] / len * distance,
            eyeY = cy + dir[1] / len * distance,
            eyeZ = cz + dir[2] / len * distance,
            distance = distance,
            radius = radius,
        )
    }

    /** Every corner of [bounds] lands inside the frustum at [aspect]. */
    fun frames(bounds: FloatArray, preset: String, aspect: Double): Boolean {
        val pose = pose(bounds, preset, aspect)
        val xs = floatArrayOf(bounds[0], bounds[3])
        val ys = floatArrayOf(bounds[1], bounds[4])
        val zs = floatArrayOf(bounds[2], bounds[5])
        for (x in xs) {
            for (y in ys) {
                for (z in zs) {
                    if (!inside(pose, x, y, z, aspect)) return false
                }
            }
        }
        return true
    }

    private fun inside(pose: Pose, x: Float, y: Float, z: Float, aspect: Double): Boolean {
        val fx = pose.targetX - pose.eyeX
        val fy = pose.targetY - pose.eyeY
        val fz = pose.targetZ - pose.eyeZ
        val fl = sqrt(fx * fx + fy * fy + fz * fz)
        if (fl <= 1e-4f) return false
        val f0 = fx / fl
        val f1 = fy / fl
        val f2 = fz / fl
        val rx = -f2
        val ry = 0f
        val rz = f0
        val rl = sqrt(rx * rx + rz * rz)
        if (rl <= 1e-4f) return false
        val r0 = rx / rl
        val r1 = ry
        val r2 = rz / rl
        val u0 = r1 * f2 - r2 * f1
        val u1 = r2 * f0 - r0 * f2
        val u2 = r0 * f1 - r1 * f0
        val vx = x - pose.eyeX
        val vy = y - pose.eyeY
        val vz = z - pose.eyeZ
        val depth = vx * f0 + vy * f1 + vz * f2
        if (depth <= 0.05f) return false
        val safeAspect = aspect.coerceIn(0.2, 5.0)
        val halfV = Math.toRadians(fovDegrees * 0.5)
        val tanV = tan(halfV)
        val ndcX = ((vx * r0 + vy * r1 + vz * r2) / depth) / (tanV * safeAspect)
        val ndcY = ((vx * u0 + vy * u1 + vz * u2) / depth) / tanV
        return abs(ndcX) <= 1.02 && abs(ndcY) <= 1.02
    }
}
