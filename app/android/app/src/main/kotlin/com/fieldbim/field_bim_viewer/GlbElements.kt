package com.fieldbim.field_bim_viewer

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import kotlin.math.sqrt

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
            val chain = nodeChain(nodes, parent, i)
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

    /**
     * +1 when the triangles face away from the centre, -1 when they face it.
     * [packed] is nine floats per triangle, in the same space as the centre.
     * A rotation keeps the sign. A mirror flips it.
     */
    fun windingSign(centreX: Float, centreY: Float, centreZ: Float, packed: FloatArray): Float {
        var sum = 0.0
        var area = 0.0
        var index = 0
        while (index + 8 < packed.size) {
            val ax = packed[index].toDouble()
            val ay = packed[index + 1].toDouble()
            val az = packed[index + 2].toDouble()
            val bx = packed[index + 3].toDouble()
            val by = packed[index + 4].toDouble()
            val bz = packed[index + 5].toDouble()
            val cx = packed[index + 6].toDouble()
            val cy = packed[index + 7].toDouble()
            val cz = packed[index + 8].toDouble()
            val abx = bx - ax
            val aby = by - ay
            val abz = bz - az
            val acx = cx - ax
            val acy = cy - ay
            val acz = cz - az
            val nx = aby * acz - abz * acy
            val ny = abz * acx - abx * acz
            val nz = abx * acy - aby * acx
            area += sqrt(nx * nx + ny * ny + nz * nz)
            val vx = (ax + bx + cx) / 3.0 - centreX
            val vy = (ay + by + cy) / 3.0 - centreY
            val vz = (az + bz + cz) / 3.0 - centreZ
            sum += nx * vx + ny * vy + nz * vz
            index += 9
        }
        return if (area < 1e-8 || sum >= 0.0) 1f else -1f
    }

    /** Column-major glTF matrix times a point. */
    fun transformPoint(matrix: FloatArray, x: Float, y: Float, z: Float): FloatArray {
        return floatArrayOf(
            matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12],
            matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13],
            matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14],
        )
    }

    /**
     * Per-element winding in package space. Samples at most 16 triangles from
     * the BIN chunk. +1 is outward, -1 is inward. The viewer's Z-up turn is a
     * rotation, so this sign matches `gl_FrontFacing` after that turn.
     */
    fun frontSigns(file: File): Map<Long, Float> {
        RandomAccessFile(file, "r").use { raf ->
            val header = ByteArray(20)
            if (raf.read(header) != 20) return emptyMap()
            val jsonLen = u32(header, 12)
            if (jsonLen <= 0 || jsonLen > 64 * 1024 * 1024) return emptyMap()
            val jsonBytes = ByteArray(jsonLen)
            raf.readFully(jsonBytes)
            val binHeader = ByteArray(8)
            if (raf.read(binHeader) != 8) return emptyMap()
            val binStart = raf.filePointer
            val root = JSONObject(String(jsonBytes, Charsets.UTF_8))
            val nodes = root.optJSONArray("nodes") ?: return emptyMap()
            val meshes = root.optJSONArray("meshes") ?: return emptyMap()
            val parent = IntArray(nodes.length()) { -1 }
            for (i in 0 until nodes.length()) {
                val children = nodes.optJSONObject(i)?.optJSONArray("children") ?: continue
                for (c in 0 until children.length()) {
                    val child = children.optInt(c, -1)
                    if (child in parent.indices) parent[child] = i
                }
            }
            val found = HashMap<Long, Float>()
            for (i in 0 until nodes.length()) {
                val node = nodes.optJSONObject(i) ?: continue
                val id = elementId(node) ?: continue
                if (!node.has("mesh")) continue
                val mesh = meshes.optJSONObject(node.getInt("mesh")) ?: continue
                val prims = mesh.optJSONArray("primitives") ?: continue
                val chain = nodeChain(nodes, parent, i)
                val centre = centreOf(prims, root, chain) ?: continue
                val packed = sampleTriangles(raf, root, binStart, prims, chain)
                if (packed.size < 9) continue
                found[id] = windingSign(centre[0], centre[1], centre[2], packed)
            }
            return found
        }
    }

    private fun nodeChain(nodes: JSONArray, parent: IntArray, index: Int): List<FloatArray> {
        val chain = ArrayList<FloatArray>()
        var walk = index
        var guard = 0
        while (walk >= 0 && guard++ < 64) {
            val current = nodes.optJSONObject(walk) ?: break
            val matrix = nodeMatrix(current)
            if (matrix != null) chain.add(matrix)
            walk = if (walk < parent.size) parent[walk] else -1
        }
        return chain
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

    private fun centreOf(prims: JSONArray, root: JSONObject, chain: List<FloatArray>): FloatArray? {
        val accessors = root.optJSONArray("accessors") ?: return null
        val bounds = ArrayList<Pair<FloatArray, FloatArray>>()
        for (p in 0 until prims.length()) {
            val prim = prims.optJSONObject(p) ?: continue
            val attrs = prim.optJSONObject("attributes") ?: continue
            if (!attrs.has("POSITION")) continue
            val acc = accessors.optJSONObject(attrs.getInt("POSITION")) ?: continue
            val pMin = vec3(acc.optJSONArray("min")) ?: continue
            val pMax = vec3(acc.optJSONArray("max")) ?: continue
            bounds.add(pMin to pMax)
        }
        val turned = elementBounds(bounds, chain) ?: return null
        return floatArrayOf(
            (turned.first[0] + turned.second[0]) * 0.5f,
            (turned.first[1] + turned.second[1]) * 0.5f,
            (turned.first[2] + turned.second[2]) * 0.5f,
        )
    }

    private class Acc(val base: Long, val stride: Int, val count: Int, val componentType: Int)

    private fun accessor(root: JSONObject, binStart: Long, index: Int): Acc? {
        val accessors = root.optJSONArray("accessors") ?: return null
        val views = root.optJSONArray("bufferViews") ?: return null
        val acc = accessors.optJSONObject(index) ?: return null
        if (!acc.has("bufferView")) return null
        val view = views.optJSONObject(acc.getInt("bufferView")) ?: return null
        val component = acc.optInt("componentType", 0)
        val size = when (component) {
            5120, 5121 -> 1
            5122, 5123 -> 2
            5125, 5126 -> 4
            else -> return null
        }
        val comps = when (acc.optString("type", "")) {
            "VEC3" -> 3
            "SCALAR" -> 1
            else -> return null
        }
        val stride = view.optInt("byteStride", 0).let { if (it > 0) it else size * comps }
        val base = binStart + view.optLong("byteOffset") + acc.optLong("byteOffset")
        return Acc(base, stride, acc.optInt("count", 0), component)
    }

    private fun sampleTriangles(
        raf: RandomAccessFile,
        root: JSONObject,
        binStart: Long,
        prims: JSONArray,
        chain: List<FloatArray>,
    ): FloatArray {
        var triangles = 0
        val counts = IntArray(prims.length())
        val positions = arrayOfNulls<Acc>(prims.length())
        val indices = arrayOfNulls<Acc>(prims.length())
        for (p in 0 until prims.length()) {
            val prim = prims.optJSONObject(p) ?: continue
            val attrs = prim.optJSONObject("attributes") ?: continue
            if (!attrs.has("POSITION")) continue
            val pos = accessor(root, binStart, attrs.getInt("POSITION")) ?: continue
            positions[p] = pos
            if (prim.has("indices")) {
                val ind = accessor(root, binStart, prim.getInt("indices")) ?: continue
                indices[p] = ind
                counts[p] = ind.count / 3
            } else {
                counts[p] = pos.count / 3
            }
            triangles += counts[p]
        }
        if (triangles <= 0) return FloatArray(0)
        val samples = minOf(16, triangles)
        val step = maxOf(1, triangles / samples)
        val out = ArrayList<Float>(samples * 9)
        var seen = 0
        var taken = 0
        for (p in 0 until prims.length()) {
            val pos = positions[p] ?: continue
            val ind = indices[p]
            for (t in 0 until counts[p]) {
                if (seen % step == 0 && taken < samples) {
                    val ids = IntArray(3) { corner ->
                        if (ind == null) {
                            t * 3 + corner
                        } else {
                            readScalar(raf, ind.base + (t * 3L + corner) * ind.stride, ind.componentType)
                        }
                    }
                    if (ids.all { it >= 0 && it < pos.count }) {
                        for (id in ids) {
                            var point = readVec3(raf, pos.base + id.toLong() * pos.stride)
                            for (matrix in chain) {
                                point = transformPoint(matrix, point[0], point[1], point[2])
                            }
                            out.add(point[0])
                            out.add(point[1])
                            out.add(point[2])
                        }
                        taken++
                    }
                }
                seen++
            }
        }
        return out.toFloatArray()
    }

    private fun readScalar(raf: RandomAccessFile, pos: Long, componentType: Int): Int {
        raf.seek(pos)
        return when (componentType) {
            5121 -> raf.readUnsignedByte()
            5123 -> {
                val bytes = ByteArray(2)
                raf.readFully(bytes)
                (bytes[0].toInt() and 0xff) or ((bytes[1].toInt() and 0xff) shl 8)
            }
            5125 -> {
                val bytes = ByteArray(4)
                raf.readFully(bytes)
                u32(bytes, 0)
            }
            else -> -1
        }
    }

    private fun readVec3(raf: RandomAccessFile, pos: Long): FloatArray {
        raf.seek(pos)
        val bytes = ByteArray(12)
        raf.readFully(bytes)
        return floatArrayOf(
            Float.fromBits(u32(bytes, 0)),
            Float.fromBits(u32(bytes, 4)),
            Float.fromBits(u32(bytes, 8)),
        )
    }
}
