package com.fieldbim.field_bim_viewer

import org.junit.Assert.assertEquals
import org.junit.Test

class GlbElementsTest {
    @Test
    fun unionsPrimitivesAndAppliesTheNodeMatrix() {
        // Local union (−1,0,0)-(1,2,1), then scale 2,3,4 and translate +10 on X.
        // A parent translation is applied after the node, matching the glTF chain.
        val bounds = GlbElements.elementBounds(
            listOf(
                floatArrayOf(0f, 0f, 0f) to floatArrayOf(1f, 1f, 1f),
                floatArrayOf(-1f, 0f, 0f) to floatArrayOf(0f, 2f, 0f),
            ),
            listOf(
                floatArrayOf(
                    2f, 0f, 0f, 0f,
                    0f, 3f, 0f, 0f,
                    0f, 0f, 4f, 0f,
                    10f, 0f, 0f, 1f,
                ),
                floatArrayOf(
                    1f, 0f, 0f, 0f,
                    0f, 1f, 0f, 0f,
                    0f, 0f, 1f, 0f,
                    0f, 5f, 0f, 1f,
                ),
            ),
        )
        requireNotNull(bounds)
        assertEquals(8f, bounds.first[0], 0.001f)
        assertEquals(5f, bounds.first[1], 0.001f)
        assertEquals(0f, bounds.first[2], 0.001f)
        assertEquals(12f, bounds.second[0], 0.001f)
        assertEquals(11f, bounds.second[1], 0.001f)
        assertEquals(4f, bounds.second[2], 0.001f)
    }
}
