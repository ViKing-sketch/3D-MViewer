package com.fieldbim.field_bim_viewer

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * First-person look and a horizontal step on one storey.
 *
 * Y is up in the Filament scene. The eye height never changes here, and no
 * mesh or box is consulted: a step can pass through a wall. The start height
 * is chosen in Dart from the storey floor.
 */
internal object WalkRig {
    const val maxPitch = 1.15f
    const val yawPerPixel = 0.004f
    const val pitchPerPixel = 0.004f
    const val metresPerPixel = 0.015f
    const val metresPerPinchPixel = 0.01f
    const val metresPerWheel = 0.5f

    data class Pose(
        val eyeX: Float,
        val eyeY: Float,
        val eyeZ: Float,
        val yaw: Float,
        val pitch: Float,
    )

    /** yaw 0 looks toward -Z. pitch 0 is level. */
    fun forward(yaw: Float, pitch: Float): FloatArray {
        val cp = cos(pitch)
        return floatArrayOf(sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)
    }

    fun fromLook(
        eyeX: Float,
        eyeY: Float,
        eyeZ: Float,
        lookX: Float,
        lookY: Float,
        lookZ: Float,
    ): Pose {
        val horiz = sqrt(lookX * lookX + lookZ * lookZ).coerceAtLeast(1e-6f)
        val yaw = atan2(lookX, -lookZ)
        val pitch = atan2(lookY, horiz).coerceIn(-maxPitch, maxPitch)
        return Pose(eyeX, eyeY, eyeZ, yaw, pitch)
    }

    fun lookDrag(pose: Pose, dx: Float, dy: Float): Pose {
        return pose.copy(
            yaw = pose.yaw + dx * yawPerPixel,
            pitch = (pose.pitch - dy * pitchPerPixel).coerceIn(-maxPitch, maxPitch),
        )
    }

    /** [forwardMetres] follows the level look. [strafeMetres] is to the right. */
    fun move(pose: Pose, forwardMetres: Float, strafeMetres: Float): Pose {
        val fx = sin(pose.yaw)
        val fz = -cos(pose.yaw)
        val rx = cos(pose.yaw)
        val rz = sin(pose.yaw)
        return pose.copy(
            eyeX = pose.eyeX + fx * forwardMetres + rx * strafeMetres,
            eyeZ = pose.eyeZ + fz * forwardMetres + rz * strafeMetres,
        )
    }
}
