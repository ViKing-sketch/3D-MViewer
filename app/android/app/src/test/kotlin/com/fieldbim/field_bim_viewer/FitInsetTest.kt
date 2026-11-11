package com.fieldbim.field_bim_viewer

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FitInsetTest {
    @Test
    fun snapCloserThanOneAndAHalfPercentStillMovesTheViewport() {
        // 0.545 -> 0.55 on a 2000px surface is 10px. The old 0.015 gate
        // dropped it, and that strip flashed black above the sheet.
        assertTrue(FitInset.changed(0.545, 0.55, 2000))
        assertTrue(FitInset.changed(0.0, 0.22, 1))
    }

    @Test
    fun subPixelNoiseDoesNotReframe() {
        assertFalse(FitInset.changed(0.55, 0.55, 2000))
        assertFalse(FitInset.changed(0.55, 0.55 + 0.1 / 2000.0, 2000))
    }
}
