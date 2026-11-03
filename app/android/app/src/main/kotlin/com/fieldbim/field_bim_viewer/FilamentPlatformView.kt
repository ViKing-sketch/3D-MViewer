package com.fieldbim.field_bim_viewer

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceView
import com.google.android.filament.Camera
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.Fence
import com.google.android.filament.LightManager
import com.google.android.filament.Material
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.Skybox
import com.google.android.filament.SwapChain
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.android.DisplayHelper
import com.google.android.filament.android.UiHelper
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.Gltfio
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import com.google.android.filament.utils.GestureDetector
import com.google.android.filament.utils.Manipulator
import com.google.android.filament.utils.Utils
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.sqrt

class FilamentViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return FilamentPlatformView(context, messenger, viewId, args)
    }
}

/**
 * Native Filament view for channel `fbv/filament`.
 *
 * Orbit, pan and zoom stay in this view. Flutter sends selection, hide,
 * isolate, X-ray and the framed cameras. The scene is `mesh/lod0.glb`.
 * `mesh/elements/<id>.glb` is loaded when that element is not already in lod0.
 * Picking uses `extras.elementId` on the glTF node.
 */
class FilamentPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    args: Any?,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val surfaceView = SurfaceView(context)
    private val channel = MethodChannel(messenger, "fbv/filament/$viewId")
    private val main = Handler(Looper.getMainLooper())
    private val choreographer = Choreographer.getInstance()
    private val uiHelper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK)
    private val displayHelper = DisplayHelper(context)

    private val engine: Engine
    private val renderer: Renderer
    private val scene: Scene
    private val view: View
    private val camera: Camera
    private val assetLoader: AssetLoader
    private val resourceLoader: ResourceLoader
    private val materialProvider: UbershaderProvider
    private val sun: Int
    private val fill: Int
    private val skybox: Skybox
    private var xrayMaterial: Material? = null
    private var xrayInstance: MaterialInstance? = null
    private var swapChain: SwapChain? = null
    private var manipulator: Manipulator? = null
    private var gesture: GestureDetector? = null

    private val assets = ArrayList<FilamentAsset>()
    private val streams = ArrayList<FileInputStream>()
    private val elementByEntity = HashMap<Int, Long>()
    private val records = HashMap<Long, ElementGeom>()
    private val originals = HashMap<Int, MaterialInstance>()
    private val inScene = HashSet<Int>()
    private val readyRenderables = IntArray(128)
    private val gpuQueue = ArrayList<File>()
    private var activeAsset: FilamentAsset? = null
    private var activeStarted = false

    private var hidden = HashSet<Long>()
    private var isolated = HashSet<Long>()
    private var selected = 0L
    private var xray = false
    private var viewportW = 1
    private var viewportH = 1
    private var near = 0.05
    private var far = 2000.0
    private var frameMin = floatArrayOf(-1f, -1f, -1f)
    private var frameMax = floatArrayOf(1f, 1f, 1f)
    private var preset = "iso"
    private var destroyed = false
    private var framed = false
    private var lastFrame = 0L
    private var downX = 0f
    private var downY = 0f
    private var pointerMoved = false
    private var loadingRoot: String? = null
    private var status: Map<String, Any?> = mapOf("code" to "idle")
    private var reportedReady = false
    private var elementFileCount = 0
    private var sawLod0 = false

    private val frameCallback: Choreographer.FrameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (destroyed) return
            choreographer.postFrameCallback(this)
            render(frameTimeNanos)
        }
    }

    init {
        ensureFilament()
        engine = Engine.create()
        renderer = engine.createRenderer()
        scene = engine.createScene()
        camera = engine.createCamera(EntityManager.get().create())
        camera.setExposure(16f, 1f / 125f, 100f)
        view = engine.createView()
        view.scene = scene
        view.camera = camera
        view.antiAliasing = View.AntiAliasing.FXAA
        materialProvider = UbershaderProvider(engine)
        assetLoader = AssetLoader(engine, materialProvider, EntityManager.get())
        resourceLoader = ResourceLoader(engine, true)
        sun = EntityManager.get().create()
        fill = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1f, 0.98f, 0.95f)
            .intensity(110_000f)
            .direction(0.25f, -1f, -0.35f)
            .castShadows(false)
            .build(engine, sun)
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.75f, 0.82f, 0.95f)
            .intensity(35_000f)
            .direction(-0.45f, -0.15f, 0.75f)
            .castShadows(false)
            .build(engine, fill)
        scene.addEntity(sun)
        scene.addEntity(fill)
        skybox = Skybox.Builder().color(0.83f, 0.87f, 0.91f, 1f).build(engine)
        scene.skybox = skybox
        xrayInstance = loadXray()
        uiHelper.renderCallback = SurfaceCallback()
        uiHelper.attachTo(surfaceView)
        surfaceView.setOnTouchListener { _, event -> onTouch(event) }
        channel.setMethodCallHandler(this)
        choreographer.postFrameCallback(frameCallback)
        val root = (args as? Map<*, *>)?.get("root") as? String
        if (!root.isNullOrEmpty()) load(root)
    }

    override fun getView() = surfaceView

    override fun dispose() {
        if (destroyed) return
        destroyed = true
        choreographer.removeFrameCallback(frameCallback)
        channel.setMethodCallHandler(null)
        uiHelper.detach()
        destroyScene()
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sync" -> result.success(status)
            "load" -> {
                val root = call.argument<String>("root")
                if (!root.isNullOrEmpty()) load(root)
                result.success(null)
            }
            "setViewState" -> {
                selected = (call.argument<Number>("selected"))?.toLong() ?: 0L
                hidden = longSet(call.argument<List<*>>("hidden"))
                isolated = longSet(call.argument<List<*>>("isolated"))
                xray = call.argument<Boolean>("xray") == true
                applyVisibility()
                result.success(null)
            }
            "fit" -> {
                frame(if (call.argument<Boolean>("selected") == true) selectedBox() else allBox(), preset)
                result.success(null)
            }
            "setCamera" -> {
                preset = call.argument<String>("preset") ?: "iso"
                frame(allBox(), preset)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun load(root: String) {
        if (destroyed || loadingRoot == root) return
        loadingRoot = root
        reportedReady = false
        setStatus(mapOf("code" to "loading"))
        Thread {
            try {
                val plan = plan(File(root))
                main.post {
                    if (!destroyed && loadingRoot == root) begin(plan)
                }
            } catch (error: Exception) {
                main.post {
                    if (!destroyed) {
                        setStatus(mapOf("code" to "error", "message" to (error.message ?: "load failed")))
                    }
                }
            }
        }.start()
    }

    private fun plan(root: File): LoadPlan {
        val geoms = HashMap<Long, ElementGeom>()
        val lod0 = File(root, "mesh/lod0.glb")
        val hasLod0 = lod0.isFile
        if (hasLod0) {
            for (geom in GlbElements.parse(GlbElements.readJson(lod0))) geoms[geom.id] = geom
        }
        val elementDir = File(root, "mesh/elements")
        val elementGlbs = elementDir.listFiles { file ->
            file.isFile && file.name.endsWith(".glb")
        }?.sortedBy { it.name } ?: emptyList()
        val gpu = ArrayList<File>()
        if (hasLod0) gpu.add(lod0)
        val covered = HashSet(geoms.keys)
        for (file in elementGlbs) {
            val parsed = try {
                GlbElements.parse(GlbElements.readJson(file))
            } catch (_: Exception) {
                emptyList()
            }
            var missing = false
            for (geom in parsed) {
                if (covered.add(geom.id)) {
                    geoms[geom.id] = geom
                    missing = true
                }
            }
            if (!hasLod0 || missing) gpu.add(file)
        }
        if (gpu.isEmpty()) error("mesh/lod0.glb was not found")
        return LoadPlan(gpu, geoms, hasLod0, elementGlbs.size)
    }

    private fun begin(plan: LoadPlan) {
        clearModels()
        records.clear()
        records.putAll(plan.geoms)
        sawLod0 = plan.lod0
        elementFileCount = plan.elementFiles
        gpuQueue.clear()
        gpuQueue.addAll(plan.files)
        activeAsset = null
        activeStarted = false
        pumpQueue()
    }

    private fun pumpQueue() {
        if (destroyed) return
        if (activeAsset != null && activeStarted) {
            val progress = resourceLoader.asyncGetLoadProgress()
            if (progress < 0.999f && progress < 99.9f) return
            activeAsset = null
            activeStarted = false
        }
        if (gpuQueue.isEmpty()) {
            if (!reportedReady) {
                reportedReady = true
                if (!framed) frame(allBox(), preset)
                applyVisibility()
                setStatus(
                    mapOf(
                        "code" to "ready",
                        "lod0" to sawLod0,
                        "elementFiles" to elementFileCount,
                        "drawn" to elementByEntity.size,
                    ),
                )
            }
            return
        }
        val file = gpuQueue.removeAt(0)
        val asset = openAsset(file)
        if (asset == null) {
            pumpQueue()
            return
        }
        assets.add(asset)
        index(asset)
        rememberBounds(asset)
        resourceLoader.asyncBeginLoad(asset)
        asset.releaseSourceData()
        activeAsset = asset
        activeStarted = true
    }

    private fun openAsset(file: File): FilamentAsset? {
        val input = FileInputStream(file)
        streams.add(input)
        val mapped = input.channel.map(java.nio.channels.FileChannel.MapMode.READ_ONLY, 0, input.channel.size())
        val asset = assetLoader.createAsset(mapped as ByteBuffer)
        if (asset == null) {
            input.close()
            streams.remove(input)
            return null
        }
        return asset
    }

    private fun index(asset: FilamentAsset) {
        for (entity in asset.entities) {
            if (entity == 0 || elementByEntity.containsKey(entity)) continue
            val id = elementId(asset.getExtras(entity)) ?: asset.getName(entity)?.toLongOrNull()
            if (id != null && id != 0L) elementByEntity[entity] = id
        }
    }

    private fun elementId(extras: String?): Long? {
        if (extras.isNullOrBlank()) return null
        return try {
            val obj = JSONObject(extras)
            if (!obj.has("elementId")) null else obj.getLong("elementId")
        } catch (_: Exception) {
            null
        }
    }

    private fun rememberBounds(asset: FilamentAsset) {
        val box = asset.boundingBox
        val center = box.center
        val half = box.halfExtent
        if (!framed && half[0] + half[1] + half[2] > 0f) {
            frameMin = floatArrayOf(center[0] - half[0], center[1] - half[1], center[2] - half[2])
            frameMax = floatArrayOf(center[0] + half[0], center[1] + half[1], center[2] + half[2])
        }
    }

    private fun render(frameTimeNanos: Long) {
        if (destroyed || !uiHelper.isReadyToRender || swapChain == null) return
        val dt = if (lastFrame == 0L) 0f else ((frameTimeNanos - lastFrame) / 1_000_000_000f).coerceIn(0f, 0.1f)
        lastFrame = frameTimeNanos
        manipulator?.update(dt)
        val eye = DoubleArray(3)
        val target = DoubleArray(3)
        val up = DoubleArray(3)
        manipulator?.getLookAt(eye, target, up)
        if (manipulator != null) {
            camera.lookAt(eye[0], eye[1], eye[2], target[0], target[1], target[2], up[0], up[1], up[2])
        }
        resourceLoader.asyncUpdateLoad()
        assetLoader.gc()
        populate()
        pumpQueue()
        if (renderer.beginFrame(swapChain!!, frameTimeNanos)) {
            renderer.render(view)
            renderer.endFrame()
        }
    }

    private fun populate() {
        var added = false
        for (asset in assets) {
            var count = asset.popRenderables(readyRenderables)
            while (count > 0) {
                for (i in 0 until count) indexEntity(asset, readyRenderables[i])
                added = true
                count = asset.popRenderables(readyRenderables)
            }
        }
        if (added) applyVisibility()
    }

    private fun indexEntity(asset: FilamentAsset, entity: Int) {
        if (entity == 0 || elementByEntity.containsKey(entity)) return
        val id = elementId(asset.getExtras(entity)) ?: asset.getName(entity)?.toLongOrNull()
        if (id != null && id != 0L) elementByEntity[entity] = id
    }

    private fun applyVisibility() {
        if (destroyed) return
        val rm = engine.renderableManager
        for ((entity, id) in elementByEntity) {
            val instance = rm.getInstance(entity)
            val show = isVisible(id)
            if (show) {
                if (inScene.add(entity)) scene.addEntity(entity)
            } else if (inScene.remove(entity)) {
                scene.remove(entity)
            }
            if (instance == 0 || !show) continue
            val original = originals.getOrPut(entity) { rm.getMaterialInstanceAt(instance, 0) }
            val ghost = xray && id != selected && xrayInstance != null
            if (ghost) {
                rm.setMaterialInstanceAt(instance, 0, xrayInstance!!)
            } else {
                rm.setMaterialInstanceAt(instance, 0, original)
                val color = if (id == selected) HIGHLIGHT else records[id]?.color
                if (color != null) {
                    try {
                        original.setParameter("baseColorFactor", color[0], color[1], color[2], color[3])
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }

    private fun isVisible(id: Long): Boolean {
        if (hidden.contains(id)) return false
        if (isolated.isNotEmpty() && !isolated.contains(id)) return false
        return true
    }

    private fun frame(box: FloatArray?, cameraPreset: String) {
        val bounds = box ?: return
        frameMin = bounds.copyOfRange(0, 3)
        frameMax = bounds.copyOfRange(3, 6)
        val cx = (frameMin[0] + frameMax[0]) * 0.5f
        val cy = (frameMin[1] + frameMax[1]) * 0.5f
        val cz = (frameMin[2] + frameMax[2]) * 0.5f
        val hx = (frameMax[0] - frameMin[0]) * 0.5f
        val hy = (frameMax[1] - frameMin[1]) * 0.5f
        val hz = (frameMax[2] - frameMin[2]) * 0.5f
        val radius = max(0.5f, max(hx, max(hy, hz)))
        val distance = radius * 2.8f
        val dir = when (cameraPreset) {
            "front" -> floatArrayOf(0f, 0f, 1f)
            "back" -> floatArrayOf(0f, 0f, -1f)
            "left" -> floatArrayOf(-1f, 0f, 0f)
            "right" -> floatArrayOf(1f, 0f, 0f)
            "top" -> floatArrayOf(0f, 1f, 0.04f)
            "bottom" -> floatArrayOf(0f, -1f, 0.04f)
            else -> floatArrayOf(0.75f, 0.55f, 0.85f)
        }
        val len = sqrt(dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2])
        val eye = floatArrayOf(cx + dir[0] / len * distance, cy + dir[1] / len * distance, cz + dir[2] / len * distance)
        near = max(0.02, radius / 200.0)
        far = max(distance.toDouble() * 40.0, 1000.0)
        manipulator = Manipulator.Builder()
            .viewport(viewportW.coerceAtLeast(1), viewportH.coerceAtLeast(1))
            .targetPosition(cx, cy, cz)
            .orbitHomePosition(eye[0], eye[1], eye[2])
            .build(Manipulator.Mode.ORBIT)
        gesture = GestureDetector(surfaceView, manipulator!!)
        framed = true
        updateProjection()
    }

    private fun allBox(): FloatArray? {
        if (records.isEmpty()) {
            return floatArrayOf(frameMin[0], frameMin[1], frameMin[2], frameMax[0], frameMax[1], frameMax[2])
        }
        var minX = Float.POSITIVE_INFINITY
        var minY = Float.POSITIVE_INFINITY
        var minZ = Float.POSITIVE_INFINITY
        var maxX = Float.NEGATIVE_INFINITY
        var maxY = Float.NEGATIVE_INFINITY
        var maxZ = Float.NEGATIVE_INFINITY
        for (geom in records.values) {
            minX = minOf(minX, geom.min[0]); minY = minOf(minY, geom.min[1]); minZ = minOf(minZ, geom.min[2])
            maxX = maxOf(maxX, geom.max[0]); maxY = maxOf(maxY, geom.max[1]); maxZ = maxOf(maxZ, geom.max[2])
        }
        if (minX == Float.POSITIVE_INFINITY) return null
        return floatArrayOf(minX, minY, minZ, maxX, maxY, maxZ)
    }

    private fun selectedBox(): FloatArray? {
        val geom = records[selected] ?: return allBox()
        return floatArrayOf(geom.min[0], geom.min[1], geom.min[2], geom.max[0], geom.max[1], geom.max[2])
    }

    private fun updateProjection() {
        if (viewportW <= 0 || viewportH <= 0) return
        val aspect = viewportW.toDouble() / viewportH.toDouble()
        camera.setProjection(45.0, aspect, near, far, Camera.Fov.VERTICAL)
    }

    private fun onTouch(event: MotionEvent): Boolean {
        gesture?.onTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                pointerMoved = false
            }
            MotionEvent.ACTION_POINTER_DOWN -> pointerMoved = true
            MotionEvent.ACTION_MOVE -> {
                val dx = event.x - downX
                val dy = event.y - downY
                if (dx * dx + dy * dy > 18f * 18f) pointerMoved = true
            }
            MotionEvent.ACTION_UP -> if (!pointerMoved) pick(event.x, event.y)
        }
        return true
    }

    private fun pick(x: Float, y: Float) {
        if (viewportW <= 1 || viewportH <= 1) return
        val px = x.toInt().coerceIn(0, viewportW - 1)
        val py = (viewportH - y.toInt()).coerceIn(0, viewportH - 1)
        view.pick(px, py, main, View.OnPickCallback { result ->
            if (destroyed) return@OnPickCallback
            val id = elementByEntity[result.renderable] ?: 0L
            try {
                channel.invokeMethod("onPick", mapOf("elementId" to id))
            } catch (_: Exception) {
            }
        })
    }

    private fun loadXray(): MaterialInstance? {
        return try {
            val bytes = context.assets.open("materials/xray.filamat").use { it.readBytes() }
            val buffer = ByteBuffer.allocateDirect(bytes.size)
            buffer.put(bytes)
            buffer.flip()
            val material = Material.Builder().payload(buffer, buffer.remaining()).build(engine)
            xrayMaterial = material
            material.createInstance().apply {
                setParameter("baseColor", 0.62f, 0.76f, 0.9f, 0.22f)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun setStatus(value: Map<String, Any?>) {
        status = value
        try {
            channel.invokeMethod("onStatus", value)
        } catch (_: Exception) {
        }
    }

    private fun clearModels() {
        for (asset in assets) {
            scene.removeEntities(asset.entities)
            assetLoader.destroyAsset(asset)
        }
        assets.clear()
        for (stream in streams) {
            try {
                stream.close()
            } catch (_: Exception) {
            }
        }
        streams.clear()
        elementByEntity.clear()
        originals.clear()
        inScene.clear()
        framed = false
    }

    private fun destroyScene() {
        try {
            clearModels()
            xrayInstance = null
            xrayMaterial?.let { engine.destroyMaterial(it) }
            engine.destroySkybox(skybox)
            engine.destroyEntity(sun)
            engine.destroyEntity(fill)
            assetLoader.destroy()
            materialProvider.destroyMaterials()
            materialProvider.destroy()
            resourceLoader.destroy()
            swapChain?.let { engine.destroySwapChain(it) }
            engine.destroyRenderer(renderer)
            engine.destroyView(view)
            engine.destroyScene(scene)
            engine.destroyCameraComponent(camera.entity)
            EntityManager.get().destroy(camera.entity)
            EntityManager.get().destroy(sun)
            EntityManager.get().destroy(fill)
            engine.destroy()
        } catch (_: Exception) {
        }
    }

    private fun longSet(values: List<*>?): HashSet<Long> {
        val out = HashSet<Long>()
        values?.forEach { if (it is Number) out.add(it.toLong()) }
        return out
    }

    private inner class SurfaceCallback : UiHelper.RendererCallback {
        override fun onNativeWindowChanged(surface: Surface) {
            if (destroyed) return
            swapChain?.let { engine.destroySwapChain(it) }
            swapChain = engine.createSwapChain(surface)
            surfaceView.display?.let { displayHelper.attach(renderer, it) }
        }

        override fun onDetachedFromSurface() {
            displayHelper.detach()
            swapChain?.let {
                engine.destroySwapChain(it)
                engine.flushAndWait()
                swapChain = null
            }
        }

        override fun onResized(width: Int, height: Int) {
            viewportW = width.coerceAtLeast(1)
            viewportH = height.coerceAtLeast(1)
            view.viewport = Viewport(0, 0, viewportW, viewportH)
            manipulator?.setViewport(viewportW, viewportH)
            updateProjection()
            if (!destroyed) {
                val fence = engine.createFence()
                fence.wait(Fence.Mode.FLUSH, Fence.WAIT_FOR_EVER)
                engine.destroyFence(fence)
            }
        }
    }

    companion object {
        private val HIGHLIGHT = floatArrayOf(1f, 0.45f, 0.08f, 1f)
        private var ready = false

        fun ensureFilament() {
            if (ready) return
            Utils.init()
            Gltfio.init()
            ready = true
        }
    }
}

private data class LoadPlan(
    val files: List<File>,
    val geoms: Map<Long, ElementGeom>,
    val lod0: Boolean,
    val elementFiles: Int,
)
