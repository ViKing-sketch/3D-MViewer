package com.fieldbim.field_bim_viewer

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile

/** Element geometry read from a GLB JSON chunk, without the BIN payload. */
data class ElementGeom(
    val id: Long,
    val min: FloatArray,
    val max: FloatArray,
    val color: FloatArray,
)

object GlbElements {
    fun readJson(file: File): String {
        RandomAccessFile(file, "r").use { raf ->
            val header = ByteArray(20)
            if (raf.read(header) != 20) error("glb header is short: ${file.name}")
            if (header[0] != 'g'.code.toByte() || header[1] != 'l'.code.toByte() ||
                header[2] != 'T'.code.toByte() || header[3] != 'F'.code.toByte()
            ) {
                error("not a glb: ${file.name}")
            }
            val jsonLen = u32(header, 12)
            val jsonType = u32(header, 16)
            if (jsonType != 0x4E4F534A) error("glb has no JSON chunk: ${file.name}")
            if (jsonLen < 0 || jsonLen > 64 * 1024 * 1024) error("glb JSON chunk is unexpected: ${file.name}")
            val json = ByteArray(jsonLen)
            raf.readFully(json)
            return String(json, Charsets.UTF_8).trim { it <= ' ' }
        }
    }

    fun parse(json: String): List<ElementGeom> {
        val root = JSONObject(json)
        val nodes = root.optJSONArray("nodes") ?: return emptyList()
        val meshes = root.optJSONArray("meshes")
        val accessors = root.optJSONArray("accessors")
        val materials = root.optJSONArray("materials")
        val found = ArrayList<ElementGeom>()
        for (i in 0 until nodes.length()) {
            val node = nodes.optJSONObject(i) ?: continue
            val id = elementId(node) ?: continue
            if (!node.has("mesh") || meshes == null || accessors == null) continue
            val mesh = meshes.optJSONObject(node.getInt("mesh")) ?: continue
            val prims = mesh.optJSONArray("primitives") ?: continue
            if (prims.length() == 0) continue
            val prim = prims.getJSONObject(0)
            val attrs = prim.optJSONObject("attributes") ?: continue
            if (!attrs.has("POSITION")) continue
            val acc = accessors.optJSONObject(attrs.getInt("POSITION")) ?: continue
            val min = vec3(acc.optJSONArray("min")) ?: continue
            val max = vec3(acc.optJSONArray("max")) ?: continue
            val color = colorOf(materials, prim.optInt("material", -1))
            found.add(ElementGeom(id, min, max, color))
        }
        return found
    }

    fun elementId(node: JSONObject): Long? {
        val extras = node.optJSONObject("extras")
        if (extras != null && extras.has("elementId")) {
            return extras.getLong("elementId")
        }
        return node.optString("name", "").toLongOrNull()
    }

    private fun colorOf(materials: JSONArray?, index: Int): FloatArray {
        val fallback = floatArrayOf(0.7f, 0.72f, 0.74f, 1f)
        if (materials == null || index < 0 || index >= materials.length()) return fallback
        val pbr = materials.optJSONObject(index)?.optJSONObject("pbrMetallicRoughness") ?: return fallback
        val factor = pbr.optJSONArray("baseColorFactor") ?: return fallback
        if (factor.length() < 3) return fallback
        val alpha = if (factor.length() >= 4) factor.getDouble(3).toFloat() else 1f
        return floatArrayOf(
            factor.getDouble(0).toFloat(),
            factor.getDouble(1).toFloat(),
            factor.getDouble(2).toFloat(),
            alpha,
        )
    }

    private fun vec3(array: JSONArray?): FloatArray? {
        if (array == null || array.length() < 3) return null
        return floatArrayOf(array.getDouble(0).toFloat(), array.getDouble(1).toFloat(), array.getDouble(2).toFloat())
    }

    private fun u32(bytes: ByteArray, offset: Int): Int {
        return (bytes[offset].toInt() and 0xff) or
            ((bytes[offset + 1].toInt() and 0xff) shl 8) or
            ((bytes[offset + 2].toInt() and 0xff) shl 16) or
            ((bytes[offset + 3].toInt() and 0xff) shl 24)
    }
}
