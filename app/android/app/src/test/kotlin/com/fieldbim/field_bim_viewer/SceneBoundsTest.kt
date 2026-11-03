package com.fieldbim.field_bim_viewer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SceneBoundsTest {
    @Test
    fun fitSkipsProxyIds() {
        val wall = geom(1, 0f, 0f, 0f, 5f, 0.2f, 3f)
        val huge = geom(2, -5000f, -5000f, -5000f, 5000f, 5000f, 5000f)
        val box = SceneBounds.union(listOf(wall, huge), skip = setOf(2L))
        requireNotNull(box)
        assertEquals(0f, box[0], 0.001f)
        assertEquals(0f, box[1], 0.001f)
        assertEquals(0f, box[2], 0.001f)
        assertEquals(5f, box[3], 0.001f)
        assertEquals(0.2f, box[4], 0.001f)
        assertEquals(3f, box[5], 0.001f)
    }

    @Test
    fun emptyAfterSkip() {
        val huge = geom(2, -5000f, 0f, 0f, 5000f, 1f, 1f)
        assertNull(SceneBounds.union(listOf(huge), skip = setOf(2L)))
    }

    @Test
    fun clampKeepsCenterAndCapsSpan() {
        val huge = geom(2, -5000f, 0f, 0f, 5000f, 2f, 2f)
        val clamped = SceneBounds.clamp(huge, 10f)
        assertEquals(0f, (clamped.min[0] + clamped.max[0]) * 0.5f, 0.001f)
        assertEquals(1f, (clamped.min[1] + clamped.max[1]) * 0.5f, 0.001f)
        assertEquals(10f, clamped.max[0] - clamped.min[0], 0.001f)
        assertEquals(2f, clamped.max[1] - clamped.min[1], 0.001f)
        assertEquals(2f, clamped.max[2] - clamped.min[2], 0.001f)
    }

    private fun geom(id: Long, minX: Float, minY: Float, minZ: Float, maxX: Float, maxY: Float, maxZ: Float) =
        ElementGeom(
            id,
            floatArrayOf(minX, minY, minZ),
            floatArrayOf(maxX, maxY, maxZ),
            floatArrayOf(1f, 1f, 1f, 1f),
        )
}
