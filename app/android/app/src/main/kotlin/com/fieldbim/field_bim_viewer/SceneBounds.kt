package com.fieldbim.field_bim_viewer

import kotlin.math.max

/**
 * Camera fit uses real element bounds only. Proxy stand-ins are skipped, and a
 * stand-in whose source box is far larger than the real scene is clamped so it
 * cannot cover the model.
 */
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
