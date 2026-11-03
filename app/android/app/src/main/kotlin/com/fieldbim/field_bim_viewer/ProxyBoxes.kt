package com.fieldbim.field_bim_viewer

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** One shared unit-cube GLB whose nodes are axis-aligned stand-ins. */
data class ProxyGlb(val buffer: ByteBuffer, val count: Int)

/**
 * Coarse stand-ins for elements whose source GLB does not fit the memory budget.
 *
 * Coordinates stay in package Z-up metres. The viewer applies the same Z-up to
 * Y-up root transform it uses for real assets. The cube is −0.5..0.5 so the
 * node scale is the full extent.
 */
object ProxyBoxes {
    private const val cap = 4000
    private const val minExtent = 0.02f
    private const val binBytes = 648

    fun build(geoms: List<ElementGeom>): ProxyGlb? {
        if (geoms.isEmpty()) return null
        val chosen = geoms
            .sortedByDescending { volume(it) }
            .take(cap)
        val json = json(chosen).toByteArray(Charsets.UTF_8)
        val jsonPad = (4 - json.size % 4) % 4
        val total = 12 + 8 + json.size + jsonPad + 8 + binBytes
        val buffer = ByteBuffer.allocateDirect(total).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(0x46546C67)
        buffer.putInt(2)
        buffer.putInt(total)
        buffer.putInt(json.size + jsonPad)
        buffer.putInt(0x4E4F534A)
        buffer.put(json)
        repeat(jsonPad) { buffer.put(' '.code.toByte()) }
        buffer.putInt(binBytes)
        buffer.putInt(0x004E4942)
        buffer.put(cubeBin())
        buffer.position(0)
        buffer.limit(total)
        return ProxyGlb(buffer, chosen.size)
    }

    private fun volume(geom: ElementGeom): Float {
        val sx = (geom.max[0] - geom.min[0]).coerceAtLeast(0f)
        val sy = (geom.max[1] - geom.min[1]).coerceAtLeast(0f)
        val sz = (geom.max[2] - geom.min[2]).coerceAtLeast(0f)
        return sx * sy * sz
    }

    private fun json(geoms: List<ElementGeom>): String {
        val children = StringBuilder()
        val nodes = StringBuilder()
        geoms.forEachIndexed { index, geom ->
            val node = index + 1
            if (index > 0) children.append(',')
            children.append(node)
            if (index > 0) nodes.append(',')
            val sx = extent(geom.max[0] - geom.min[0])
            val sy = extent(geom.max[1] - geom.min[1])
            val sz = extent(geom.max[2] - geom.min[2])
            val tx = (geom.min[0] + geom.max[0]) * 0.5f
            val ty = (geom.min[1] + geom.max[1]) * 0.5f
            val tz = (geom.min[2] + geom.max[2]) * 0.5f
            nodes.append("{\"mesh\":0,\"extras\":{\"elementId\":")
            nodes.append(geom.id)
            nodes.append("},\"matrix\":[")
            nodes.append(sx).append(",0,0,0,0,")
            nodes.append(sy).append(",0,0,0,0,")
            nodes.append(sz).append(",0,")
            nodes.append(tx).append(',')
            nodes.append(ty).append(',')
            nodes.append(tz).append(",1]}")
        }
        return "{\"asset\":{\"version\":\"2.0\"},\"scene\":0," +
            "\"scenes\":[{\"nodes\":[0]}]," +
            "\"nodes\":[{\"name\":\"root\",\"children\":[$children]},$nodes]," +
            "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":1}," +
            "\"indices\":2,\"material\":0}]}]," +
            "\"materials\":[{\"doubleSided\":true,\"pbrMetallicRoughness\":{" +
            "\"baseColorFactor\":[0.62,0.66,0.7,1],\"metallicFactor\":0,\"roughnessFactor\":0.8}}]," +
            "\"accessors\":[" +
            "{\"bufferView\":0,\"componentType\":5126,\"count\":24,\"type\":\"VEC3\"," +
            "\"min\":[-0.5,-0.5,-0.5],\"max\":[0.5,0.5,0.5]}," +
            "{\"bufferView\":1,\"componentType\":5126,\"count\":24,\"type\":\"VEC3\"}," +
            "{\"bufferView\":2,\"componentType\":5123,\"count\":36,\"type\":\"SCALAR\"}" +
            "]," +
            "\"bufferViews\":[" +
            "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":288,\"target\":34962}," +
            "{\"buffer\":0,\"byteOffset\":288,\"byteLength\":288,\"target\":34962}," +
            "{\"buffer\":0,\"byteOffset\":576,\"byteLength\":72,\"target\":34963}" +
            "]," +
            "\"buffers\":[{\"byteLength\":$binBytes}]}"
    }

    private fun extent(span: Float): Float = if (span < minExtent) minExtent else span

    private fun cubeBin(): ByteArray {
        val bin = ByteBuffer.allocate(binBytes).order(ByteOrder.LITTLE_ENDIAN)
        val faces = arrayOf(
            floatArrayOf(0f, 0f, 1f, -0.5f, -0.5f, 0.5f, 0.5f, -0.5f, 0.5f, 0.5f, 0.5f, 0.5f, -0.5f, 0.5f, 0.5f),
            floatArrayOf(0f, 0f, -1f, -0.5f, -0.5f, -0.5f, -0.5f, 0.5f, -0.5f, 0.5f, 0.5f, -0.5f, 0.5f, -0.5f, -0.5f),
            floatArrayOf(0f, 1f, 0f, -0.5f, 0.5f, -0.5f, -0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, -0.5f),
            floatArrayOf(0f, -1f, 0f, -0.5f, -0.5f, -0.5f, 0.5f, -0.5f, -0.5f, 0.5f, -0.5f, 0.5f, -0.5f, -0.5f, 0.5f),
            floatArrayOf(1f, 0f, 0f, 0.5f, -0.5f, -0.5f, 0.5f, 0.5f, -0.5f, 0.5f, 0.5f, 0.5f, 0.5f, -0.5f, 0.5f),
            floatArrayOf(-1f, 0f, 0f, -0.5f, -0.5f, -0.5f, -0.5f, -0.5f, 0.5f, -0.5f, 0.5f, 0.5f, -0.5f, 0.5f, -0.5f),
        )
        for (face in faces) {
            for (k in 3 until 15 step 3) {
                bin.putFloat(face[k])
                bin.putFloat(face[k + 1])
                bin.putFloat(face[k + 2])
            }
        }
        for (face in faces) {
            repeat(4) {
                bin.putFloat(face[0])
                bin.putFloat(face[1])
                bin.putFloat(face[2])
            }
        }
        for (face in 0 until 6) {
            val base = face * 4
            bin.putShort(base.toShort())
            bin.putShort((base + 1).toShort())
            bin.putShort((base + 2).toShort())
            bin.putShort(base.toShort())
            bin.putShort((base + 2).toShort())
            bin.putShort((base + 3).toShort())
        }
        return bin.array()
    }
}
