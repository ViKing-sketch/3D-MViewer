package com.fieldbim.field_bim_viewer

import android.view.MotionEvent
import kotlin.math.hypot

/**
 * One finger looks around. Two fingers walk: drag moves, pinch steps forward.
 * The eye height is left to [WalkRig.move].
 */
internal class WalkGestures(
    private val onLook: (dx: Float, dy: Float) -> Unit,
    private val onMove: (forwardMetres: Float, strafeMetres: Float) -> Unit,
) {
    private var lastX = 0f
    private var lastY = 0f
    private var lastSep = 0f
    private var tracking = false

    fun onTouchEvent(event: MotionEvent) {
        val action = event.actionMasked
        if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
            tracking = false
            return
        }
        if (action == MotionEvent.ACTION_DOWN ||
            action == MotionEvent.ACTION_POINTER_DOWN ||
            !tracking
        ) {
            remember(event)
            tracking = true
            return
        }
        if (action != MotionEvent.ACTION_MOVE) return
        if (event.pointerCount <= 1) {
            onLook(event.x - lastX, event.y - lastY)
            remember(event)
            return
        }
        val midX = (event.getX(0) + event.getX(1)) * 0.5f
        val midY = (event.getY(0) + event.getY(1)) * 0.5f
        val sep = hypot(event.getX(1) - event.getX(0), event.getY(1) - event.getY(0))
        val strafe = (midX - lastX) * WalkRig.metresPerPixel
        val forward = (lastY - midY) * WalkRig.metresPerPixel
        val pinch = (lastSep - sep) * WalkRig.metresPerPinchPixel
        onMove(forward + pinch, strafe)
        lastX = midX
        lastY = midY
        lastSep = sep
    }

    private fun remember(event: MotionEvent) {
        if (event.pointerCount >= 2) {
            lastX = (event.getX(0) + event.getX(1)) * 0.5f
            lastY = (event.getY(0) + event.getY(1)) * 0.5f
            lastSep = hypot(event.getX(1) - event.getX(0), event.getY(1) - event.getY(0))
        } else {
            lastX = event.x
            lastY = event.y
            lastSep = 0f
        }
    }
}
