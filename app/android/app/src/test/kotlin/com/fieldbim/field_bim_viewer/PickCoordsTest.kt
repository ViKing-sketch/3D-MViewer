package com.fieldbim.field_bim_viewer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PickCoordsTest {
    @Test
    fun fullBleedKeepsTheGlYAxis() {
        val coords = PickCoords.resolve(0, 0, 400, 800, 800, 20f, 10f)
        assertEquals(20, coords!![0])
        assertEquals(789, coords[1])
    }

    @Test
    fun portraitInsetStaysInsideThePickBuffer() {
        // Surface 2000, sheet inset leaves a 1414-tall viewport whose GL bottom is 586.
        // A tap at the top of the model must be the top row of a 1414-tall buffer,
        // not surfaceY 2000, which is past that buffer.
        val top = PickCoords.resolve(0, 586, 1080, 1414, 2000, 100f, 0f)
        assertEquals(100, top!![0])
        assertEquals(1413, top[1])
        val centre = PickCoords.resolve(0, 586, 1080, 1414, 2000, 540f, 707f)
        assertEquals(540, centre!![0])
        assertEquals(706, centre[1])
    }

    @Test
    fun sheetTapIsOutsideTheViewport() {
        assertNull(PickCoords.resolve(0, 586, 1080, 1414, 2000, 100f, 1500f))
        assertNull(PickCoords.resolve(0, 0, 1, 800, 800, 0f, 10f))
        assertNull(PickCoords.resolve(0, 0, 400, 800, 800, -4f, 10f))
    }
}
