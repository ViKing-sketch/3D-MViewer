package com.fieldbim.field_bim_viewer

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Places the orbit camera so a Y-up box stays inside the view.
 *
 * The mesh root is turned from package Z-up with `(x, y, z) -> (x, z, -y)`.
 * [pose] expects bounds that have already had that same turn applied. Distance
 * is solved by projecting the eight corners through the same view and
 * perspective matrices Filament uses (45° vertical, OpenGL NDC), so a tall
 * thin element is not framed as a sphere and a wide site is not left with its
 * corners in the middle of the picture.
 */
object CameraFit {
    const val fovDegrees = 45.0
    private const val fill = 0.96

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
        val cx = (bounds[0] + bounds[3]) * 0.5
        val cy = (bounds[1] + bounds[4]) * 0.5
        val cz = (bounds[2] + bounds[5]) * 0.5
        val hx = abs(bounds[3] - bounds[0]) * 0.5
        val hy = abs(bounds[4] - bounds[1]) * 0.5
        val hz = abs(bounds[5] - bounds[2]) * 0.5
        val radius = max(0.5, sqrt(hx * hx + hy * hy + hz * hz))
        val dir = direction(preset)
        val len = sqrt(dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2]).toDouble()
        val dx = dir[0] / len
        val dy = dir[1] / len
        val dz = dir[2] / len
        val safeAspect = aspect.coerceIn(0.2, 5.0)
        val projection = perspective(safeAspect)
        var hi = max(radius * 8.0, 1.0)
        repeat(10) {
            if (projected(bounds, cx, cy, cz, dx, dy, dz, hi, projection) <= fill) return@repeat
            hi *= 1.7
        }
        var lo = 0.25
        repeat(22) {
            val mid = (lo + hi) * 0.5
            if (projected(bounds, cx, cy, cz, dx, dy, dz, mid, projection) > fill) lo = mid else hi = mid
        }
        return Pose(
            targetX = cx.toFloat(),
            targetY = cy.toFloat(),
            targetZ = cz.toFloat(),
            eyeX = (cx + dx * hi).toFloat(),
            eyeY = (cy + dy * hi).toFloat(),
            eyeZ = (cz + dz * hi).toFloat(),
            distance = hi.toFloat(),
            radius = radius.toFloat(),
        )
    }

    /** Largest absolute NDC of the eight corners. Behind the eye counts as outside. */
    fun maxAbsNdc(bounds: FloatArray, pose: Pose, aspect: Double): Float {
        val projection = perspective(aspect.coerceIn(0.2, 5.0))
        val view = viewMatrix(
            pose.eyeX.toDouble(),
            pose.eyeY.toDouble(),
            pose.eyeZ.toDouble(),
            pose.targetX.toDouble(),
            pose.targetY.toDouble(),
            pose.targetZ.toDouble(),
        )
        return maxAbsNdc(view, projection, bounds)
    }

    /**
     * Project [bounds] with column-major [view] and [projection].
     * A corner behind the camera returns a value larger than 1.
     */
    fun maxAbsNdc(view: DoubleArray, projection: DoubleArray, bounds: FloatArray): Float {
        val clip = DoubleArray(16)
        multiply(projection, view, clip)
        var peak = 0.0
        val xs = doubleArrayOf(bounds[0].toDouble(), bounds[3].toDouble())
        val ys = doubleArrayOf(bounds[1].toDouble(), bounds[4].toDouble())
        val zs = doubleArrayOf(bounds[2].toDouble(), bounds[5].toDouble())
        for (x in xs) {
            for (y in ys) {
                for (z in zs) {
                    val point = transformPoint(clip, x, y, z)
                    if (point[3] <= 1e-4) return 8f
                    val ndcX = abs(point[0] / point[3])
                    val ndcY = abs(point[1] / point[3])
                    if (ndcX > peak) peak = ndcX
                    if (ndcY > peak) peak = ndcY
                }
            }
        }
        return peak.toFloat()
    }

    /** Every corner of [bounds] lands inside the frustum at [aspect]. */
    fun frames(bounds: FloatArray, preset: String, aspect: Double): Boolean {
        val pose = pose(bounds, preset, aspect)
        return maxAbsNdc(bounds, pose, aspect) <= 1.02f
    }

    private fun projected(
        bounds: FloatArray,
        cx: Double,
        cy: Double,
        cz: Double,
        dx: Double,
        dy: Double,
        dz: Double,
        distance: Double,
        projection: DoubleArray,
    ): Float {
        val view = viewMatrix(cx + dx * distance, cy + dy * distance, cz + dz * distance, cx, cy, cz)
        return maxAbsNdc(view, projection, bounds)
    }

    /** Filament vertical perspective, OpenGL clip, column-major. XY NDC does not depend on the planes. */
    fun perspective(aspect: Double): DoubleArray {
        val tanV = tan(Math.toRadians(fovDegrees * 0.5))
        val m00 = 1.0 / (tanV * aspect)
        val m11 = 1.0 / tanV
        val near = 0.1
        val far = 10000.0
        val m22 = (far + near) / (near - far)
        val m32 = (2.0 * far * near) / (near - far)
        return doubleArrayOf(
            m00, 0.0, 0.0, 0.0,
            0.0, m11, 0.0, 0.0,
            0.0, 0.0, m22, -1.0,
            0.0, 0.0, m32, 0.0,
        )
    }

    /** Column-major look-at. The camera looks from [eye] toward the target, with world up +Y. */
    fun viewMatrix(
        eyeX: Double,
        eyeY: Double,
        eyeZ: Double,
        targetX: Double,
        targetY: Double,
        targetZ: Double,
    ): DoubleArray {
        var fx = targetX - eyeX
        var fy = targetY - eyeY
        var fz = targetZ - eyeZ
        val fl = sqrt(fx * fx + fy * fy + fz * fz).coerceAtLeast(1e-8)
        fx /= fl
        fy /= fl
        fz /= fl
        var rx = -fz
        var ry = 0.0
        var rz = fx
        var rl = sqrt(rx * rx + rz * rz)
        if (rl < 1e-6) {
            rx = 1.0
            ry = 0.0
            rz = 0.0
            rl = 1.0
        }
        rx /= rl
        ry /= rl
        rz /= rl
        val ux = ry * fz - rz * fy
        val uy = rz * fx - rx * fz
        val uz = rx * fy - ry * fx
        return doubleArrayOf(
            rx, ux, -fx, 0.0,
            ry, uy, -fy, 0.0,
            rz, uz, -fz, 0.0,
            -(rx * eyeX + ry * eyeY + rz * eyeZ),
            -(ux * eyeX + uy * eyeY + uz * eyeZ),
            fx * eyeX + fy * eyeY + fz * eyeZ,
            1.0,
        )
    }

    private fun multiply(a: DoubleArray, b: DoubleArray, out: DoubleArray) {
        for (col in 0..3) {
            for (row in 0..3) {
                var sum = 0.0
                for (k in 0..3) sum += a[k * 4 + row] * b[col * 4 + k]
                out[col * 4 + row] = sum
            }
        }
    }

    private fun transformPoint(matrix: DoubleArray, x: Double, y: Double, z: Double): DoubleArray {
        val v = doubleArrayOf(x, y, z, 1.0)
        val out = DoubleArray(4)
        for (row in 0..3) {
            var sum = 0.0
            for (col in 0..3) sum += matrix[col * 4 + row] * v[col]
            out[row] = sum
        }
        return out
    }
}
