package com.fieldbim.field_bim_viewer

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Section plane and optional box in Filament Y-up metres.
 *
 * A point is clipped when `dot(point, normal) > distance`. The same test is
 * in `materials/section.mat`. [rejects] is the picking check: it ignores a hit
 * only when the reconstructed point is clearly on the cut side and still near
 * the scene, so a bad unproject does not swallow a real pick.
 */
object SectionClip {
    class Clip(
        val nx: Float,
        val ny: Float,
        val nz: Float,
        val d: Float,
        val box: Boolean,
        val minX: Float,
        val minY: Float,
        val minZ: Float,
        val maxX: Float,
        val maxY: Float,
        val maxZ: Float,
    ) {
        fun matches(other: Clip): Boolean {
            return close(nx, other.nx) && close(ny, other.ny) && close(nz, other.nz) &&
                close(d, other.d) && box == other.box &&
                close(minX, other.minX) && close(minY, other.minY) && close(minZ, other.minZ) &&
                close(maxX, other.maxX) && close(maxY, other.maxY) && close(maxZ, other.maxZ)
        }
    }

    /** Slider 0 keeps [baseNear]. Slider 1 pushes the near plane to the orbit focus. */
    fun nearDistance(baseNear: Double, eyeDistance: Double, amount: Double): Double {
        val base = if (baseNear.isNaN()) 0.05 else baseNear.coerceAtLeast(0.01)
        val eye = if (eyeDistance.isNaN()) base else eyeDistance
        val t = if (amount.isNaN()) 0.0 else amount.coerceIn(0.0, 1.0)
        val span = (eye - base).coerceAtLeast(0.0)
        return base + t * span * 0.98
    }

