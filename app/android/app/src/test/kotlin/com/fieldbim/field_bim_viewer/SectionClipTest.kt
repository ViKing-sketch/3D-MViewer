package com.fieldbim.field_bim_viewer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SectionClipTest {
    private val bounds = floatArrayOf(0f, 0f, 0f, 10f, 4f, 2f)

    @Test
    fun planeThroughTheCentreKeepsTheNegativeSide() {
        val clip = solve(axis = "x", flip = false, offset = 0f)
        assertEquals(1f, clip.nx, 1e-4f)
        assertEquals(5f, clip.d, 1e-3f)
        assertFalse(SectionClip.clipped(4f, 2f, 1f, clip))
        assertFalse(SectionClip.clipped(5f, 2f, 1f, clip))
        assertTrue(SectionClip.clipped(6f, 2f, 1f, clip))
    }

    @Test
    fun flipSwapsTheKeptSideWithoutMovingTheCentre() {
        val clip = solve(axis = "x", flip = true, offset = 0f)
        assertEquals(-1f, clip.nx, 1e-4f)
        assertEquals(-5f, clip.d, 1e-3f)
        assertTrue(SectionClip.clipped(4f, 2f, 1f, clip))
        assertFalse(SectionClip.clipped(5f, 2f, 1f, clip))
        assertFalse(SectionClip.clipped(6f, 2f, 1f, clip))
    }

    @Test
    fun flipKeepsAnOffsetPlaneAndOnlySwapsTheSide() {
        val half = 20f
        val centre = 29.39f
        val at = 13.56f
        val bounds = floatArrayOf(centre - half, 0f, -10f, centre + half, 8f, 10f)
        val offset = (at - centre) / half
        val kept = SectionClip.solve(
            axis = "x",
            flip = false,
            offset = offset,
            bounds = bounds,
            eyeX = 0f,
            eyeY = 4f,
            eyeZ = 30f,
            targetX = centre,
            targetY = 4f,
            targetZ = 0f,
            boxEnabled = false,
            boxInset = 0f,
        )
        val flipped = SectionClip.solve(
            axis = "x",
            flip = true,
            offset = offset,
            bounds = bounds,
            eyeX = 0f,
            eyeY = 4f,
            eyeZ = 30f,
            targetX = centre,
            targetY = 4f,
            targetZ = 0f,
            boxEnabled = false,
            boxInset = 0f,
        )
        assertEquals(1f, kept.nx, 1e-4f)
        assertEquals(at, kept.d, 0.02f)
        assertEquals(-1f, flipped.nx, 1e-4f)
        assertEquals(-at, flipped.d, 0.02f)
        assertEquals(kept.metres, flipped.metres, 0.02f)
        assertFalse(SectionClip.clipped(10f, 2f, 0f, kept))
        assertTrue(SectionClip.clipped(10f, 2f, 0f, flipped))
    }

    @Test
    fun packageSpacePositionSurvivesAWorldPlaneThatMissesIt() {
        val clip = SectionClip.solve(
            axis = "y",
            flip = false,
            offset = 0f,
            bounds = floatArrayOf(0f, 0f, -40f, 40f, 16f, 0f),
            eyeX = 20f,
            eyeY = 40f,
            eyeZ = -20f,
            targetX = 20f,
            targetY = 8f,
            targetZ = -20f,
            boxEnabled = false,
            boxInset = 0f,
        )
        assertEquals(8f, clip.d, 1e-3f)
        assertTrue(SectionClip.clipped(29f, 80f, 8f, clip))
        assertTrue(SectionClip.visible(29f, 80f, 8f, 29f, 80f, 8f, clip))
        assertFalse(SectionClip.visible(29f, 40f, -20f, 29f, -20f, 40f, clip))
    }

    @Test
    fun packageSpaceBoxKeepsAPointWhoseWorldYIsOutside() {
        val clip = solve(axis = "x", flip = false, offset = 1f, box = true, inset = 0f)
        assertTrue(SectionClip.clipped(5f, 80f, 1f, clip))
        assertTrue(SectionClip.visible(5f, 80f, 1f, 5f, -1f, 2f, clip))
        assertFalse(SectionClip.visible(5f, 80f, 1f, 5f, -80f, 80f, clip))
    }

    @Test
    fun offsetSlidesThePlaneToTheFarFace() {
        val positive = solve(axis = "y", flip = false, offset = 1f)
        assertEquals(1f, positive.ny, 1e-4f)
        assertEquals(4f, positive.d, 1e-3f)
        assertFalse(SectionClip.clipped(5f, 3.9f, 1f, positive))
        val negative = solve(axis = "z", flip = false, offset = -1f)
        assertEquals(0f, negative.d, 1e-3f)
        assertTrue(SectionClip.clipped(5f, 2f, 1f, negative))
        assertFalse(SectionClip.clipped(5f, 2f, 0f, negative))
    }

    @Test
    fun viewPlaneFacesTheCameraAndIgnoresZoomDistance() {
        val clip = SectionClip.solve(
            axis = "view",
            flip = false,
            offset = 0f,
            bounds = floatArrayOf(-2f, -2f, -2f, 2f, 2f, 2f),
            eyeX = 0f,
            eyeY = 0f,
            eyeZ = 40f,
            targetX = 0f,
            targetY = 0f,
            targetZ = 0f,
            boxEnabled = false,
            boxInset = 0f,
        )
        assertEquals(0f, clip.nx, 1e-4f)
        assertEquals(0f, clip.ny, 1e-4f)
        assertEquals(1f, clip.nz, 1e-4f)
        assertEquals(0f, clip.d, 1e-3f)
        assertTrue(SectionClip.clipped(0f, 0f, 0.5f, clip))
        assertFalse(SectionClip.clipped(0f, 0f, -0.5f, clip))
    }

    @Test
    fun degenerateViewDirectionFallsBackToZ() {
        val clip = SectionClip.solve(
            axis = "view",
            flip = false,
            offset = 0f,
            bounds = floatArrayOf(-1f, -1f, -1f, 1f, 1f, 1f),
            eyeX = 3f,
            eyeY = 4f,
            eyeZ = 5f,
            targetX = 3f,
            targetY = 4f,
            targetZ = 5f,
            boxEnabled = false,
            boxInset = 0f,
        )
        assertEquals(0f, clip.nx, 1e-4f)
        assertEquals(0f, clip.ny, 1e-4f)
        assertEquals(1f, clip.nz, 1e-4f)
    }

    @Test
    fun boxShrinksTowardTheCentre() {
        val clip = solve(axis = "x", flip = false, offset = 1f, box = true, inset = 0.5f)
        assertTrue(clip.box)
        assertEquals(2.5f, clip.minX, 1e-3f)
        assertEquals(7.5f, clip.maxX, 1e-3f)
        assertEquals(1f, clip.minY, 1e-3f)
        assertEquals(3f, clip.maxY, 1e-3f)
        assertFalse(SectionClip.clipped(5f, 2f, 1f, clip))
        assertTrue(SectionClip.clipped(1f, 2f, 1f, clip))
    }

    @Test
    fun pickingRejectsAClearCutAndKeepsThePlaneAndGarbage() {
        val clip = solve(axis = "x", flip = false, offset = 0f)
        assertTrue(SectionClip.rejects(8f, 2f, 1f, clip, bounds))
        assertFalse(SectionClip.rejects(5.01f, 2f, 1f, clip, bounds))
        assertFalse(SectionClip.rejects(4f, 2f, 1f, clip, bounds))
        assertFalse(SectionClip.rejects(1000f, 1000f, 1000f, clip, bounds))
    }

    @Test
    fun nearSliderReachesTheFocusAndStaysAtTheBase() {
        assertEquals(0.05, SectionClip.nearDistance(0.05, 10.0, 0.0), 1e-6)
        assertEquals(9.801, SectionClip.nearDistance(0.05, 10.0, 1.0), 1e-6)
        assertEquals(0.05, SectionClip.nearDistance(0.05, 0.01, 1.0), 1e-6)
        assertEquals(0.05, SectionClip.nearDistance(0.05, 10.0, Double.NaN), 1e-6)
        assertEquals(0.05, SectionClip.nearDistance(Double.NaN, 10.0, 0.0), 1e-6)
    }

    @Test
    fun unprojectAppliesTheCameraModel() {
        val identity = DoubleArray(16) { if (it % 5 == 0) 1.0 else 0.0 }
        val origin = SectionClip.unproject(identity, identity, 100, 50, 50f, 25f, 0.5f)
        assertEquals(0f, origin!![0], 1e-4f)
        assertEquals(0f, origin[1], 1e-4f)
        assertEquals(0f, origin[2], 1e-4f)
        val moved = doubleArrayOf(
            1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            3.0, 4.0, 5.0, 1.0,
        )
        val world = SectionClip.unproject(identity, moved, 100, 50, 50f, 25f, 0.5f)
        assertEquals(3f, world!![0], 1e-4f)
        assertEquals(4f, world[1], 1e-4f)
        assertEquals(5f, world[2], 1e-4f)
        assertNull(SectionClip.unproject(identity, identity, 0, 10, 0f, 0f, 0f))
        assertNull(SectionClip.invert(DoubleArray(16)))
    }

    private fun solve(
        axis: String,
        flip: Boolean,
        offset: Float,
        box: Boolean = false,
        inset: Float = 0f,
    ): SectionClip.Clip {
        return SectionClip.solve(
            axis = axis,
            flip = flip,
            offset = offset,
            bounds = bounds,
            eyeX = 0f,
            eyeY = 2f,
            eyeZ = 8f,
            targetX = 5f,
            targetY = 2f,
            targetZ = 1f,
            boxEnabled = box,
            boxInset = inset,
        )
    }
}
