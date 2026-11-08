package com.fieldbim.field_bim_viewer

import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.PI

class WalkRigTest {
    @Test
    fun levelLookTowardNegativeZIsYawZero() {
        val pose = WalkRig.fromLook(3f, 1.8f, -1.5f, 0f, 0f, -1f)
        assertEquals(0f, pose.yaw, 1e-4f)
        assertEquals(0f, pose.pitch, 1e-4f)
        assertEquals(1.8f, pose.eyeY, 0f)
        val look = WalkRig.forward(pose.yaw, pose.pitch)
        assertEquals(0f, look[0], 1e-4f)
        assertEquals(0f, look[1], 1e-4f)
        assertEquals(-1f, look[2], 1e-4f)
    }

    @Test
    fun yawTurnsTheLevelStepWithoutChangingEyeHeight() {
        val start = WalkRig.Pose(0f, 1.6f, 0f, (PI / 2.0).toFloat(), 0f)
        val moved = WalkRig.move(start, forwardMetres = 4f, strafeMetres = 0f)
        assertEquals(4f, moved.eyeX, 1e-4f)
        assertEquals(1.6f, moved.eyeY, 0f)
        assertEquals(0f, moved.eyeZ, 1e-4f)
    }

    @Test
    fun aStepIsNotStoppedByAnythingInFrontOfTheEye() {
        val start = WalkRig.Pose(0f, 1.6f, -2f, 0f, 0f)
        val moved = WalkRig.move(start, forwardMetres = 5f, strafeMetres = 1f)
        assertEquals(1f, moved.eyeX, 1e-4f)
        assertEquals(1.6f, moved.eyeY, 0f)
        assertEquals(-7f, moved.eyeZ, 1e-4f)
    }

    @Test
    fun lookDragClampsPitchAndLeavesTheEye() {
        val start = WalkRig.Pose(1f, 1.6f, 2f, 0.2f, 0f)
        val up = WalkRig.lookDrag(start, dx = 0f, dy = -10000f)
        assertEquals(WalkRig.maxPitch, up.pitch, 1e-4f)
        assertEquals(1.6f, up.eyeY, 0f)
        assertEquals(1f, up.eyeX, 0f)
        val down = WalkRig.lookDrag(start, dx = 10f, dy = 10000f)
        assertEquals(-WalkRig.maxPitch, down.pitch, 1e-4f)
        assertEquals(start.yaw + 10f * WalkRig.yawPerPixel, down.yaw, 1e-4f)
    }
}
