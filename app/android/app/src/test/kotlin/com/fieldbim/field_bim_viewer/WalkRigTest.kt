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

    @Test
    fun stickStepFollowsYawAndLeavesEyeHeight() {
        val ahead = WalkRig.integrate(
            WalkRig.Pose(0f, 1.6f, 0f, 0f, 0f),
            WalkRig.Axes(forward = 1f),
            dt = 1f,
        )
        assertEquals(0f, ahead.eyeX, 1e-4f)
        assertEquals(1.6f, ahead.eyeY, 0f)
        assertEquals(-WalkRig.metresPerSecond, ahead.eyeZ, 1e-4f)

        val turned = WalkRig.integrate(
            WalkRig.Pose(0f, 1.6f, 0f, (PI / 2.0).toFloat(), 0.4f),
            WalkRig.Axes(strafe = 0.5f, forward = 1f),
            dt = 1f,
        )
        assertEquals(WalkRig.metresPerSecond, turned.eyeX, 1e-4f)
        assertEquals(1.6f, turned.eyeY, 0f)
        assertEquals(0.5f * WalkRig.metresPerSecond, turned.eyeZ, 1e-4f)
        assertEquals(0.4f, turned.pitch, 1e-4f)
    }

    @Test
    fun stickLookClampsPitchWithoutMovingTheEye() {
        val start = WalkRig.Pose(2f, 1.6f, -3f, 0.2f, 0f)
        val up = WalkRig.integrate(start, WalkRig.Axes(pitch = 1f), dt = 100f)
        assertEquals(WalkRig.maxPitch, up.pitch, 1e-4f)
        assertEquals(2f, up.eyeX, 0f)
        assertEquals(1.6f, up.eyeY, 0f)
        assertEquals(-3f, up.eyeZ, 0f)

        val down = WalkRig.integrate(
            start,
            WalkRig.Axes(yaw = 1f, pitch = -1f),
            dt = 100f,
        )
        assertEquals(-WalkRig.maxPitch, down.pitch, 1e-4f)
        assertEquals(0.2f + WalkRig.yawPerSecond * 100f, down.yaw, 1e-3f)
        assertEquals(start.eyeY, down.eyeY, 0f)
    }

    @Test
    fun stickMoveUsesTheYawFromTheStartOfTheFrame() {
        val next = WalkRig.integrate(
            WalkRig.Pose(0f, 1.6f, 0f, 0f, 0f),
            WalkRig.Axes(forward = 1f, yaw = 1f),
            dt = 1f,
        )
        assertEquals(0f, next.eyeX, 1e-4f)
        assertEquals(1.6f, next.eyeY, 0f)
        assertEquals(-WalkRig.metresPerSecond, next.eyeZ, 1e-4f)
        assertEquals(WalkRig.yawPerSecond, next.yaw, 1e-4f)
    }
}