    fun distance(
        ax: Double,
        ay: Double,
        az: Double,
        bx: Double,
        by: Double,
        bz: Double,
    ): Double {
        val dx = ax - bx
        val dy = ay - by
        val dz = az - bz
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    fun solve(
        axis: String,
        flip: Boolean,
        offset: Float,
        bounds: FloatArray,
        eyeX: Float,
        eyeY: Float,
        eyeZ: Float,
        targetX: Float,
        targetY: Float,
        targetZ: Float,
        boxEnabled: Boolean,
        boxInset: Float,
    ): Clip {
        val n = normal(axis, eyeX, eyeY, eyeZ, targetX, targetY, targetZ)
        val nx = if (flip) -n[0] else n[0]
        val ny = if (flip) -n[1] else n[1]
        val nz = if (flip) -n[2] else n[2]
        val minX = minOf(bounds[0], bounds[3])
        val minY = minOf(bounds[1], bounds[4])
        val minZ = minOf(bounds[2], bounds[5])
        val maxX = maxOf(bounds[0], bounds[3])
        val maxY = maxOf(bounds[1], bounds[4])
        val maxZ = maxOf(bounds[2], bounds[5])
        val cx = (minX + maxX) * 0.5f
        val cy = (minY + maxY) * 0.5f
        val cz = (minZ + maxZ) * 0.5f
        val hx = (maxX - minX) * 0.5f
        val hy = (maxY - minY) * 0.5f
        val hz = (maxZ - minZ) * 0.5f
        val reach = abs(nx) * hx + abs(ny) * hy + abs(nz) * hz
        val span = if (reach < 1e-3f) 1f else reach
        val along = offset.coerceIn(-1f, 1f) * span
        val px = cx + nx * along
        val py = cy + ny * along
        val pz = cz + nz * along
        val shrink = (1f - boxInset.coerceIn(0f, 1f)).coerceIn(0.02f, 1f)
        return Clip(
            nx = nx,
            ny = ny,
            nz = nz,
            d = nx * px + ny * py + nz * pz,
            box = boxEnabled,
            minX = cx - hx * shrink,
            minY = cy - hy * shrink,
            minZ = cz - hz * shrink,
            maxX = cx + hx * shrink,
            maxY = cy + hy * shrink,
            maxZ = cz + hz * shrink,
        )
    }

    /** Exact shader test: clipped when the point is strictly past the plane or outside the box. */
    fun clipped(x: Float, y: Float, z: Float, clip: Clip): Boolean {
        if (x * clip.nx + y * clip.ny + z * clip.nz > clip.d) return true
        if (!clip.box) return false
        return x < clip.minX || y < clip.minY || z < clip.minZ ||
            x > clip.maxX || y > clip.maxY || z > clip.maxZ
    }

    /**
     * Picking reject. A point far from the scene is treated as a failed unproject
     * and is not rejected. The kept side is widened by a few millimetres so a
     * hit on the cut face itself still selects.
     */
    fun rejects(x: Float, y: Float, z: Float, clip: Clip, bounds: FloatArray): Boolean {
        if (!plausible(x, y, z, bounds)) return false
        val eps = max(0.02f, spanOf(bounds) * 0.002f)
        val loosened = Clip(
            nx = clip.nx,
            ny = clip.ny,
            nz = clip.nz,
            d = clip.d + eps,
            box = clip.box,
            minX = clip.minX - eps,
            minY = clip.minY - eps,
            minZ = clip.minZ - eps,
            maxX = clip.maxX + eps,
            maxY = clip.maxY + eps,
            maxZ = clip.maxZ + eps,
        )
        return clipped(x, y, z, loosened)
    }

    /**
     * Filament pick unproject:
     * `clip = (frag.xy / viewport, frag.z) * 2 - 1`, then inverse projection and the camera model.
     * Returns world xyz, or null when the matrix cannot be inverted.
     */
    fun unproject(
        projection: DoubleArray,
        model: DoubleArray,
        width: Int,
        height: Int,
        fragX: Float,
        fragY: Float,
        fragZ: Float,
    ): FloatArray? {
        if (width < 1 || height < 1 || projection.size < 16 || model.size < 16) return null
        val inv = invert(projection) ?: return null
        val cx = fragX / width * 2.0 - 1.0
        val cy = fragY / height * 2.0 - 1.0
        val cz = fragZ * 2.0 - 1.0
        val view = mul(inv, doubleArrayOf(cx, cy, cz, 1.0))
        if (abs(view[3]) < 1e-8) return null
        val invW = 1.0 / view[3]
        val world = mul(model, doubleArrayOf(view[0] * invW, view[1] * invW, view[2] * invW, 1.0))
        return floatArrayOf(world[0].toFloat(), world[1].toFloat(), world[2].toFloat())
    }

    fun invert(matrix: DoubleArray): DoubleArray? {
        if (matrix.size < 16) return null
        val a = Array(4) { DoubleArray(8) }
        for (col in 0..3) {
            for (row in 0..3) {
                a[row][col] = matrix[col * 4 + row]
                a[row][col + 4] = if (row == col) 1.0 else 0.0
            }
        }
        for (col in 0..3) {
            var pivot = col
            var best = abs(a[col][col])
            for (row in col + 1..3) {
                val value = abs(a[row][col])
                if (value > best) {
                    best = value
                    pivot = row
                }
            }
            if (best < 1e-12) return null
            if (pivot != col) {
                val swap = a[col]
                a[col] = a[pivot]
                a[pivot] = swap
            }
            val div = a[col][col]
            for (j in col..7) a[col][j] /= div
            for (row in 0..3) {
                if (row == col) continue
                val factor = a[row][col]
                if (factor == 0.0) continue
                for (j in col..7) a[row][j] -= factor * a[col][j]
            }
        }
        val out = DoubleArray(16)
        for (col in 0..3) {
            for (row in 0..3) out[col * 4 + row] = a[row][col + 4]
        }
        return out
    }

    private fun normal(
        axis: String,
        eyeX: Float,
        eyeY: Float,
        eyeZ: Float,
        targetX: Float,
        targetY: Float,
        targetZ: Float,
    ): FloatArray {
        return when (axis) {
            "y" -> floatArrayOf(0f, 1f, 0f)
            "z" -> floatArrayOf(0f, 0f, 1f)
            "view" -> unit(eyeX - targetX, eyeY - targetY, eyeZ - targetZ)
            else -> floatArrayOf(1f, 0f, 0f)
        }
    }

    private fun unit(x: Float, y: Float, z: Float): FloatArray {
        val len = sqrt(x * x + y * y + z * z)
        if (len < 1e-6f) return floatArrayOf(0f, 0f, 1f)
        return floatArrayOf(x / len, y / len, z / len)
    }

    private fun plausible(x: Float, y: Float, z: Float, bounds: FloatArray): Boolean {
        if (bounds.size < 6) return false
        val cx = (bounds[0] + bounds[3]) * 0.5f
        val cy = (bounds[1] + bounds[4]) * 0.5f
        val cz = (bounds[2] + bounds[5]) * 0.5f
        val dx = x - cx
        val dy = y - cy
        val dz = z - cz
        val limit = spanOf(bounds) * 4f
        return dx * dx + dy * dy + dz * dz <= limit * limit
    }

    private fun spanOf(bounds: FloatArray): Float {
        if (bounds.size < 6) return 1f
        val dx = abs(bounds[3] - bounds[0])
        val dy = abs(bounds[4] - bounds[1])
        val dz = abs(bounds[5] - bounds[2])
        return max(1f, max(dx, max(dy, dz)))
    }

    private fun close(a: Float, b: Float): Boolean = abs(a - b) <= 1e-4f

    private fun mul(matrix: DoubleArray, vector: DoubleArray): DoubleArray {
        val out = DoubleArray(4)
        for (row in 0..3) {
            out[row] = matrix[row] * vector[0] +
                matrix[4 + row] * vector[1] +
                matrix[8 + row] * vector[2] +
                matrix[12 + row] * vector[3]
        }
        return out
    }
}
