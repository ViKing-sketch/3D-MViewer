package com.fieldbim.field_bim_viewer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DollyTest {
    @Test
    fun farCommandTravelsTheSameDistanceWithoutASingleJump() {
        val zoomSpeed = 3.5f
        var pending = -Dolly.wheelScroll
        var travelled = 0f
        var peak = 0f
        repeat(120) {
            val step = Dolly.step(pending, 1f / 60f, zoomSpeed, gap = 40f, radius = 10f)
            pending = step.pending
            val metres = -step.scroll * zoomSpeed
            travelled += metres
            if (metres > peak) peak = metres
        }
        assertEquals(0f, pending, 1e-3f)
        assertEquals(Dolly.wheelScroll * zoomSpeed, travelled, 0.05f)
        assertTrue(peak < 4f)
    }

    @Test
    fun nearSurfaceZoomInDoesNotCrossTheGapInOneFrame() {
        val zoomSpeed = 3.5f
        var pending = -20f
        var travelled = 0f
        var peak = 0f
        var gap = 1.2f
        repeat(90) {
            val step = Dolly.step(pending, 1f / 60f, zoomSpeed, gap, radius = 10f)
            pending = step.pending
            val metres = -step.scroll * zoomSpeed
            if (metres > peak) peak = metres
            if (metres > 0f) {
                travelled += metres
                gap = (gap - metres).coerceAtLeast(0f)
            }
        }
        assertTrue(peak < 0.4f)
        assertTrue(travelled < 6f)
        assertTrue(travelled < Dolly.wheelScroll * zoomSpeed * 2f)
    }

    @Test
    fun zoomOutNearTheSurfaceKeepsTheCommand() {
        val zoomSpeed = 3.5f
        var pending = Dolly.wheelScroll
        var travelled = 0f
        repeat(120) {
            val step = Dolly.step(pending, 1f / 60f, zoomSpeed, gap = 0f, radius = 10f)
            pending = step.pending
            travelled += -step.scroll * zoomSpeed
        }
        assertEquals(-Dolly.wheelScroll * zoomSpeed, travelled, 0.05f)
    }

    @Test
    fun gainIsFullOnceTheEyeClearsHalfTheRadius() {
        assertEquals(1f, Dolly.zoomInGain(6f, 10f), 1e-3f)
        assertTrue(Dolly.zoomInGain(0f, 10f) < 0.1f)
        assertEquals(0f, Dolly.gapToBox(0f, 0f, 0f, -1f, -1f, -1f, 1f, 1f, 1f), 1e-4f)
        assertEquals(2f, Dolly.gapToBox(3f, 0f, 0f, -1f, -1f, -1f, 1f, 1f, 1f), 1e-4f)
    }
}
