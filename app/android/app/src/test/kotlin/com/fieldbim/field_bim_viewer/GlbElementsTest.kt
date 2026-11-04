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

    @Test
    fun outwardTriangleFacesAwayFromTheCentre() {
        val packed = floatArrayOf(
            0f, 0f, 1f,
            1f, 0f, 1f,
            1f, 1f, 1f,
        )
        assertEquals(1f, GlbElements.windingSign(0f, 0f, 0f, packed), 0f)
    }

    @Test
    fun inwardTriangleFacesTheCentre() {
        val packed = floatArrayOf(
            0f, 0f, 1f,
            1f, 1f, 1f,
            1f, 0f, 1f,
        )
        assertEquals(-1f, GlbElements.windingSign(0f, 0f, 0f, packed), 0f)
    }

    @Test
    fun rotationKeepsTheSignAndAMirrorFlipsIt() {
        val packed = floatArrayOf(
            0f, 0f, 1f,
            1f, 0f, 1f,
            1f, 1f, 1f,
        )
        val zToY = floatArrayOf(
            1f, 0f, 0f, 0f,
            0f, 0f, -1f, 0f,
            0f, 1f, 0f, 0f,
            0f, 0f, 0f, 1f,
        )
        val mirrorX = floatArrayOf(
            -1f, 0f, 0f, 0f,
            0f, 1f, 0f, 0f,
            0f, 0f, 1f, 0f,
            0f, 0f, 0f, 1f,
        )
        assertEquals(1f, GlbElements.windingSign(0f, 0f, 0f, transformAll(zToY, packed)), 0f)
        assertEquals(-1f, GlbElements.windingSign(0f, 0f, 0f, transformAll(mirrorX, packed)), 0f)
    }

    private fun transformAll(matrix: FloatArray, packed: FloatArray): FloatArray {
        val out = FloatArray(packed.size)
        var index = 0
        while (index + 2 < packed.size) {
            val point = GlbElements.transformPoint(matrix, packed[index], packed[index + 1], packed[index + 2])
            out[index] = point[0]
            out[index + 1] = point[1]
            out[index + 2] = point[2]
            index += 3
        }
        return out
    }
}
