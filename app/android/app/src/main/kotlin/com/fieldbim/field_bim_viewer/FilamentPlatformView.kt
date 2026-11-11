package com.fieldbim.field_bim_viewer

import android.annotation.SuppressLint
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
import kotlin.math.abs
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
 * isolate, X-ray, the section clip and the framed cameras. Package meshes are Z-up; each asset
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
    private var letterboxView: View? = null
    private var letterboxScene: Scene? = null
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
    private var sectionMaterial: Material? = null
    private var sectionGhostMaterial: Material? = null
    private var sectionBody: MaterialInstance? = null
    private var sectionBodyInward: MaterialInstance? = null
    private var sectionSelected: MaterialInstance? = null
    private var sectionSelectedInward: MaterialInstance? = null
    private var sectionGhost: MaterialInstance? = null
    private var sectionGhostInward: MaterialInstance? = null
    private var sectionStandIn: MaterialInstance? = null
    private var swapChain: SwapChain? = null
    private var manipulator: Manipulator? = null
    private var gesture: OrbitGestures? = null
    private var walkMode = false
    private var walkToken = -1
    private var walkPose = WalkRig.Pose(0f, 1.6f, 0f, 0f, 0f)
    private var walkGesture: WalkGestures? = null
    private var dollyPending = 0f
    private var dollySpeed = 0.25f
    private var dollyX = 0
    private var dollyY = 0
    private var framedRadius = 1f

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
    private var sectionEnabled = false
    private var sectionNearAmount = 0.0
    private var sectionAxis = "x"
    private var sectionFlip = false
    private var sectionOffset = 0f
    private var sectionBox = false
    private var sectionInset = 0f
    private var sectionActive = false
    private var liveClip: SectionClip.Clip? = null
    private var sentClip: SectionClip.Clip? = null
    private var publishedAt = Float.NaN
    private var publishedHalf = Float.NaN
    private var viewportW = 1
    private var viewportH = 1
    private var fitBottomInset = 0.0
    private val cameraView = DoubleArray(16)
    private val cameraProjection = DoubleArray(16)
    private var near = 0.05
    private var baseNear = 0.05
    private var far = 2000.0
    private var lastEye = doubleArrayOf(0.0, 0.0, 5.0)
    private var lastTarget = doubleArrayOf(0.0, 0.0, 0.0)
    private var frameMin = floatArrayOf(-1f, -1f, -1f)
    private var frameMax = floatArrayOf(1f, 1f, 1f)
    private var preset = "iso"
    @Volatile private var destroyed = false
    private var framed = false
    private var refitSelected = false
    private var framedBox: FloatArray? = null
    private var framedAspect = 0.0
    private val replaced = HashSet<Long>()
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
    private val inwardIds = HashSet<Long>()
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
        renderer.clearOptions = Renderer.ClearOptions().apply {
            setClearColor(0.83, 0.87, 0.91, 1.0)
            clear = true
            discard = false
        }
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
        // The scene viewport stops at the sheet. Pixels below it are not drawn
        // by [view], and an uncleared SurfaceView buffer flashes black there
        // whenever the sheet and the inset disagree by a few pixels.
        val letterScene = engine.createScene()
        letterScene.skybox = skybox
        val letterView = engine.createView()
        letterView.scene = letterScene
        letterView.camera = camera
        letterView.isPostProcessingEnabled = false
        letterView.antiAliasing = View.AntiAliasing.NONE
        letterboxScene = letterScene
        letterboxView = letterView
        xrayInstance = loadXray()
        loadSection()
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
                    if (sceneArmed) pumpQueue()
                    if ((frameSelected || refitSelected) && selected != 0L) {
                        refitSelected = false
                        frame(selectedBox(), preset)
                    }
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
            "setFitInset" -> {
                val bottom = call.argument<Number>("bottom")?.toDouble() ?: 0.0
                renderHandler.post {
                    if (destroyed) return@post
                    val next = bottom.coerceIn(0.0, 0.72)
                    if (!FitInset.changed(fitBottomInset, next, viewportH)) return@post
                    fitBottomInset = next
                    applyViewViewport()
                    if (walkMode) {
                        updateProjection()
                        return@post
                    }
                    val box = framedBox
                    if (box != null) frame(box, preset) else updateProjection()
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
            "cameraPose" -> {
                renderHandler.post {
                    if (destroyed) {
                        result.success(null)
                        return@post
                    }
                    val eye = lastEye.copyOf()
                    val target = lastTarget.copyOf()
                    result.success(
                        mapOf(
                            "eye" to eye.toList(),
                            "target" to target.toList(),
                        ),
                    )
                }
            }
            "setViewpoint" -> {
                val eye = vec3(call.argument<List<*>>("eye"))
                val target = vec3(call.argument<List<*>>("target"))
                renderHandler.post {
                    if (destroyed || eye == null || target == null) return@post
                    placeOrbit(eye, target)
                }
                result.success(null)
            }
            "setNavigation" -> {
                val mode = call.argument<String>("mode") ?: "orbit"
                val token = call.argument<Number>("token")?.toInt() ?: 0
                val eye = vec3(call.argument<List<*>>("eye"))
                val look = vec3(call.argument<List<*>>("look"))
                renderHandler.post {
                    if (destroyed) return@post
                    if (mode != "walk" || eye == null || look == null) {
                        if (walkMode) exitWalkKeepingView()
                        return@post
                    }
                    if (walkMode && token == walkToken) return@post
                    walkToken = token
                    walkPose = WalkRig.fromLook(
                        eye[0], eye[1], eye[2], look[0], look[1], look[2],
                    )
                    walkMode = true
                    gesture = null
                    walkGesture = WalkGestures(::nudgeLook, ::nudgeMove)
                    near = 0.05
                    baseNear = 0.05
                    if (far < 2000.0) far = 2000.0
                    updateProjection()
                    Log.i(
                        TAG,
                        "walk eye=${eye[0]},${eye[1]},${eye[2]} " +
                            "look=${look[0]},${look[1]},${look[2]}",
                    )
                }
                result.success(null)
            }
            "setSection" -> {
                val enabled = call.argument<Boolean>("enabled") == true
                val nearAmount = finite(call.argument<Number>("near")?.toDouble() ?: 0.0, 0.0)
                val axis = call.argument<String>("axis") ?: "x"
                val flip = call.argument<Boolean>("flip") == true
                val offset = finite(call.argument<Number>("offset")?.toDouble() ?: 0.0, 0.0).toFloat()
                val box = call.argument<Boolean>("box") == true
                val inset = finite(call.argument<Number>("inset")?.toDouble() ?: 0.0, 0.0).toFloat()
                renderHandler.post {
                    if (destroyed) return@post
                    sectionEnabled = enabled
                    sectionNearAmount = nearAmount.coerceIn(0.0, 1.0)
                    sectionAxis = axis
                    sectionFlip = flip
                    sectionOffset = offset.coerceIn(-1f, 1f)
                    sectionBox = box
                    sectionInset = inset.coerceIn(0f, 1f)
                    syncSection(log = true)
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
        if (destroyed) return
        if (loadingRoot == root) {
            val ticket = generation.get()
            renderHandler.post {
                if (destroyed || loadingRoot != root || ticket != generation.get()) return@post
                val reload = reportedReady
                resetViewerState()
                if (reload) {
                    frame(allBox(), preset)
                    applyVisibility()
                }
            }
            return
        }
        loadingRoot = root
        val ticket = generation.incrementAndGet()
        setStatus(mapOf("code" to "loading", "loaded" to 0, "total" to 0))
        renderHandler.post {
            if (ticket != generation.get() || destroyed) return@post
            resetViewerState()
            sceneArmed = false
            reportedReady = false
            clearModels()
        }
        Thread {
            try {
                val plan = plan(File(root), ticket)
                renderHandler.post {
                    if (!destroyed && ticket == generation.get() && loadingRoot == root) begin(plan)
                }
            } catch (_: CancelledLoad) {
                // Back already bumped the generation. Do not plan or begin.
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

    private fun plan(root: File, ticket: Int): LoadPlan {
        fun live() {
            if (destroyed || ticket != generation.get()) throw CancelledLoad()
        }
        live()
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
            live()
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
        live()
        val standIn = proxyIds.toSet()
        val inward = LinkedHashSet<Long>()
        if (lod0.isFile) noteWinding(lod0, inward)
        for (file in elementGlbs) noteWinding(file, inward)
        val span = SceneBounds.span(SceneBounds.union(geomsZ.values, standIn))
        // Records keep the full element bounds so a selected stand-in is framed
        // to the mesh, not to the clamped orange box.
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
            standGeoms.add(SceneBounds.clamp(geom, span))
        }
        live()
        val preview = ProxyBoxes.build(previewGeoms)
        val proxy = ProxyBoxes.build(standGeoms)
        val partial = (lod0.isFile && !useLod0) || standIn.isNotEmpty()
        if (gpu.isEmpty() && proxy == null && preview == null) error("mesh/lod0.glb was not found")
        live()
        Log.i(
            TAG,
            "plan lod0=$useLod0 files=${gpu.size} standIns=${standIn.size} " +
                "inward=${inward.size} fitSpan=$span preview=${previewGeoms.size}",
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
            inward,
        )
    }

    /** Element files overwrite lod0, matching [readGeoms]. Failures stay outward. */
    private fun noteWinding(file: File, inward: MutableSet<Long>) {
        try {
            for ((id, sign) in GlbElements.frontSigns(file)) {
                if (sign < 0f) inward.add(id) else inward.remove(id)
            }
        } catch (error: Exception) {
            Log.w(TAG, "winding ${file.name}: ${error.message}")
        }
    }

    private fun resetViewerState() {
        val wasSection = sectionEnabled || sectionActive
        sectionEnabled = false
        sectionNearAmount = 0.0
        sectionAxis = "x"
        sectionFlip = false
        sectionOffset = 0f
        sectionBox = false
        sectionInset = 0f
        sectionActive = false
        liveClip = null
        sentClip = null
        publishedAt = Float.NaN
        publishedHalf = Float.NaN
        preset = "iso"
        walkMode = false
        walkToken = -1
        walkGesture = null
        selected = 0L
        hidden = HashSet()
        isolated = HashSet()
        xray = false
        manipulator = null
        gesture = null
        dollyPending = 0f
        if (wasSection) Log.i(TAG, "section enabled=false")
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
        inwardIds.addAll(plan.inward)
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
        val fit = SceneBounds.fit(records.values, standInIds)
        if (fit != null) {
            val box = fit.bounds
            Log.i(
                TAG,
                "fit min=${box[0]},${box[1]},${box[2]} max=${box[3]},${box[4]},${box[5]} " +
                    "kept=${fit.kept} elements=${fit.total} standIns=${standInIds.size}",
            )
            frame(box, preset)
        } else {
            Log.i(TAG, "fit empty elements=${records.size} standIns=${standInIds.size}")
            frame(null, preset)
        }
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
                    releasePreviewAssets()
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
        if (!proxy && refitSelected && selected != 0L) {
            refitSelected = false
            frame(selectedBox(), preset)
        }
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
        val tm = engine.transformManager
        var instance = tm.getInstance(asset.root)
        if (instance == 0) {
            tm.create(asset.root)
            instance = tm.getInstance(asset.root)
        }
        if (instance != 0) {
            tm.setTransform(instance, Z_TO_Y)
        } else {
            Log.w(TAG, "root transform missing")
        }
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

    @SuppressLint("BlockedPrivateApi")
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

    private fun index(asset: FilamentAsset): List<Long> {
        val found = ArrayList<Long>()
        val proxy = asset in proxyAssets
        for (entity in asset.entities) {
            if (entity == 0 || elementByEntity.containsKey(entity)) continue
            val id = elementId(asset.getExtras(entity)) ?: asset.getName(entity)?.toLongOrNull()
            if (id != null && id != 0L) {
                if (proxy && id in replaced) continue
                elementByEntity[entity] = id
                if (proxy) proxyEntities.add(entity) else found.add(id)
            }
        }
        if (!proxy) {
            retireProxies(found)
            adoptAssetBounds(asset, found)
        }
        releaseRetiredProxies()
        return found
    }

    /** The loaded GLB can be larger than the accessor box we framed. Keep the union. */
    private fun adoptAssetBounds(asset: FilamentAsset, ids: List<Long>) {
        if (ids.size != 1) return
        val box = uprightAssetBox(asset) ?: return
        if (ids[0] == selected && adoptBox(ids[0], box)) refitSelected = true
    }

    private fun uprightAssetBox(asset: FilamentAsset): FloatArray? {
        val center = asset.boundingBox.center
        val half = asset.boundingBox.halfExtent
        if (half[0] + half[1] + half[2] <= 0f) return null
        val min = floatArrayOf(center[0] - half[0], center[1] - half[1], center[2] - half[2])
        val max = floatArrayOf(center[0] + half[0], center[1] + half[1], center[2] + half[2])
        val upright = ElementGeom(0L, min, max, floatArrayOf(1f, 1f, 1f, 1f)).upright()
        return floatArrayOf(
            upright.min[0], upright.min[1], upright.min[2],
            upright.max[0], upright.max[1], upright.max[2],
        )
    }

    private fun adoptBox(id: Long, box: FloatArray): Boolean {
        val current = records[id] ?: return false
        val recorded = floatArrayOf(
            current.min[0], current.min[1], current.min[2],
            current.max[0], current.max[1], current.max[2],
        )
        val merged = SceneBounds.enclosing(recorded, box)
        val grew = merged[0] < recorded[0] - 0.01f || merged[1] < recorded[1] - 0.01f ||
            merged[2] < recorded[2] - 0.01f || merged[3] > recorded[3] + 0.01f ||
            merged[4] > recorded[4] + 0.01f || merged[5] > recorded[5] + 0.01f
        if (!grew) return false
        records[id] = current.copy(
            min = floatArrayOf(merged[0], merged[1], merged[2]),
            max = floatArrayOf(merged[3], merged[4], merged[5]),
        )
        return true
    }

    /** Drop preview boxes once their elements have a real mesh. Stand-ins stay. */
    private fun releaseRetiredProxies() {
        if (!engineAlive || previewAssets.isEmpty()) return
        val drop = ArrayList<FilamentAsset>()
        for (asset in previewAssets) {
            if (asset == activeAsset) continue
            val still = asset.entities.any { entity ->
                entity != 0 && entity in proxyEntities && elementByEntity[entity]?.let { it !in replaced } == true
            }
            if (!still) drop.add(asset)
        }
        if (drop.isEmpty()) return
        destroyPreviewAssets(drop)
    }

    /** The preview GLB is only a placeholder. Real meshes have replaced it by the time the queue is idle. */
    private fun releasePreviewAssets() {
        if (!engineAlive || previewAssets.isEmpty()) return
        val drop = previewAssets.filter { it != activeAsset }
        if (drop.isEmpty()) return
        destroyPreviewAssets(drop)
    }

    private fun destroyPreviewAssets(drop: List<FilamentAsset>) {
        for (asset in drop) {
            for (entity in asset.entities) {
                if (inScene.remove(entity)) scene.remove(entity)
                elementByEntity.remove(entity)
                originals.remove(entity)
                proxyEntities.remove(entity)
                val tint = tinted.remove(entity)
                if (tint != null) {
                    try {
                        engine.destroyMaterialInstance(tint)
                    } catch (_: Exception) {
                    }
                }
            }
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
        if (ids.isEmpty()) return
        replaced.addAll(ids)
        val wanted = ids.toHashSet()
        val drop = ArrayList<Int>()
        for ((entity, id) in elementByEntity) {
            if (entity in proxyEntities && id in wanted) drop.add(entity)
        }
        for (asset in proxyAssets.toList()) {
            for (entity in asset.entities) {
                if (entity == 0 || entity in drop) continue
                val id = elementByEntity[entity]
                    ?: elementId(asset.getExtras(entity))
                    ?: asset.getName(entity)?.toLongOrNull()
                if (id != null && id in wanted) drop.add(entity)
            }
        }
        for (entity in drop) hideProxyEntity(entity)
        if (drop.isNotEmpty()) {
            Log.i(TAG, "cleared proxy entities=${drop.size} elements=${wanted.size}")
        }
    }

    private fun hideProxyEntity(entity: Int) {
        if (inScene.remove(entity)) scene.remove(entity)
        elementByEntity.remove(entity)
        originals.remove(entity)
        proxyEntities.remove(entity)
        val tint = tinted.remove(entity)
        if (tint != null) {
            try {
                engine.destroyMaterialInstance(tint)
            } catch (_: Exception) {
            }
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
        if (walkMode) {
            val pose = walkPose
            val look = WalkRig.forward(pose.yaw, pose.pitch)
            lastEye[0] = pose.eyeX.toDouble()
            lastEye[1] = pose.eyeY.toDouble()
            lastEye[2] = pose.eyeZ.toDouble()
            lastTarget[0] = pose.eyeX + look[0].toDouble()
            lastTarget[1] = pose.eyeY + look[1].toDouble()
            lastTarget[2] = pose.eyeZ + look[2].toDouble()
            camera.lookAt(
                lastEye[0], lastEye[1], lastEye[2],
                lastTarget[0], lastTarget[1], lastTarget[2],
                0.0, 1.0, 0.0,
            )
        } else {
            flushDolly(dt)
            manipulator?.update(dt)
            val eye = DoubleArray(3)
            val target = DoubleArray(3)
            val up = DoubleArray(3)
            manipulator?.getLookAt(eye, target, up)
            if (manipulator != null) {
                lastEye = eye
                lastTarget = target
                camera.lookAt(eye[0], eye[1], eye[2], target[0], target[1], target[2], up[0], up[1], up[2])
            }
        }
        if (sectionEnabled) syncSection(log = false)
        resourceLoader.asyncUpdateLoad()
        assetLoader.gc()
        populate()
        pumpQueue()
        logUploadHeartbeat(frameTimeNanos)
        if (renderer.beginFrame(swapChain!!, frameTimeNanos)) {
            paintLetterbox()
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
        if (refitSelected && selected != 0L) {
            refitSelected = false
            frame(selectedBox(), preset)
        }
    }

    private fun indexEntity(asset: FilamentAsset, entity: Int) {
        if (entity == 0 || elementByEntity.containsKey(entity)) return
        val id = elementId(asset.getExtras(entity)) ?: asset.getName(entity)?.toLongOrNull()
        if (id != null && id != 0L) {
            if (asset in proxyAssets && id in replaced) {
                if (inScene.remove(entity)) scene.remove(entity)
                return
            }
            elementByEntity[entity] = id
            if (asset in proxyAssets) {
                proxyEntities.add(entity)
            } else {
                retireProxies(listOf(id))
                val visual = worldBoxOf(entity)
                if (visual != null && adoptBox(id, visual) && id == selected) refitSelected = true
            }
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
            if (sectionActive && sectionBody != null) {
                val proxy = entity in proxyEntities
                val inward = !proxy && id in inwardIds
                val painted = when {
                    id == selected -> if (inward) sectionSelectedInward else sectionSelected
                    xray -> if (inward) sectionGhostInward else sectionGhost
                    proxy -> sectionStandIn
                    inward -> sectionBodyInward
                    else -> sectionBody
                } ?: sectionBody!!
                rm.setMaterialInstanceAt(instance, 0, painted)
                continue
            }
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
        walkMode = false
        walkGesture = null
        val bounds = box
        if (bounds == null || bounds.size < 6) {
            Log.i(TAG, "frame skipped")
            return
        }
        frameMin = bounds.copyOfRange(0, 3)
        frameMax = bounds.copyOfRange(3, 6)
        val aspect = frameAspect()
        val solved = tighten(CameraFit.pose(bounds, cameraPreset, aspect), bounds)
        lastEye = doubleArrayOf(solved.eyeX.toDouble(), solved.eyeY.toDouble(), solved.eyeZ.toDouble())
        lastTarget = doubleArrayOf(
            solved.targetX.toDouble(),
            solved.targetY.toDouble(),
            solved.targetZ.toDouble(),
        )
        framedBox = bounds.copyOf()
        framedAspect = aspect
        baseNear = max(0.02, solved.radius / 4000.0)
        near = baseNear
        far = max(solved.distance.toDouble() * 80.0, solved.radius * 80.0)
        if (far < 500.0) far = 500.0
        val zoom = max(solved.distance * 0.035f, 0.25f)
        dollySpeed = zoom
        dollyPending = 0f
        framedRadius = solved.radius
        manipulator = Manipulator.Builder()
            .viewport(viewportW.coerceAtLeast(1), viewportH.coerceAtLeast(1))
            .targetPosition(solved.targetX, solved.targetY, solved.targetZ)
            .orbitHomePosition(solved.eyeX, solved.eyeY, solved.eyeZ)
            .upVector(0f, 1f, 0f)
            .zoomSpeed(zoom)
            .fovDegrees(CameraFit.fovDegrees.toFloat())
            .fovDirection(Manipulator.Fov.VERTICAL)
            .farPlane(far.toFloat())
            .build(Manipulator.Mode.ORBIT)
        gesture = OrbitGestures(surfaceView, manipulator!!, ::noteZoom)
        framed = true
        applyViewViewport()
        updateProjection()
        val ndc = if (engineAlive) readNdc(bounds) else CameraFit.maxAbsNdc(bounds, solved, aspect)
        if (sectionEnabled) syncSection(log = false)
        Log.i(
            TAG,
            "frame target=${solved.targetX},${solved.targetY},${solved.targetZ} " +
                "eye=${solved.eyeX},${solved.eyeY},${solved.eyeZ} " +
                "dist=${solved.distance} radius=${solved.radius} ndc=$ndc " +
                "aspect=$aspect inset=$fitBottomInset preset=$cameraPreset",
        )
    }

    /**
     * Move the eye along the view until the live Filament matrices put the
     * corners at the edge of the picture. The analytic pose is the start.
     */
    private fun tighten(pose: CameraFit.Pose, bounds: FloatArray): CameraFit.Pose {
        if (!engineAlive) return pose
        val dx = (pose.eyeX - pose.targetX).toDouble()
        val dy = (pose.eyeY - pose.targetY).toDouble()
        val dz = (pose.eyeZ - pose.targetZ).toDouble()
        val len = sqrt(dx * dx + dy * dy + dz * dz).coerceAtLeast(1e-4)
        val ux = dx / len
        val uy = dy / len
        val uz = dz / len
        near = max(0.02, pose.radius / 4000.0)
        far = max(pose.distance.toDouble() * 80.0, 500.0)
        fun ndcAt(distance: Double): Float {
            camera.lookAt(
                pose.targetX + ux * distance,
                pose.targetY + uy * distance,
                pose.targetZ + uz * distance,
                pose.targetX.toDouble(),
                pose.targetY.toDouble(),
                pose.targetZ.toDouble(),
                0.0,
                1.0,
                0.0,
            )
            updateProjection()
            return readNdc(bounds)
        }
        val guessed = ndcAt(pose.distance.toDouble())
        if (guessed in 0.90f..1.02f || guessed > 4f) return pose
        var lo = 0.5
        var hi = max(pose.distance.toDouble() * 4.0, pose.radius * 8.0)
        repeat(8) {
            val farNdc = ndcAt(hi)
            if (farNdc > 4f) return pose
            if (farNdc <= 1.0f) return@repeat
            hi *= 1.6
        }
        repeat(16) {
            val mid = (lo + hi) * 0.5
            val midNdc = ndcAt(mid)
            if (midNdc > 4f) return pose
            if (midNdc > 0.96f) lo = mid else hi = mid
        }
        val solved = ndcAt(hi)
        if (solved !in 0.90f..1.02f) return pose
        return pose.copy(
            eyeX = (pose.targetX + ux * hi).toFloat(),
            eyeY = (pose.targetY + uy * hi).toFloat(),
            eyeZ = (pose.targetZ + uz * hi).toFloat(),
            distance = hi.toFloat(),
        )
    }

    private fun readNdc(bounds: FloatArray): Float {
        camera.getViewMatrix(cameraView)
        camera.getProjectionMatrix(cameraProjection)
        return CameraFit.maxAbsNdc(cameraView, cameraProjection, bounds)
    }

    private fun frameAspect(): Double {
        val height = visibleHeight()
        return if (viewportW > 1 && height > 1) viewportW.toDouble() / height else 1.0
    }

    private fun visibleHeight(): Int {
        val full = viewportH.coerceAtLeast(1)
        val height = (full * (1.0 - fitBottomInset.coerceIn(0.0, 0.72))).toInt()
        return height.coerceIn(1, full)
    }

    private fun applyViewViewport() {
        if (!engineAlive) return
        val height = visibleHeight()
        view.viewport = Viewport(0, viewportH - height, viewportW.coerceAtLeast(1), height)
    }

    private fun paintLetterbox() {
        val letter = letterboxView ?: return
        val fullW = viewportW.coerceAtLeast(1)
        val fullH = viewportH.coerceAtLeast(1)
        if (visibleHeight() >= fullH) return
        letter.viewport = Viewport(0, 0, fullW, fullH)
        renderer.render(letter)
    }

    private fun allBox(): FloatArray? {
        val skip = SceneBounds.skipForFrame(records.keys, standInIds, hidden, isolated)
        return SceneBounds.fit(records.values, skip)?.bounds
            ?: floatArrayOf(frameMin[0], frameMin[1], frameMin[2], frameMax[0], frameMax[1], frameMax[2])
    }

    private fun selectedBox(): FloatArray? {
        val geom = records[selected] ?: return allBox()
        val recorded = floatArrayOf(
            geom.min[0], geom.min[1], geom.min[2],
            geom.max[0], geom.max[1], geom.max[2],
        )
        val visual = renderedBox(selected) ?: return recorded
        return SceneBounds.enclosing(recorded, visual)
    }

    /** World-space box of whatever is currently drawn for [id], proxy or mesh. */
    private fun renderedBox(id: Long): FloatArray? {
        var box: FloatArray? = null
        for ((entity, entityId) in elementByEntity) {
            if (entityId != id) continue
            val part = worldBoxOf(entity) ?: continue
            val soFar = box
            box = if (soFar == null) part else SceneBounds.enclosing(soFar, part)
        }
        return box
    }

    private fun worldBoxOf(entity: Int): FloatArray? {
        if (!engineAlive) return null
        val renderable = engine.renderableManager
        val instance = renderable.getInstance(entity)
        if (instance == 0) return null
        val local = renderable.getAxisAlignedBoundingBox(instance)
        val transform = engine.transformManager
        val node = transform.getInstance(entity)
        if (node == 0) return null
        val matrix = FloatArray(16)
        transform.getWorldTransform(node, matrix)
        val center = local.center
        val half = local.halfExtent
        var minX = Float.POSITIVE_INFINITY
        var minY = Float.POSITIVE_INFINITY
        var minZ = Float.POSITIVE_INFINITY
        var maxX = Float.NEGATIVE_INFINITY
        var maxY = Float.NEGATIVE_INFINITY
        var maxZ = Float.NEGATIVE_INFINITY
        for (sx in intArrayOf(-1, 1)) {
            for (sy in intArrayOf(-1, 1)) {
                for (sz in intArrayOf(-1, 1)) {
                    val x = center[0] + sx * half[0]
                    val y = center[1] + sy * half[1]
                    val z = center[2] + sz * half[2]
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
        if (minX == Float.POSITIVE_INFINITY) return null
        return floatArrayOf(minX, minY, minZ, maxX, maxY, maxZ)
    }

    private fun updateProjection() {
        if (viewportW <= 0 || viewportH <= 0) return
        camera.setProjection(45.0, frameAspect(), near, far, Camera.Fov.VERTICAL)
    }

    private fun nudgeLook(dx: Float, dy: Float) {
        renderHandler.post {
            if (!walkMode || destroyed) return@post
            walkPose = WalkRig.lookDrag(walkPose, dx, dy)
        }
    }

    private fun nudgeMove(forward: Float, strafe: Float) {
        renderHandler.post {
            if (!walkMode || destroyed) return@post
            walkPose = WalkRig.move(walkPose, forward, strafe)
        }
    }

    private fun exitWalkKeepingView() {
        val pose = walkPose
        val look = WalkRig.forward(pose.yaw, pose.pitch)
        lastEye[0] = pose.eyeX.toDouble()
        lastEye[1] = pose.eyeY.toDouble()
        lastEye[2] = pose.eyeZ.toDouble()
        lastTarget[0] = pose.eyeX + look[0].toDouble()
        lastTarget[1] = pose.eyeY + look[1].toDouble()
        lastTarget[2] = pose.eyeZ + look[2].toDouble()
        walkMode = false
        walkGesture = null
        val zoom = max(dollySpeed, 0.25f)
        manipulator = Manipulator.Builder()
            .viewport(viewportW.coerceAtLeast(1), viewportH.coerceAtLeast(1))
            .targetPosition(
                lastTarget[0].toFloat(),
                lastTarget[1].toFloat(),
                lastTarget[2].toFloat(),
            )
            .orbitHomePosition(
                lastEye[0].toFloat(),
                lastEye[1].toFloat(),
                lastEye[2].toFloat(),
            )
            .upVector(0f, 1f, 0f)
            .zoomSpeed(zoom)
            .fovDegrees(CameraFit.fovDegrees.toFloat())
            .fovDirection(Manipulator.Fov.VERTICAL)
            .farPlane(far.toFloat())
            .build(Manipulator.Mode.ORBIT)
        gesture = OrbitGestures(surfaceView, manipulator!!, ::noteZoom)
    }

    private fun placeOrbit(eye: FloatArray, target: FloatArray) {
        val dx = (eye[0] - target[0]).toDouble()
        val dy = (eye[1] - target[1]).toDouble()
        val dz = (eye[2] - target[2]).toDouble()
        val distance = sqrt(dx * dx + dy * dy + dz * dz).coerceAtLeast(0.25)
        lastEye = doubleArrayOf(eye[0].toDouble(), eye[1].toDouble(), eye[2].toDouble())
        lastTarget = doubleArrayOf(target[0].toDouble(), target[1].toDouble(), target[2].toDouble())
        walkMode = false
        walkGesture = null
        baseNear = max(0.02, distance / 4000.0)
        near = baseNear
        far = max(distance * 80.0, 500.0)
        dollySpeed = max(distance * 0.035, 0.25).toFloat()
        dollyPending = 0f
        val zoom = dollySpeed
        manipulator = Manipulator.Builder()
            .viewport(viewportW.coerceAtLeast(1), viewportH.coerceAtLeast(1))
            .targetPosition(target[0], target[1], target[2])
            .orbitHomePosition(eye[0], eye[1], eye[2])
            .upVector(0f, 1f, 0f)
            .zoomSpeed(zoom)
            .fovDegrees(CameraFit.fovDegrees.toFloat())
            .fovDirection(Manipulator.Fov.VERTICAL)
            .farPlane(far.toFloat())
            .build(Manipulator.Mode.ORBIT)
        gesture = OrbitGestures(surfaceView, manipulator!!, ::noteZoom)
        framed = true
        updateProjection()
        if (::camera.isInitialized) {
            camera.lookAt(
                lastEye[0], lastEye[1], lastEye[2],
                lastTarget[0], lastTarget[1], lastTarget[2],
                0.0, 1.0, 0.0,
            )
        }
    }

    private fun vec3(raw: List<*>?): FloatArray? {
        if (raw == null || raw.size < 3) return null
        val out = FloatArray(3)
        for (i in 0..2) {
            val number = raw[i] as? Number ?: return null
            out[i] = number.toFloat()
        }
        return out
    }

    private fun noteZoom(x: Int, y: Int, scrollDelta: Float) {
        dollyX = x
        dollyY = y
        dollyPending += scrollDelta
    }

    /**
     * Ease the queued pinch and wheel command. Far from the model the metres
     * match an immediate `scroll`. Against the bounds, zoom-in is smaller.
     */
    private fun flushDolly(dt: Float) {
        val manip = manipulator ?: return
        if (dollyPending == 0f) return
        val gap = Dolly.gapToBox(
            lastEye[0].toFloat(),
            lastEye[1].toFloat(),
            lastEye[2].toFloat(),
            frameMin[0],
            frameMin[1],
            frameMin[2],
            frameMax[0],
            frameMax[1],
            frameMax[2],
        )
        val step = Dolly.step(dollyPending, dt, dollySpeed, gap, framedRadius)
        dollyPending = step.pending
        if (abs(step.scroll) < 1e-5f) return
        manip.scroll(dollyX, dollyY, step.scroll)
    }

    private fun onTouch(event: MotionEvent): Boolean {
        if (!engineAlive || destroyed) return true
        if (walkMode) {
            walkGesture?.onTouchEvent(event)
            if (event.actionMasked == MotionEvent.ACTION_SCROLL) {
                val wheel = event.getAxisValue(MotionEvent.AXIS_VSCROLL)
                val metres = wheel * WalkRig.metresPerWheel
                renderHandler.post {
                    if (walkMode && !destroyed) {
                        walkPose = WalkRig.move(walkPose, metres, 0f)
                    }
                }
            }
        } else {
            gesture?.onTouchEvent(event)
        }
        if (!walkMode && event.actionMasked == MotionEvent.ACTION_SCROLL && manipulator != null) {
            val wheel = event.getAxisValue(MotionEvent.AXIS_VSCROLL)
            noteZoom(event.x.toInt(), event.y.toInt(), -wheel * Dolly.wheelScroll)
        }
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
        val ready = vp.width > 1 && vp.height > 1
        val left = if (ready) vp.left else 0
        val bottom = if (ready) vp.bottom else 0
        val width = if (ready) vp.width else viewportW
        val height = if (ready) vp.height else viewportH
        val coords = PickCoords.resolve(left, bottom, width, height, viewportH, x, y)
        if (coords == null) {
            val reason = if (width <= 1 || height <= 1) "unready" else "outside"
            Log.i(
                TAG,
                "pick miss reason=$reason x=$x y=$y viewport=$left,$bottom ${width}x$height",
            )
            return
        }
        val px = coords[0]
        val py = coords[1]
        val clip = if (sectionActive) liveClip else null
        val bounds = if (clip != null) sectionBounds() else null
        val projection = if (clip != null) camera.getProjectionMatrix(DoubleArray(16)) else null
        val model = if (clip != null) camera.getModelMatrix(DoubleArray(16)) else null
        view.pick(px, py, renderHandler, View.OnPickCallback { result ->
            if (destroyed) return@OnPickCallback
            var id = elementByEntity[result.renderable] ?: 0L
            val depth = result.depth
            val frag = result.fragCoords
            val fragX = if (frag.size >= 1) frag[0] else px.toFloat()
            val fragY = if (frag.size >= 2) frag[1] else py.toFloat()
            // fragCoords.z is 1 - depth: 0 at the near plane, 1 at infinity.
            val fragZ = if (frag.size >= 3) frag[2] else 1f - depth
            var world: FloatArray? = null
            var rejected = false
            if (id != 0L && clip != null && bounds != null && projection != null && model != null &&
                SectionClip.usableDepth(depth)
            ) {
                world = SectionClip.unproject(projection, model, width, height, fragX, fragY, fragZ)
                if (world != null && SectionClip.rejects(world[0], world[1], world[2], clip, bounds)) {
                    rejected = true
                    id = 0L
                }
            }
            val reason = when {
                rejected -> "section"
                id != 0L -> "hit"
                result.renderable != 0 -> "unmapped"
                else -> "miss"
            }
            val worldText = world?.joinToString(",") ?: "none"
            Log.i(
                TAG,
                "pick $reason element=$id renderable=${result.renderable} depth=$depth " +
                    "fragZ=$fragZ px=$px py=$py world=$worldText",
            )
            if (id != 0L && deferred.containsKey(id)) {
                ensureSelected(id)
                if (sceneArmed) pumpQueue()
            }
            val picked = id
            mainHandler.post {
                try {
                    channel.invokeMethod("onPick", mapOf("elementId" to picked))
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

    private fun loadSection() {
        sectionMaterial = openMaterial("materials/section.filamat")
        sectionGhostMaterial = openMaterial("materials/section_ghost.filamat")
        val material = sectionMaterial
        if (material == null) return
        sectionBody = material.createInstance().also {
            paintSection(it, SECTION_BODY, 0.78f, 1f)
        }
        sectionBodyInward = material.createInstance().also {
            paintSection(it, SECTION_BODY, 0.78f, -1f)
        }
        sectionSelected = material.createInstance().also {
            paintSection(it, HIGHLIGHT, 0.42f, 1f)
        }
        sectionSelectedInward = material.createInstance().also {
            paintSection(it, HIGHLIGHT, 0.42f, -1f)
        }
        sectionStandIn = material.createInstance().also {
            paintSection(it, STAND_IN, 0.5f, 1f)
        }
        sectionGhost = sectionGhostMaterial?.createInstance()?.also {
            paintSection(it, SECTION_GHOST, 0.9f, 1f)
        }
        sectionGhostInward = sectionGhostMaterial?.createInstance()?.also {
            paintSection(it, SECTION_GHOST, 0.9f, -1f)
        }
    }

    private fun openMaterial(path: String): Material? {
        return try {
            val bytes = context.assets.open(path).use { it.readBytes() }
            val buffer = ByteBuffer.allocateDirect(bytes.size)
            buffer.put(bytes)
            buffer.flip()
            Material.Builder().payload(buffer, buffer.remaining()).build(engine)
        } catch (error: Exception) {
            Log.w(TAG, "section material $path: ${error.message}")
            null
        }
    }

    private fun paintSection(instance: MaterialInstance, color: FloatArray, roughness: Float, frontSign: Float) {
        instance.setParameter("baseColor", color[0], color[1], color[2], color[3])
        instance.setParameter("capColor", SECTION_CAP[0], SECTION_CAP[1], SECTION_CAP[2], SECTION_CAP[3])
        instance.setParameter("roughness", roughness)
        instance.setParameter("frontSign", frontSign)
        instance.setParameter("clipPlane", 0f, 0f, 0f, 0f)
        instance.setParameter("boxMin", 0f, 0f, 0f, 0f)
        instance.setParameter("boxMax", 0f, 0f, 0f, 0f)
    }

    private fun eachSection(block: (MaterialInstance) -> Unit) {
        sectionBody?.let(block)
        sectionBodyInward?.let(block)
        sectionSelected?.let(block)
        sectionSelectedInward?.let(block)
        sectionGhost?.let(block)
        sectionGhostInward?.let(block)
        sectionStandIn?.let(block)
    }

    private fun syncSection(log: Boolean) {
        val want = sectionEnabled && sectionBody != null
        if (want) {
            updateSectionUniforms()
        } else {
            liveClip = null
            sentClip = null
        }
        updateNear()
        if (want != sectionActive) {
            sectionActive = want
            applyVisibility()
        }
        if (log) logSection()
    }

    private fun updateSectionUniforms() {
        if (sectionBody == null) return
        val bounds = sectionBounds()
        val clip = SectionClip.solve(
            axis = sectionAxis,
            flip = sectionFlip,
            offset = sectionOffset,
            bounds = bounds,
            eyeX = lastEye[0].toFloat(),
            eyeY = lastEye[1].toFloat(),
            eyeZ = lastEye[2].toFloat(),
            targetX = lastTarget[0].toFloat(),
            targetY = lastTarget[1].toFloat(),
            targetZ = lastTarget[2].toFloat(),
            boxEnabled = sectionBox,
            boxInset = sectionInset,
        )
        liveClip = clip
        val previous = sentClip
        if (previous == null || !previous.matches(clip)) {
            sentClip = clip
            eachSection { pushClip(it, clip) }
        }
        publishSection(clip.reach, clip.boxSpan, clip.at, force = false)
    }

    private fun pushClip(instance: MaterialInstance, clip: SectionClip.Clip) {
        try {
            instance.setParameter("clipPlane", clip.nx, clip.ny, clip.nz, clip.d)
            instance.setParameter(
                "boxMin",
                clip.minX,
                clip.minY,
                clip.minZ,
                if (clip.box) 1f else 0f,
            )
            instance.setParameter("boxMax", clip.maxX, clip.maxY, clip.maxZ, 0f)
        } catch (error: Exception) {
            Log.w(TAG, "section uniform: ${error.message}")
        }
    }

    private fun updateNear() {
        val eyeDistance = SectionClip.distance(
            lastEye[0], lastEye[1], lastEye[2],
            lastTarget[0], lastTarget[1], lastTarget[2],
        )
        val next = if (sectionEnabled) {
            SectionClip.nearDistance(baseNear, eyeDistance, sectionNearAmount)
        } else {
            baseNear
        }
        if (kotlin.math.abs(next - near) <= 1e-4) return
        near = next
        updateProjection()
    }

    private fun sectionBounds(): FloatArray {
        return allBox()
            ?: floatArrayOf(frameMin[0], frameMin[1], frameMin[2], frameMax[0], frameMax[1], frameMax[2])
    }

    private fun logSection() {
        val clip = liveClip
        if (!sectionEnabled || clip == null) {
            Log.i(TAG, "section enabled=false")
            publishSection(0f, 0f, 0f, force = true)
            return
        }
        Log.i(
            TAG,
            "section enabled=true axis=$sectionAxis flip=$sectionFlip " +
                "offset=$sectionOffset metres=${clip.metres} at=${clip.at} near=$sectionNearAmount " +
                "box=$sectionBox inset=$sectionInset " +
                "plane=${clip.nx},${clip.ny},${clip.nz},${clip.d} " +
                "centre=${clip.cx},${clip.cy},${clip.cz} " +
                "boxMin=${clip.minX},${clip.minY},${clip.minZ} " +
                "boxMax=${clip.maxX},${clip.maxY},${clip.maxZ}",
        )
        publishSection(clip.reach, clip.boxSpan, clip.at, force = true)
    }

    private fun publishSection(half: Float, box: Float, at: Float, force: Boolean) {
        if (!force && !publishedAt.isNaN() &&
            kotlin.math.abs(publishedAt - at) < 0.05f &&
            kotlin.math.abs(publishedHalf - half) < 0.05f
        ) {
            return
        }
        publishedAt = at
        publishedHalf = half
        mainHandler.post {
            try {
                channel.invokeMethod(
                    "onSection",
                    mapOf(
                        "half" to half.toDouble(),
                        "box" to box.toDouble(),
                        "at" to at.toDouble(),
                    ),
                )
            } catch (_: Exception) {
            }
        }
    }

    private fun finite(value: Double, fallback: Double): Double {
        return if (value.isNaN() || value.isInfinite()) fallback else value
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
        for ((entity, original) in originals) {
            val inst = rm.getInstance(entity)
            if (inst == 0) continue
            try {
                rm.setMaterialInstanceAt(inst, 0, original)
            } catch (_: Exception) {
            }
        }
        sectionActive = false
        liveClip = null
        sentClip = null
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
        inwardIds.clear()
        replaced.clear()
        framedBox = null
        framedAspect = 0.0
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
        step("section-instances") {
            eachSection { engine.destroyMaterialInstance(it) }
        }
        sectionBody = null
        sectionBodyInward = null
        sectionSelected = null
        sectionSelectedInward = null
        sectionGhost = null
        sectionGhostInward = null
        sectionStandIn = null
        step("section-material") {
            sectionMaterial?.let { engine.destroyMaterial(it) }
            sectionGhostMaterial?.let { engine.destroyMaterial(it) }
        }
        sectionMaterial = null
        sectionGhostMaterial = null
        step("lights") {
            scene.indirectLight = null
            scene.skybox = null
            letterboxScene?.skybox = null
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
            letterboxView?.let { engine.destroyView(it) }
            letterboxView = null
            letterboxScene?.let { engine.destroyScene(it) }
            letterboxScene = null
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
                if (width < 2 || height < 2) return@post
                viewportW = width
                viewportH = height
                applyViewViewport()
                manipulator?.setViewport(viewportW, viewportH)
                val aspect = frameAspect()
                val box = framedBox
                if (box != null && kotlin.math.abs(aspect - framedAspect) > 0.05) {
                    frame(box, preset)
                }
                updateProjection()
                val fence = engine.createFence()
                fence.wait(Fence.Mode.FLUSH, Fence.WAIT_FOR_EVER)
                engine.destroyFence(fence)
            }
        }
    }

    private class CancelledLoad : RuntimeException()

    companion object {
        private const val TAG = "FbvFilament"
        private val HIGHLIGHT = floatArrayOf(1f, 0.45f, 0.08f, 1f)
        private val STAND_IN = floatArrayOf(0.95f, 0.45f, 0.12f, 1f)
        private val SECTION_BODY = floatArrayOf(0.73f, 0.75f, 0.78f, 1f)
        private val SECTION_CAP = floatArrayOf(0.93f, 0.38f, 0.14f, 1f)
        private val SECTION_GHOST = floatArrayOf(0.62f, 0.76f, 0.90f, 0.28f)

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
    val inward: Set<Long>,
)
