package com.fieldbim.field_bim_viewer

import android.view.MotionEvent
import android.view.View
import com.google.android.filament.utils.Manipulator
import kotlin.math.abs
import kotlin.math.hypot

/**
 * Orbit and pan go straight to Filament. Pinch zoom is reported as a scroll
 * delta in the same units as [Manipulator.scroll], so the view can ease it.
 * The thresholds match Filament's GestureDetector.
 */
internal class OrbitGestures(
    private val view: View,
    private val manipulator: Manipulator,
    private val onZoom: (x: Int, y: Int, scrollDelta: Float) -> Unit,
) {
    private enum class Gesture { NONE, ORBIT, PAN, ZOOM }

    private class Touch(val x0: Float, val y0: Float, val x1: Float, val y1: Float) {
        val separation get() = hypot(x1 - x0, y1 - y0)
        val midX get() = (x0 + x1) * 0.5f
        val midY get() = (y0 + y1) * 0.5f
    }

    private var current = Gesture.NONE
    private var previous = Touch(0f, 0f, 0f, 0f)
    private val pans = ArrayList<Touch>()
    private val orbits = ArrayList<Touch>()
    private val zooms = ArrayList<Touch>()

    fun onTouchEvent(event: MotionEvent) {
        val touch = read(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_MOVE -> {
                if ((event.pointerCount != 1 && current == Gesture.ORBIT) ||
                    (event.pointerCount != 2 && current == Gesture.PAN) ||
                    (event.pointerCount != 2 && current == Gesture.ZOOM)
                ) {
                    end()
                    return
                }
                if (current == Gesture.ZOOM) {
                    val delta = (previous.separation - touch.separation) * Dolly.pinchScrollPerPixel
                    onZoom(touch.midX.toInt(), touch.midY.toInt(), delta)
                    previous = touch
                    return
                }
                if (current != Gesture.NONE) {
                    manipulator.grabUpdate(touch.midX.toInt(), touch.midY.toInt())
                    return
                }
                if (event.pointerCount == 1) orbits.add(touch)
                if (event.pointerCount == 2) {
                    pans.add(touch)
                    zooms.add(touch)
                }
                if (orbits.size > 2) {
                    manipulator.grabBegin(touch.midX.toInt(), touch.midY.toInt(), false)
                    current = Gesture.ORBIT
                    return
                }
                if (isZoom()) {
                    current = Gesture.ZOOM
                    previous = touch
                    return
                }
                if (isPan()) {
                    manipulator.grabBegin(touch.midX.toInt(), touch.midY.toInt(), true)
                    current = Gesture.PAN
                }
            }
            MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_UP -> end()
        }
    }

    private fun read(event: MotionEvent): Touch {
        val height = view.height
        var x0 = 0f
        var y0 = 0f
        var x1 = 0f
        var y1 = 0f
        if (event.pointerCount >= 1) {
            x0 = event.getX(0)
            y0 = height - event.getY(0)
            x1 = x0
            y1 = y0
        }
        if (event.pointerCount >= 2) {
            x1 = event.getX(1)
            y1 = height - event.getY(1)
        }
        return Touch(x0, y0, x1, y1)
    }

    private fun end() {
        pans.clear()
        orbits.clear()
        zooms.clear()
        current = Gesture.NONE
        manipulator.grabEnd()
    }

    private fun isZoom(): Boolean {
        if (zooms.size <= 2) return false
        return abs(zooms.last().separation - zooms.first().separation) > 10f
    }

    private fun isPan(): Boolean {
        if (pans.size <= 2) return false
        val oldest = pans.first()
        val newest = pans.last()
        return hypot(newest.midX - oldest.midX, newest.midY - oldest.midY) > 4f
    }
}
