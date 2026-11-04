package com.fieldbim.field_bim_viewer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class CameraFitTest {
    @Test
    fun targetIsTheUprightCentre() {
        val source = ElementGeom(
            1L,
            floatArrayOf(0f, 0f, 0f),
            floatArrayOf(10f, 20f, 3f),
            floatArrayOf(1f, 1f, 1f, 1f),
        ).upright()
        val box = floatArrayOf(
            source.min[0],
            source.min[1],
            source.min[2],
            source.max[0],
            source.max[1],
            source.max[2],
        )
        val pose = CameraFit.pose(box, "iso", 0.5)
        assertEquals(5f, pose.targetX, 0.001f)
        assertEquals(1.5f, pose.targetY, 0.001f)
        assertEquals(-10f, pose.targetZ, 0.001f)
        assertTrue(pose.distance > pose.radius)
        assertTrue(CameraFit.frames(box, "iso", 0.5))
    }

    @Test
    fun portraitFramesTheWideSiteFromTheDeviceLog() {
        // Y-up fit reported for the partial model: a wide footprint and a short height.
        val box = floatArrayOf(0f, 0f, -278.99225f, 224.77005f, 65.460175f, -0f)
        val portrait = CameraFit.pose(box, "iso", 0.46)
        val centreZ = (box[2] + box[5]) * 0.5f
        assertEquals(112.385025f, portrait.targetX, 0.001f)
        assertEquals(32.730087f, portrait.targetY, 0.001f)
        assertEquals(centreZ, portrait.targetZ, 0.001f)
        assertTrue(portrait.distance > portrait.radius)
        // Half-extent times 2.8 left this site inside the camera. The sphere and the
        // narrower field of view put the eye well outside it.
        assertTrue(portrait.distance > 800f)
        assertTrue(abs(portrait.eyeX - portrait.targetX) + abs(portrait.eyeZ - portrait.targetZ) > portrait.radius)
        assertTrue(CameraFit.frames(box, "iso", 0.46))
        assertTrue(CameraFit.frames(box, "iso", 1.8))
        assertTrue(CameraFit.frames(box, "front", 0.46))
    }

    @Test
    fun tallBoxIsFramedTighterThanASphere() {
        val box = floatArrayOf(-1f, 0f, -1f, 1f, 40f, 1f)
        val pose = CameraFit.pose(box, "front", 0.46)
        assertTrue(pose.distance > pose.radius)
        // A sphere around this column sits much farther out than the projected box.
        assertTrue(pose.distance < pose.radius * 4f)
        assertTrue(CameraFit.frames(box, "front", 0.46))
        assertTrue(CameraFit.frames(box, "iso", 0.46))
    }
}
