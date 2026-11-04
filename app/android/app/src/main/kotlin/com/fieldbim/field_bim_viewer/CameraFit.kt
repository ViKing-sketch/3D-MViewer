package com.fieldbim.field_bim_viewer

import kotlin.math.abs
import kotlin.math.atan
import kotlin.math.max
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Places the orbit camera so a Y-up box stays inside the view.
 *
 * The mesh root is turned from package Z-up with `(x, y, z) -> (x, z, -y)`.
 * [pose] expects bounds that have already had that same turn applied, and
 * aims at their centre. Distance is the closest eye position at which every
 * corner of the box projects inside the 45° frustum, so a tall thin element
 * is not framed as if it were a sphere.
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
        val safeAspect = aspect.coerceIn(0.2, 5.0).toFloat()
        val halfV = Math.toRadians(fovDegrees * 0.5).toFloat()
        val halfH = atan(tan(halfV) * safeAspect)
        val tanV = tan(halfV)
        val tanH = tan(halfH).coerceAtLeast(0.05f)
        val dir = direction(preset)
        val len = sqrt(dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2])
        val dx = dir[0] / len
        val dy = dir[1] / len
        val dz = dir[2] / len
        val basis = cameraBasis(-dx, -dy, -dz)
        var needed = 0.5f
        val xs = floatArrayOf(-hx, hx)
        val ys = floatArrayOf(-hy, hy)
        val zs = floatArrayOf(-hz, hz)
        for (x in xs) {
            for (y in ys) {
                for (z in zs) {
                    val along = x * dx + y * dy + z * dz
                    val horiz = abs(x * basis[0] + y * basis[1] + z * basis[2])
                    val vert = abs(x * basis[3] + y * basis[4] + z * basis[5])
                    val corner = along + max(horiz / tanH, vert / tanV)
                    if (corner > needed) needed = corner
                }
            }
        }
        val distance = needed * 1.04f
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

    /** Right (xyz, y, z) then up (x, y, z) for a camera looking along [forward]. */
    private fun cameraBasis(fx: Float, fy: Float, fz: Float): FloatArray {
        var rx = -fz
        var rz = fx
        var rl = sqrt(rx * rx + rz * rz)
        if (rl <= 1e-4f) {
            rx = 1f
            rz = 0f
            rl = 1f
        }
        val r0 = rx / rl
        val r1 = 0f
        val r2 = rz / rl
        val u0 = r1 * fz - r2 * fy
        val u1 = r2 * fx - r0 * fz
        val u2 = r0 * fy - r1 * fx
        return floatArrayOf(r0, r1, r2, u0, u1, u2)
    }
}
