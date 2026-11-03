package com.fieldbim.field_bim_viewer

import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Choreographer
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceView
import com.google.android.filament.Camera
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.Fence
import com.google.android.filament.IndirectLight
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
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
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
 * isolate, X-ray and the framed cameras. Package meshes are Z-up; each asset
 * root is turned to Filament Y-up. `mesh/lod0.glb` loads when it fits the
 * source-byte budget. A larger lod0 becomes element GLBs (smallest first)
 * plus box proxies, and selecting a deferred element streams its file.
 * Ready is reported only after [begin]. Picking uses `extras.elementId`.
 *
 * The engine lives on the `FbvFilament` thread. A large scene shows clamped
 * box proxies first, then uploads one GLB per frame. Closing the model
 * unmaps files and destroys the assets before the page pops.
 */
class FilamentPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    args: Any?,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val surfaceView = SurfaceView(context).apply {
        isFocusable = false
        isFocusableInTouchMode = false
    }
    private val channel = MethodChannel(messenger, "fbv/filament/$viewId")
    private val renderThread = HandlerThread("FbvFilament").apply { start() }
    private val renderHandler = Handler(renderThread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val generation = AtomicInteger(0)
    private val choreographer = Choreographer.getInstance()
    private val uiHelper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK)
    private val displayHelper = DisplayHelper(context)
    private val frameQueued = AtomicBoolean(false)

    private lateinit var engine: Engine
    private lateinit var renderer: Renderer
    private lateinit var scene: Scene
    private lateinit var view: View
    private lateinit var camera: Camera
    private lateinit var assetLoader: AssetLoader
    private lateinit var resourceLoader: ResourceLoader
    private lateinit var materialProvider: UbershaderProvider
    private var sun: Int = 0
    private var fill: Int = 0
    private lateinit var indirect: IndirectLight
    private lateinit var skybox: Skybox
    private var engineAlive = false
    private var xrayMaterial: Material? = null
    private var xrayInstance: MaterialInstance? = null
    private var swapChain: SwapChain? = null
    private var manipulator: Manipulator? = null
    private var gesture: GestureDetector? = null

    private val assets = ArrayList<FilamentAsset>()
    private val proxyAssets = HashSet<FilamentAsset>()
    private val previewAssets = HashSet<FilamentAsset>()
    private val proxyEntities = HashSet<Int>()
    private val bufferQueue = ArrayList<PendingGlb>()
    private val tinted = HashMap<Int, MaterialInstance>()
    private val streams = ArrayList<FileInputStream>()
    private val mappedBuffers = ArrayList<MappedByteBuffer>()
    private val elementByEntity = HashMap<Int, Long>()
    private val records = HashMap<Long, ElementGeom>()
    private val originals = HashMap<Int, MaterialInstance>()
    private val inScene = HashSet<Int>()
    private val readyRenderables = IntArray(128)
    private val gpuQueue = ArrayList<File>()
    private var activeAsset: FilamentAsset? = null
    private var activeStarted = false
    private var activeMapped: MappedByteBuffer? = null
    private var activeStream: FileInputStream? = null
    private var beginTicket = 0

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
    @Volatile private var loadingRoot: String? = null
    @Volatile private var status: Map<String, Any?> = mapOf("code" to "idle")
    private var reportedReady = false
    private var sceneArmed = false
    private var elementFileCount = 0
    private var sawLod0 = false
    private var partialScene = false
    private var boxCount = 0
    private var budgetBytes = 96L * 1024 * 1024
    private val deferred = HashMap<Long, File>()
    private val retainedBuffers = ArrayList<ByteBuffer>()
    private val standInIds = HashSet<Long>()
    private var uploadsDone = 0
    private var uploadsTotal = 0
    private var lastUploadLog = 0L

    private val frameCallback: Choreographer.FrameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (destroyed) return
            choreographer.postFrameCallback(this)
            if (!frameQueued.compareAndSet(false, true)) return
            renderHandler.post {
                frameQueued.set(false)
                render(frameTimeNanos)
            }
        }
    }

    init {
        ensureFilament()
        val ready = CountDownLatch(1)
        var failure: Throwable? = null
        renderHandler.post {
            try {
                createGpu()
            } catch (error: Throwable) {
                failure = error
            } finally {
                ready.countDown()
            }
        }
        if (!ready.await(15, TimeUnit.SECONDS)) error("Filament engine was not created")
        failure?.let { throw it }
        uiHelper.renderCallback = SurfaceCallback()
        uiHelper.attachTo(surfaceView)
        surfaceView.setOnTouchListener { _, event ->
            val copy = MotionEvent.obtain(event)
            renderHandler.post {
                try {
                    onTouch(copy)
                } finally {
                    copy.recycle()
                }
            }
            true
        }
        channel.setMethodCallHandler(this)
        choreographer.postFrameCallback(frameCallback)
        val root = (args as? Map<*, *>)?.get("root") as? String
        if (!root.isNullOrEmpty()) load(root)
    }

    override fun getView() = surfaceView

    private fun createGpu() {
        val config = Engine.Config()
        config.driverHandleArenaSizeMB = 32L
        config.perRenderPassArenaSizeMB = 16L
        config.perFrameCommandsSizeMB = 8L
        config.commandBufferSizeMB = 12L
        config.minCommandBufferSizeMB = 2L
        engine = Engine.Builder().config(config).build()
        engineAlive = true
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
        // Constant SH so doubleSided back faces are not pure black under the two directionals.
        indirect = IndirectLight.Builder()
            .irradiance(1, floatArrayOf(0.2f, 0.2f, 0.22f))
            .intensity(20_000f)
            .build(engine)
        scene.indirectLight = indirect
        skybox = Skybox.Builder().color(0.83f, 0.87f, 0.91f, 1f).build(engine)
        scene.skybox = skybox
        xrayInstance = loadXray()
    }

    override fun dispose() {
        if (destroyed) return
        destroyed = true
        generation.incrementAndGet()
        choreographer.removeFrameCallback(frameCallback)
        channel.setMethodCallHandler(null)
        surfaceView.setOnTouchListener(null)
        uiHelper.detach()
        renderHandler.post {
            try {
                destroyScene()
            } finally {
                renderThread.quitSafely()
            }
        }
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sync" -> result.success(status)
            "load" -> {
                val root = call.argument<String>("root")
                if (!root.isNullOrEmpty()) load(root)
                result.success(null)
            }
            "release" -> releaseScene(result)
            "setViewState" -> {
                val nextSelected = (call.argument<Number>("selected"))?.toLong() ?: 0L
                val nextHidden = longSet(call.argument<List<*>>("hidden"))
                val nextIsolated = longSet(call.argument<List<*>>("isolated"))
                val nextXray = call.argument<Boolean>("xray") == true
                val frameSelected = call.argument<Boolean>("frame") == true
                renderHandler.post {
                    if (destroyed) return@post
                    selected = nextSelected
                    hidden = nextHidden
                    isolated = nextIsolated
                    xray = nextXray
                    ensureSelected(selected)
                    applyVisibility()
                    if (frameSelected && selected != 0L) frame(selectedBox(), preset)
                    if (sceneArmed) pumpQueue()
                }
                result.success(null)
            }
            "fit" -> {
                val selectedFit = call.argument<Boolean>("selected") == true
                renderHandler.post {
                    if (destroyed) return@post
                    frame(if (selectedFit) selectedBox() else allBox(), preset)
                }
                result.success(null)
            }
            "setCamera" -> {
                val next = call.argument<String>("preset") ?: "iso"
                renderHandler.post {
                    if (destroyed) return@post
                    preset = next
                    frame(allBox(), preset)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun releaseScene(result: MethodChannel.Result) {
        generation.incrementAndGet()
        loadingRoot = null
        Log.i(TAG, "cancel requested")
        renderHandler.post {
            try {
                sceneArmed = false
                reportedReady = false
                gpuQueue.clear()
                if (!destroyed) clearModels()
            } finally {
                mainHandler.post {
                    try {
                        result.success(null)
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }

    private fun load(root: String) {
        if (destroyed || loadingRoot == root) return
        loadingRoot = root
        val ticket = generation.incrementAndGet()
        setStatus(mapOf("code" to "loading", "loaded" to 0, "total" to 0))
        renderHandler.post {
            if (ticket != generation.get() || destroyed) return@post
            sceneArmed = false
            reportedReady = false
            clearModels()
        }
        Thread {
            try {
                val plan = plan(File(root))
                renderHandler.post {
                    if (!destroyed && ticket == generation.get() && loadingRoot == root) begin(plan)
                }
            } catch (error: Exception) {
                renderHandler.post {
                    if (!destroyed && ticket == generation.get()) {
                        setStatus(mapOf("code" to "error", "message" to (error.message ?: "load failed")))
                    }
                }
            }
        }.start()
    }

    private fun deviceBudget(): Long {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return 96L * 1024 * 1024
        val info = ActivityManager.MemoryInfo()
        am.getMemoryInfo(info)
        val threeGiB = 3L * 1024 * 1024 * 1024
        return if (info.totalMem <= threeGiB) 96L * 1024 * 1024 else 256L * 1024 * 1024
    }

    private fun plan(root: File): LoadPlan {
        val budget = deviceBudget()
        val lod0 = File(root, "mesh/lod0.glb")
        val lod0Bytes = if (lod0.isFile) lod0.length() else 0L
        val useLod0 = lod0.isFile && lod0Bytes <= budget
        val geomsZ = HashMap<Long, ElementGeom>()
        val geomsU = HashMap<Long, ElementGeom>()
        val lod0Ids = HashSet<Long>()
        if (lod0.isFile) {
            for (geom in readGeoms(lod0)) {
                geomsZ[geom.id] = geom
                geomsU[geom.id] = geom.upright()
                lod0Ids.add(geom.id)
            }
        }
        val elementDir = File(root, "mesh/elements")
        val elementGlbs = elementDir.listFiles { file ->
            file.isFile && file.name.endsWith(".glb")
        }?.toList() ?: emptyList()
        val elems = ArrayList<ElementFile>()
        for (file in elementGlbs) {
            val parsed = readGeoms(file)
            for (geom in parsed) {
                geomsZ[geom.id] = geom
                geomsU[geom.id] = geom.upright()
            }
            elems.add(ElementFile(file, parsed))
        }
        val gpu = ArrayList<File>()
        val deferredFiles = HashMap<Long, File>()
        val proxyIds = LinkedHashSet<Long>()
        var used = 0L
        if (useLod0) {
            gpu.add(lod0)
            used = lod0Bytes
            val covered = HashSet(lod0Ids)
            for (elem in elems.sortedBy { it.file.length() }) {
                val missing = elem.geoms.filter { it.id !in covered }
                if (missing.isEmpty()) continue
                if (elem.file.length() <= budget && used + elem.file.length() <= budget) {
                    gpu.add(elem.file)
                    used += elem.file.length()
                    missing.forEach { covered.add(it.id) }
                } else {
                    for (geom in missing) {
                        deferredFiles[geom.id] = elem.file
                        proxyIds.add(geom.id)
                    }
                }
            }
        } else {
            val covered = HashSet<Long>()
            for (elem in elems.sortedBy { it.file.length() }) {
                if (elem.geoms.isEmpty()) continue
                if (elem.file.length() <= budget && used + elem.file.length() <= budget) {
                    gpu.add(elem.file)
                    used += elem.file.length()
                    elem.geoms.forEach { covered.add(it.id) }
                } else {
                    for (geom in elem.geoms) {
                        if (covered.add(geom.id)) {
                            deferredFiles[geom.id] = elem.file
                            proxyIds.add(geom.id)
                        }
                    }
                }
            }
            for (id in geomsZ.keys) {
                if (id !in covered && id !in deferredFiles) proxyIds.add(id)
            }
        }
        val standIn = proxyIds.toSet()
        val span = SceneBounds.span(SceneBounds.union(geomsZ.values, standIn))
        for (id in standIn) {
            val geom = geomsZ[id] ?: continue
            val clamped = SceneBounds.clamp(geom, span)
            geomsZ[id] = clamped
            geomsU[id] = clamped.upright()
        }
        val heavy = geomsZ.size > 80 || (lod0.isFile && lod0Bytes >= 8L * 1024 * 1024)
        val previewGeoms = ArrayList<ElementGeom>()
        if (heavy) {
            for (geom in geomsZ.values) {
                if (geom.id !in standIn) previewGeoms.add(geom)
            }
        }
        val standGeoms = ArrayList<ElementGeom>()
        for (id in standIn) {
            val geom = geomsZ[id] ?: continue
            standGeoms.add(geom)
        }
        val preview = ProxyBoxes.build(previewGeoms)
        val proxy = ProxyBoxes.build(standGeoms)
        val partial = (lod0.isFile && !useLod0) || standIn.isNotEmpty()
        if (gpu.isEmpty() && proxy == null && preview == null) error("mesh/lod0.glb was not found")
        Log.i(
            TAG,
            "plan lod0=$useLod0 files=${gpu.size} standIns=${standIn.size} " +
                "fitSpan=$span preview=${previewGeoms.size}",
        )
        return LoadPlan(
            gpu,
            geomsU,
            useLod0,
            elementGlbs.size,
            partial,
            standIn.size,
            budget,
            deferredFiles,
            proxy,
            preview,
            standIn,
        )
    }

    private fun readGeoms(file: File): List<ElementGeom> {
        return try {
            GlbElements.parse(GlbElements.readJson(file))
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun begin(plan: LoadPlan) {
        beginTicket = generation.get()
        clearModels()
        records.putAll(plan.geoms)
        standInIds.addAll(plan.standIn)
        sawLod0 = plan.lod0
        elementFileCount = plan.elementFiles
        partialScene = plan.partial
        boxCount = plan.boxes
        budgetBytes = plan.budget
        deferred.clear()
        deferred.putAll(plan.deferred)
        gpuQueue.clear()
        gpuQueue.addAll(plan.files)
        uploadsDone = 0
        uploadsTotal = plan.files.size
        lastUploadLog = 0L
        activeAsset = null
        activeStarted = false
        bufferQueue.clear()
        plan.preview?.let { bufferQueue.add(PendingGlb(it.buffer, preview = true)) }
        plan.proxy?.let { bufferQueue.add(PendingGlb(it.buffer, preview = false)) }
        sceneArmed = true
        val fit = SceneBounds.union(records.values, standInIds)
        if (fit != null) {
            Log.i(
                TAG,
                "fit min=${fit[0]},${fit[1]},${fit[2]} max=${fit[3]},${fit[4]},${fit[5]} " +
                    "elements=${records.size} standIns=${standInIds.size}",
            )
        } else {
            Log.i(TAG, "fit empty elements=${records.size} standIns=${standInIds.size}")
        }
        frame(fit, preset)
        plan.preview?.let { retainedBuffers.add(it.buffer) }
        plan.proxy?.let { retainedBuffers.add(it.buffer) }
        reportProgress()
        pumpQueue()
    }

    private fun pumpQueue() {
        if (destroyed || !sceneArmed || generation.get() != beginTicket) return
        if (activeAsset != null && activeStarted) {
            val progress = resourceLoader.asyncGetLoadProgress()
            if (progress < 0.999f && progress < 99.9f) return
            finishActive()
        }
        if (gpuQueue.isEmpty()) {
            if (!reportedReady) ensureSelected(selected)
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
                            "partial" to partialScene,
                            "boxes" to boxCount,
                            "budget" to budgetBytes,
                            "standIns" to pendingStandIns(),
                        ),
                    )
                    Log.i(
                        TAG,
                        "upload finished files=$uploadsDone total=$uploadsTotal " +
                            "standIns=${pendingStandIns().size} partial=$partialScene",
                    )
                }
                return
            }
        }
        if (destroyed || !sceneArmed || generation.get() != beginTicket) return
        if (bufferQueue.isNotEmpty()) {
            val pending = bufferQueue.removeAt(0)
            val asset = openBuffer(pending.buffer)
            if (asset != null) startLoad(asset, proxy = true, preview = pending.preview)
            return
        }
        val file = gpuQueue.removeAt(0)
        val asset = openAsset(file)
        if (asset == null) {
            pumpQueue()
            return
        }
        if (!startLoad(asset, proxy = false)) {
            finishActive()
            return
        }
        uploadsDone += 1
        if (uploadsDone == 1 || uploadsDone == uploadsTotal || uploadsDone % 8 == 0) reportProgress()
    }

    private fun reportProgress() {
        if (reportedReady) return
        setStatus(
            mapOf(
                "code" to "loading",
                "loaded" to uploadsDone,
                "total" to uploadsTotal,
                "partial" to partialScene,
                "boxes" to boxCount,
                "standIns" to pendingStandIns(),
            ),
        )
    }

    private fun pendingStandIns(): List<Long> {
        return standInIds.filter { deferred.containsKey(it) }.sorted()
    }

    private fun startLoad(asset: FilamentAsset, proxy: Boolean, preview: Boolean = false): Boolean {
        if (destroyed || !sceneArmed || generation.get() != beginTicket) {
            try {
                assetLoader.destroyAsset(asset)
            } catch (_: Exception) {
            }
            return false
        }
        if (proxy) proxyAssets.add(asset)
        if (preview) previewAssets.add(asset)
        assets.add(asset)
        applyRootTurn(asset)
        index(asset)
        rememberBounds(asset)
        val started = try {
            resourceLoader.asyncBeginLoad(asset)
        } catch (error: Exception) {
            Log.w(TAG, "asyncBeginLoad failed: ${error.message}")
            false
        }
        asset.releaseSourceData()
        if (!started) {
            Log.w(TAG, "asyncBeginLoad returned false")
            activeAsset = null
            activeStarted = false
            return true
        }
        activeAsset = asset
        activeStarted = true
        return true
    }

    private fun applyRootTurn(asset: FilamentAsset) {
        val instance = engine.transformManager.getInstance(asset.root)
        if (instance != 0) engine.transformManager.setTransform(instance, Z_TO_Y)
    }

    private fun ensureSelected(id: Long) {
        if (id == 0L || destroyed || !sceneArmed) return
        val file = deferred[id] ?: return
        if (file.length() > 128L * 1024 * 1024) {
            Log.i(TAG, "stream skipped element=$id bytes=${file.length()}")
            return
        }
        val ids = deferred.filterValues { it == file }.keys.toList()
        ids.forEach { deferred.remove(it) }
        Log.i(TAG, "stream element=$id file=${file.name} bytes=${file.length()}")
        setStatus(
            mapOf(
                "code" to if (reportedReady) "ready" else "loading",
                "lod0" to sawLod0,
                "elementFiles" to elementFileCount,
                "drawn" to elementByEntity.size,
                "partial" to partialScene,
                "boxes" to boxCount,
                "budget" to budgetBytes,
                "lastStreamed" to id,
                "loaded" to uploadsDone,
                "total" to uploadsTotal,
                "standIns" to pendingStandIns(),
            ),
        )
        val drop = elementByEntity.filterValues { it in ids }.keys.toList()
        for (entity in drop) {
            if (inScene.remove(entity)) scene.remove(entity)
            elementByEntity.remove(entity)
            originals.remove(entity)
        }
        if (file !in gpuQueue) gpuQueue.add(file)
    }

    private fun openAsset(file: File): FilamentAsset? {
        val input = FileInputStream(file)
        streams.add(input)
        val mapped = input.channel.map(java.nio.channels.FileChannel.MapMode.READ_ONLY, 0, input.channel.size())
        mappedBuffers.add(mapped)
        activeStream = input
        activeMapped = mapped
        val asset = try {
            assetLoader.createAsset(mapped)
        } catch (error: Exception) {
            Log.w(TAG, "createAsset failed: ${error.message}")
            null
        }
        if (asset == null) {
            mappedBuffers.remove(mapped)
            unmap(mapped)
            if (activeMapped === mapped) activeMapped = null
            try {
                input.close()
            } catch (_: Exception) {
            }
            streams.remove(input)
            if (activeStream === input) activeStream = null
            return null
        }
        return asset
    }

    private fun finishActive() {
        activeAsset?.let { applyRootTurn(it) }
        activeAsset = null
        activeStarted = false
        val mapped = activeMapped
        activeMapped = null
        if (mapped != null) {
            mappedBuffers.remove(mapped)
            unmap(mapped)
        }
        val stream = activeStream
        activeStream = null
        if (stream != null) {
            streams.remove(stream)
            try {
                stream.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun unmap(buffer: ByteBuffer) {
        if (buffer !is MappedByteBuffer) return
        try {
            val method = Class.forName("sun.nio.ch.FileChannelImpl")
                .getDeclaredMethod("unmap", MappedByteBuffer::class.java)
            method.isAccessible = true
            method.invoke(null, buffer)
            return
        } catch (_: Throwable) {
        }
        try {
            val unsafeClass = Class.forName("sun.misc.Unsafe")
            val field = unsafeClass.getDeclaredField("theUnsafe")
            field.isAccessible = true
            val unsafe = field.get(null)
            unsafeClass.getMethod("invokeCleaner", ByteBuffer::class.java).invoke(unsafe, buffer)
            return
        } catch (_: Throwable) {
        }
        try {
            val cleaner = buffer.javaClass.getMethod("cleaner").invoke(buffer) ?: return
            cleaner.javaClass.getMethod("clean").invoke(cleaner)
        } catch (_: Throwable) {
        }
    }

    private fun openBuffer(buffer: ByteBuffer): FilamentAsset? {
        buffer.order(ByteOrder.LITTLE_ENDIAN)
        buffer.position(0)
        return assetLoader.createAsset(buffer)
    }

    private fun index(asset: FilamentAsset) {
        val found = ArrayList<Long>()
        val proxy = asset in proxyAssets
        for (entity in asset.entities) {
            if (entity == 0 || elementByEntity.containsKey(entity)) continue
            val id = elementId(asset.getExtras(entity)) ?: asset.getName(entity)?.toLongOrNull()
            if (id != null && id != 0L) {
                elementByEntity[entity] = id
                if (proxy) proxyEntities.add(entity) else found.add(id)
            }
        }
        if (!proxy) retireProxies(found)
        releaseRetiredProxies()
    }

    /** Drop preview boxes once their elements have a real mesh. Stand-ins stay. */
    private fun releaseRetiredProxies() {
        if (!engineAlive || previewAssets.isEmpty()) return
        val drop = ArrayList<FilamentAsset>()
        for (asset in previewAssets) {
            if (asset == activeAsset) continue
            val still = asset.entities.any { it != 0 && it in proxyEntities }
            if (!still) drop.add(asset)
        }
        if (drop.isEmpty()) return
        for (asset in drop) {
            assets.remove(asset)
            proxyAssets.remove(asset)
            previewAssets.remove(asset)
            try {
                scene.removeEntities(asset.entities)
                assetLoader.destroyAsset(asset)
            } catch (_: Exception) {
            }
        }
        Log.i(TAG, "released preview proxies=${drop.size}")
    }

    private fun retireProxies(ids: Collection<Long>) {
        if (ids.isEmpty() || proxyEntities.isEmpty()) return
        val wanted = ids.toHashSet()
        val drop = ArrayList<Int>()
        for ((entity, id) in elementByEntity) {
            if (entity in proxyEntities && id in wanted) drop.add(entity)
        }
        for (entity in drop) {
            if (inScene.remove(entity)) scene.remove(entity)
            elementByEntity.remove(entity)
            originals.remove(entity)
            proxyEntities.remove(entity)
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
            val minX = center[0] - half[0]
            val minY = center[1] - half[1]
            val minZ = center[2] - half[2]
            val maxX = center[0] + half[0]
            val maxY = center[1] + half[1]
            val maxZ = center[2] + half[2]
            frameMin = floatArrayOf(minX, minZ, -maxY)
            frameMax = floatArrayOf(maxX, maxZ, -minY)
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
        logUploadHeartbeat(frameTimeNanos)
        if (renderer.beginFrame(swapChain!!, frameTimeNanos)) {
            renderer.render(view)
            renderer.endFrame()
        }
    }

    private fun populate() {
        val snapshot = assets.toList()
        var added = false
        for (asset in snapshot) {
            if (asset !in assets) continue
            val count = asset.popRenderables(readyRenderables)
            if (count <= 0) continue
            for (i in 0 until count) indexEntity(asset, readyRenderables[i])
            added = true
            break
        }
        if (added) applyVisibility()
        releaseRetiredProxies()
    }

    private fun indexEntity(asset: FilamentAsset, entity: Int) {
        if (entity == 0 || elementByEntity.containsKey(entity)) return
        val id = elementId(asset.getExtras(entity)) ?: asset.getName(entity)?.toLongOrNull()
        if (id != null && id != 0L) {
            elementByEntity[entity] = id
            if (asset in proxyAssets) proxyEntities.add(entity) else retireProxies(listOf(id))
        }
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
            val standIn = id in standInIds && deferred.containsKey(id)
            if (ghost) {
                rm.setMaterialInstanceAt(instance, 0, xrayInstance!!)
            } else if (id == selected || standIn) {
                val color = if (id == selected) HIGHLIGHT else STAND_IN
                val painted = paintCopy(entity, original)
                rm.setMaterialInstanceAt(instance, 0, painted)
                try {
                    painted.setParameter("baseColorFactor", color[0], color[1], color[2], color[3])
                } catch (_: Exception) {
                }
            } else {
                rm.setMaterialInstanceAt(instance, 0, original)
                val color = records[id]?.color
                if (color != null) {
                    try {
                        original.setParameter("baseColorFactor", color[0], color[1], color[2], color[3])
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }

    private fun paintCopy(entity: Int, original: MaterialInstance): MaterialInstance {
        tinted[entity]?.let { return it }
        return try {
            original.material.createInstance().also { tinted[entity] = it }
        } catch (_: Exception) {
            original
        }
    }

    private fun logUploadHeartbeat(frameTimeNanos: Long) {
        if (!sceneArmed || reportedReady || destroyed) return
        if (lastUploadLog != 0L && frameTimeNanos - lastUploadLog < 2_000_000_000L) return
        lastUploadLog = frameTimeNanos
        val progress = if (activeStarted) {
            try {
                resourceLoader.asyncGetLoadProgress()
            } catch (_: Exception) {
                -1f
            }
        } else {
            -1f
        }
        Log.i(
            TAG,
            "upload loaded=$uploadsDone total=$uploadsTotal progress=$progress " +
                "queue=${gpuQueue.size + bufferQueue.size}",
        )
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
        return SceneBounds.union(records.values, standInIds)
            ?: floatArrayOf(frameMin[0], frameMin[1], frameMin[2], frameMax[0], frameMax[1], frameMax[2])
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
        if (!engineAlive || destroyed) return true
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
        val vp = view.viewport
        val width = if (vp.width > 1) vp.width else viewportW
        val height = if (vp.height > 1) vp.height else viewportH
        if (width <= 1 || height <= 1) return
        val px = (vp.left + x.toInt()).coerceIn(vp.left, vp.left + width - 1)
        val py = (vp.bottom + height - y.toInt()).coerceIn(vp.bottom, vp.bottom + height - 1)
        view.pick(px, py, renderHandler, View.OnPickCallback { result ->
            if (destroyed) return@OnPickCallback
            val id = elementByEntity[result.renderable] ?: 0L
            if (id != 0L && deferred.containsKey(id)) {
                ensureSelected(id)
                if (sceneArmed) pumpQueue()
            }
            mainHandler.post {
                try {
                    channel.invokeMethod("onPick", mapOf("elementId" to id))
                } catch (_: Exception) {
                }
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
        mainHandler.post {
            try {
                channel.invokeMethod("onStatus", value)
            } catch (_: Exception) {
            }
        }
    }

    private fun clearModels() {
        if (!engineAlive) return
        val assetCount = assets.size
        val mapCount = mappedBuffers.size
        try {
            resourceLoader.asyncCancelLoad()
        } catch (_: Exception) {
        }
        activeAsset = null
        activeStarted = false
        gpuQueue.clear()
        bufferQueue.clear()
        previewAssets.clear()
        val rm = engine.renderableManager
        if (xrayInstance != null) {
            for ((entity, original) in originals) {
                val inst = rm.getInstance(entity)
                if (inst == 0) continue
                try {
                    rm.setMaterialInstanceAt(inst, 0, original)
                } catch (_: Exception) {
                }
            }
        }
        for ((entity, tint) in tinted) {
            val inst = rm.getInstance(entity)
            val original = originals[entity]
            if (inst != 0 && original != null) {
                try {
                    rm.setMaterialInstanceAt(inst, 0, original)
                } catch (_: Exception) {
                }
            }
            try {
                engine.destroyMaterialInstance(tint)
            } catch (_: Exception) {
            }
        }
        tinted.clear()
        for (asset in assets) {
            try {
                scene.removeEntities(asset.entities)
                assetLoader.destroyAsset(asset)
            } catch (_: Exception) {
            }
        }
        assets.clear()
        proxyAssets.clear()
        proxyEntities.clear()
        val maps = ArrayList(mappedBuffers)
        mappedBuffers.clear()
        for (buffer in maps) unmap(buffer)
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
        retainedBuffers.clear()
        records.clear()
        deferred.clear()
        standInIds.clear()
        activeMapped = null
        activeStream = null
        framed = false
        try {
            engine.flushAndWait()
        } catch (_: Exception) {
        }
        Log.i(TAG, "released assets=$assetCount maps=$mapCount")
    }

    private fun destroyScene() {
        if (!engineAlive) return
        fun step(label: String, body: () -> Unit) {
            try {
                body()
            } catch (error: Exception) {
                Log.w(TAG, "$label: ${error.message}")
            }
        }
        step("clear") { clearModels() }
        step("xray-instance") {
            xrayInstance?.let { engine.destroyMaterialInstance(it) }
        }
        xrayInstance = null
        step("xray-material") {
            xrayMaterial?.let { engine.destroyMaterial(it) }
        }
        xrayMaterial = null
        step("lights") {
            scene.indirectLight = null
            scene.skybox = null
            engine.destroyIndirectLight(indirect)
            engine.destroySkybox(skybox)
            engine.destroyEntity(sun)
            engine.destroyEntity(fill)
        }
        step("loaders") {
            assetLoader.destroy()
            materialProvider.destroyMaterials()
            materialProvider.destroy()
            resourceLoader.destroy()
        }
        step("views") {
            swapChain?.let { engine.destroySwapChain(it) }
            swapChain = null
            engine.destroyRenderer(renderer)
            engine.destroyView(view)
            engine.destroyScene(scene)
            engine.destroyCameraComponent(camera.entity)
            EntityManager.get().destroy(camera.entity)
            EntityManager.get().destroy(sun)
            EntityManager.get().destroy(fill)
        }
        var engineDestroyed = false
        step("engine") {
            engine.flushAndWait()
            engine.destroy()
            engineDestroyed = true
        }
        if (engineDestroyed) Log.i(TAG, "destroyed filament engine")
        engineAlive = false
    }

    private fun longSet(values: List<*>?): HashSet<Long> {
        val out = HashSet<Long>()
        values?.forEach { if (it is Number) out.add(it.toLong()) }
        return out
    }

    private inner class SurfaceCallback : UiHelper.RendererCallback {
        override fun onNativeWindowChanged(surface: Surface) {
            val display = surfaceView.display
            renderHandler.post {
                if (destroyed || !engineAlive) return@post
                swapChain?.let { engine.destroySwapChain(it) }
                swapChain = engine.createSwapChain(surface)
                if (display != null) displayHelper.attach(renderer, display)
            }
        }

        override fun onDetachedFromSurface() {
            displayHelper.detach()
            renderHandler.post {
                if (!engineAlive) return@post
                swapChain?.let {
                    engine.destroySwapChain(it)
                    engine.flushAndWait()
                    swapChain = null
                }
            }
        }

        override fun onResized(width: Int, height: Int) {
            renderHandler.post {
                if (destroyed || !engineAlive) return@post
                viewportW = width.coerceAtLeast(1)
                viewportH = height.coerceAtLeast(1)
                view.viewport = Viewport(0, 0, viewportW, viewportH)
                manipulator?.setViewport(viewportW, viewportH)
                updateProjection()
                val fence = engine.createFence()
                fence.wait(Fence.Mode.FLUSH, Fence.WAIT_FOR_EVER)
                engine.destroyFence(fence)
            }
        }
    }

    companion object {
        private const val TAG = "FbvFilament"
        private val HIGHLIGHT = floatArrayOf(1f, 0.45f, 0.08f, 1f)
        private val STAND_IN = floatArrayOf(0.95f, 0.45f, 0.12f, 1f)

        /** Column-major (x, y, z) -> (x, z, -y). */
        private val Z_TO_Y = floatArrayOf(
            1f, 0f, 0f, 0f,
            0f, 0f, -1f, 0f,
            0f, 1f, 0f, 0f,
            0f, 0f, 0f, 1f,
        )
        private var ready = false

        fun ensureFilament() {
            if (ready) return
            Utils.init()
            Gltfio.init()
            ready = true
        }
    }
}

private class ElementFile(val file: File, val geoms: List<ElementGeom>)

private class PendingGlb(val buffer: ByteBuffer, val preview: Boolean)

private data class LoadPlan(
    val files: List<File>,
    val geoms: Map<Long, ElementGeom>,
    val lod0: Boolean,
    val elementFiles: Int,
    val partial: Boolean,
    val boxes: Int,
    val budget: Long,
    val deferred: Map<Long, File>,
    val proxy: ProxyGlb?,
    val preview: ProxyGlb?,
    val standIn: Set<Long>,
)
