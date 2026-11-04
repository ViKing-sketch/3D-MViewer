package com.fieldbim.field_bim_viewer

/**
 * Maps a surface touch into Filament's pick buffer.
 *
 * The pick texture is the viewport width by height with origin (0, 0).
 * [View.pick] coordinates are relative to that buffer, Y up from its bottom.
 * Adding the viewport's bottom offset addresses a pixel that does not exist
 * once the portrait sheet lifts the viewport.
 */
object PickCoords {
    /**
     * [x] and [y] are touch coordinates from the top-left of the surface.
     * Returns null when the viewport is not ready or the touch is outside it
     * (the portrait sheet below the model).
     */
    fun resolve(
        left: Int,
        bottom: Int,
        width: Int,
        height: Int,
        surfaceHeight: Int,
        x: Float,
        y: Float,
    ): IntArray? {
        if (width <= 1 || height <= 1) return null
        val localX = x.toInt() - left
        val top = surfaceHeight - (bottom + height)
        val localY = y.toInt() - top
        if (localX < 0 || localY < 0 || localX >= width || localY >= height) return null
        return intArrayOf(localX, height - 1 - localY)
    }
}
