package com.fieldbim.field_bim_viewer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
    fun enclosingKeepsWhicheverBoxIsLarger() {
        val proxy = floatArrayOf(0f, 0f, 0f, 2f, 2f, 2f)
        val mesh = floatArrayOf(-8f, 0f, -1f, 8f, 6f, 1f)
        val box = SceneBounds.enclosing(proxy, mesh)
        assertEquals(-8f, box[0], 0.001f)
        assertEquals(0f, box[1], 0.001f)
        assertEquals(-1f, box[2], 0.001f)
        assertEquals(8f, box[3], 0.001f)
        assertEquals(6f, box[4], 0.001f)
        assertEquals(2f, box[5], 0.001f)
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

    @Test
    fun fitDropsDistantOutliers() {
        val cluster = (0 until 30).map { i ->
            val x = i * 0.4f
            geom(i.toLong(), x, 0f, 0f, x + 1f, 2f, 1f)
        }
        val far = listOf(
            geom(100, 200f, 0f, 0f, 202f, 2f, 1f),
            geom(101, 210f, 0f, 0f, 212f, 2f, 1f),
        )
        val fit = SceneBounds.fit(cluster + far)
        requireNotNull(fit)
        assertTrue(fit.kept < fit.total)
        assertTrue(fit.bounds[3] < 20f)
        assertEquals(0f, fit.bounds[0], 0.01f)
    }

    @Test
    fun fitSkipsHiddenAndFramesTheIsolatedSet() {
        val wall = geom(1, 0f, 0f, 0f, 2f, 2f, 2f)
        val far = geom(2, 100f, 0f, 0f, 110f, 2f, 2f)
        val other = geom(3, -40f, 0f, 0f, -30f, 2f, 2f)
        val hidden = SceneBounds.skipForFrame(listOf(1L, 2L), emptySet(), setOf(2L), emptySet())
        assertEquals(setOf(2L), hidden)
        val hiddenFit = SceneBounds.fit(listOf(wall, far), hidden)
        requireNotNull(hiddenFit)
        assertEquals(0f, hiddenFit.bounds[0], 0.001f)
        assertEquals(2f, hiddenFit.bounds[3], 0.001f)

        val isolated = SceneBounds.skipForFrame(listOf(1L, 2L, 3L), setOf(9L), emptySet(), setOf(2L))
        assertEquals(setOf(9L, 1L, 3L), isolated)
        val isolatedFit = SceneBounds.fit(listOf(wall, far, other), isolated)
        requireNotNull(isolatedFit)
        assertEquals(100f, isolatedFit.bounds[0], 0.001f)
        assertEquals(110f, isolatedFit.bounds[3], 0.001f)
    }

    @Test
    fun fitKeepsAContinuousRun() {
        val run = (0 until 20).map { i ->
            val x = i * 5f
            geom(i.toLong(), x, 0f, 0f, x + 4f, 3f, 2f)
        }
        val fit = SceneBounds.fit(run)
        requireNotNull(fit)
        assertEquals(20, fit.kept)
        assertEquals(0f, fit.bounds[0], 0.01f)
        assertEquals(99f, fit.bounds[3], 0.01f)
    }

    private fun geom(id: Long, minX: Float, minY: Float, minZ: Float, maxX: Float, maxY: Float, maxZ: Float) =
        ElementGeom(
            id,
            floatArrayOf(minX, minY, minZ),
            floatArrayOf(maxX, maxY, maxZ),
            floatArrayOf(1f, 1f, 1f, 1f),
        )
}
