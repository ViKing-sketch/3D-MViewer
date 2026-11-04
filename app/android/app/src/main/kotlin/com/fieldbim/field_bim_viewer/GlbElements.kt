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
) {
    /** Package Z-up metres to Filament Y-up: (x, y, z) -> (x, z, -y). */
    fun upright(): ElementGeom = copy(
        min = floatArrayOf(min[0], min[2], -max[1]),
        max = floatArrayOf(max[0], max[2], -min[1]),
    )
}

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
        val parent = IntArray(nodes.length()) { -1 }
        for (i in 0 until nodes.length()) {
            val children = nodes.optJSONObject(i)?.optJSONArray("children") ?: continue
            for (c in 0 until children.length()) {
                val child = children.optInt(c, -1)
                if (child in parent.indices) parent[child] = i
            }
        }
        val found = ArrayList<ElementGeom>()
        for (i in 0 until nodes.length()) {
            val node = nodes.optJSONObject(i) ?: continue
            val id = elementId(node) ?: continue
            if (!node.has("mesh") || meshes == null || accessors == null) continue
            val mesh = meshes.optJSONObject(node.getInt("mesh")) ?: continue
            val prims = mesh.optJSONArray("primitives") ?: continue
            val primBounds = ArrayList<Pair<FloatArray, FloatArray>>()
            var color = floatArrayOf(0.7f, 0.72f, 0.74f, 1f)
            for (p in 0 until prims.length()) {
                val prim = prims.optJSONObject(p) ?: continue
                val attrs = prim.optJSONObject("attributes") ?: continue
                if (!attrs.has("POSITION")) continue
                val acc = accessors.optJSONObject(attrs.getInt("POSITION")) ?: continue
                val pMin = vec3(acc.optJSONArray("min")) ?: continue
                val pMax = vec3(acc.optJSONArray("max")) ?: continue
                if (primBounds.isEmpty()) color = colorOf(materials, prim.optInt("material", -1))
                primBounds.add(pMin to pMax)
            }
            val chain = ArrayList<FloatArray>()
            var walk = i
            var guard = 0
            while (walk >= 0 && guard++ < 64) {
                val current = nodes.optJSONObject(walk) ?: break
                val matrix = nodeMatrix(current)
                if (matrix != null) chain.add(matrix)
                walk = parent[walk]
            }
            val turned = elementBounds(primBounds, chain) ?: continue
            found.add(ElementGeom(id, turned.first, turned.second, color))
        }
        return found
    }

    /**
     * Unions every primitive, then applies [chain] from the node outward.
     * Unit tests call this directly because the JVM android.jar stubs org.json.
     */
    fun elementBounds(
        primitives: List<Pair<FloatArray, FloatArray>>,
        chain: List<FloatArray>,
    ): Pair<FloatArray, FloatArray>? {
        if (primitives.isEmpty()) return null
        var min = primitives[0].first.copyOf()
        var max = primitives[0].second.copyOf()
        for (index in 1 until primitives.size) {
            val merged = unionAabb(min, max, primitives[index].first, primitives[index].second)
            min = merged.first
            max = merged.second
        }
        for (matrix in chain) {
            val turned = transformAabb(matrix, min, max)
            min = turned.first
            max = turned.second
        }
        return min to max
    }

    private fun unionAabb(
        min: FloatArray,
        max: FloatArray,
        otherMin: FloatArray,
        otherMax: FloatArray,
    ): Pair<FloatArray, FloatArray> {
        return floatArrayOf(
            minOf(min[0], otherMin[0]),
            minOf(min[1], otherMin[1]),
            minOf(min[2], otherMin[2]),
        ) to floatArrayOf(
            maxOf(max[0], otherMax[0]),
            maxOf(max[1], otherMax[1]),
            maxOf(max[2], otherMax[2]),
        )
    }

    private fun nodeMatrix(node: JSONObject): FloatArray? {
        val matrix = node.optJSONArray("matrix")
        if (matrix != null && matrix.length() >= 16) {
            return FloatArray(16) { matrix.getDouble(it).toFloat() }
        }
        val translation = vec3(node.optJSONArray("translation"))
        val scale = vec3(node.optJSONArray("scale"))
        if (translation == null && scale == null) return null
        val sx = scale?.get(0) ?: 1f
        val sy = scale?.get(1) ?: 1f
        val sz = scale?.get(2) ?: 1f
        val tx = translation?.get(0) ?: 0f
        val ty = translation?.get(1) ?: 0f
        val tz = translation?.get(2) ?: 0f
        return floatArrayOf(
            sx, 0f, 0f, 0f,
            0f, sy, 0f, 0f,
            0f, 0f, sz, 0f,
            tx, ty, tz, 1f,
        )
    }

    private fun transformAabb(matrix: FloatArray, min: FloatArray, max: FloatArray): Pair<FloatArray, FloatArray> {
        var minX = Float.POSITIVE_INFINITY
        var minY = Float.POSITIVE_INFINITY
        var minZ = Float.POSITIVE_INFINITY
        var maxX = Float.NEGATIVE_INFINITY
        var maxY = Float.NEGATIVE_INFINITY
        var maxZ = Float.NEGATIVE_INFINITY
        val xs = floatArrayOf(min[0], max[0])
        val ys = floatArrayOf(min[1], max[1])
        val zs = floatArrayOf(min[2], max[2])
        for (x in xs) {
            for (y in ys) {
                for (z in zs) {
                    val wx = matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12]
                    val wy = matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13]
                    val wz = matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14]
                    minX = minOf(minX, wx)
                    minY = minOf(minY, wy)
                    minZ = minOf(minZ, wz)
                    maxX = maxOf(maxX, wx)
                    maxY = maxOf(maxY, wy)
                    maxZ = maxOf(maxZ, wz)
                }
            }
        }
        return floatArrayOf(minX, minY, minZ) to floatArrayOf(maxX, maxY, maxZ)
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
