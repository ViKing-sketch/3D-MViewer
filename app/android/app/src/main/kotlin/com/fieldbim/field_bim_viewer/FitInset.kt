package com.fieldbim.field_bim_viewer

/**
 * The portrait sheet and the Filament viewport have to meet. A gap of even a
 * few pixels is the undrawn bottom of the SurfaceView, which flashes black.
 */
internal object FitInset {
    fun changed(current: Double, next: Double, surfaceHeight: Int): Boolean {
        if (current == next) return false
        if (surfaceHeight <= 1) return true
        return kotlin.math.abs(next - current) * surfaceHeight >= 0.5
    }
}
