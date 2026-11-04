package com.fieldbim.field_bim_viewer

import kotlin.math.max

/**
 * Camera fit uses real element bounds only. Proxy stand-ins are skipped, and a
 * stand-in whose source box is far larger than the real scene is clamped so it
 * cannot cover the model.
 */
data class SceneFit(val bounds: FloatArray, val kept: Int, val total: Int)

object SceneBounds {
    fun union(geoms: Iterable<ElementGeom>, skip: Set<Long> = emptySet()): FloatArray? {
        var minX = Float.POSITIVE_INFINITY
        var minY = Float.POSITIVE_INFINITY
        var minZ = Float.POSITIVE_INFINITY
        var maxX = Float.NEGATIVE_INFINITY
        var maxY = Float.NEGATIVE_INFINITY
        var maxZ = Float.NEGATIVE_INFINITY
        var any = false
        for (geom in geoms) {
            if (geom.id in skip) continue
            any = true
            minX = minOf(minX, geom.min[0])
            minY = minOf(minY, geom.min[1])
            minZ = minOf(minZ, geom.min[2])
            maxX = maxOf(maxX, geom.max[0])
            maxY = maxOf(maxY, geom.max[1])
            maxZ = maxOf(maxZ, geom.max[2])
        }
        if (!any || minX == Float.POSITIVE_INFINITY) return null
        return floatArrayOf(minX, minY, minZ, maxX, maxY, maxZ)
    }

    /**
     * Union of the elements that sit in the core of the cloud.
     *
     * A few far centres (a site shell, a stray grid) stretch the plain union and
     * leave the building small and off to one side. Centres outside the padded
     * 5th–95th percentile on any axis are left out of the fit. A compact model
     * keeps every element.
     */
    fun fit(geoms: Iterable<ElementGeom>, skip: Set<Long> = emptySet()): SceneFit? {
        val list = ArrayList<ElementGeom>()
        for (geom in geoms) {
            if (geom.id in skip) continue
            if (geom.min.size < 3 || geom.max.size < 3) continue
            list.add(geom)
        }
        if (list.isEmpty()) return null
        var kept: List<ElementGeom> = list
        if (list.size >= 16) {
            for (axis in 0..2) {
                val next = keepCore(kept, axis)
                if (next.size >= 8 && next.size * 5 >= kept.size * 3) kept = next
            }
        }
        val bounds = union(kept) ?: return null
        return SceneFit(bounds, kept.size, list.size)
    }

    private fun keepCore(geoms: List<ElementGeom>, axis: Int): List<ElementGeom> {
        val order = geoms.sortedBy { center(it, axis) }
        val n = order.size
        val low = center(order[((n - 1) * 0.05f).toInt()], axis)
        val high = center(order[((n - 1) * 0.95f).toInt()], axis)
        val pad = max(1f, (high - low) * 0.2f)
        val minCenter = low - pad
        val maxCenter = high + pad
        return order.filter { center(it, axis) in minCenter..maxCenter }
    }

    private fun center(geom: ElementGeom, axis: Int): Float {
        return (geom.min[axis] + geom.max[axis]) * 0.5f
    }

    /** Axis-aligned union. Framing uses this so the larger of two boxes wins. */
    fun enclosing(a: FloatArray, b: FloatArray): FloatArray {
        return floatArrayOf(
            minOf(a[0], b[0]),
            minOf(a[1], b[1]),
            minOf(a[2], b[2]),
            maxOf(a[3], b[3]),
            maxOf(a[4], b[4]),
            maxOf(a[5], b[5]),
        )
    }

    /** Longest axis of [box], or 100 m when there is no real geometry yet. */
    fun span(box: FloatArray?): Float {
        if (box == null) return 100f
        val dx = box[3] - box[0]
        val dy = box[4] - box[1]
        val dz = box[5] - box[2]
        return max(1f, max(dx, max(dy, dz)))
    }

    /** Keep the center. No axis grows past [maxSpan]. */
    fun clamp(geom: ElementGeom, maxSpan: Float): ElementGeom {
        val limit = max(1f, maxSpan)
        val cx = (geom.min[0] + geom.max[0]) * 0.5f
        val cy = (geom.min[1] + geom.max[1]) * 0.5f
        val cz = (geom.min[2] + geom.max[2]) * 0.5f
        val hx = half(geom.min[0], geom.max[0], limit)
        val hy = half(geom.min[1], geom.max[1], limit)
        val hz = half(geom.min[2], geom.max[2], limit)
        return geom.copy(
            min = floatArrayOf(cx - hx, cy - hy, cz - hz),
            max = floatArrayOf(cx + hx, cy + hy, cz + hz),
        )
    }

    private fun half(min: Float, max: Float, limit: Float): Float {
        return ((max - min) * 0.5f).coerceIn(0.01f, limit * 0.5f)
    }
}
