package com.fieldbim.field_bim_viewer

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Full-screen camera. Returns the QR text in [Intent] extra `link`. */
class QrScanActivity : ComponentActivity() {
    private val closed = AtomicBoolean(false)
    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private val reader = MultiFormatReader().apply {
        setHints(
            mapOf<DecodeHintType, Any>(
                DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
                DecodeHintType.TRY_HARDER to true,
            ),
        )
    }
    private lateinit var previewView: PreviewView

    private val permission = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) startCamera() else finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = FrameLayout(this)
        previewView = PreviewView(this)
        root.addView(
            previewView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        val label = TextView(this).apply {
            text = intent.getStringExtra("title") ?: "QR"
            setTextColor(Color.WHITE)
            setBackgroundColor(0x88000000.toInt())
            textSize = 18f
            setPadding(32, 64, 32, 32)
        }
        root.addView(
            label,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP,
            ),
        )
        setContentView(root)
        if (
            ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            startCamera()
        } else {
            permission.launch(Manifest.permission.CAMERA)
        }
    }

    override fun onDestroy() {
        analysisExecutor.shutdown()
        super.onDestroy()
    }

    private fun startCamera() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener(
            {
                val provider = try {
                    future.get()
                } catch (_: Exception) {
                    finish()
                    return@addListener
                }
                val preview = Preview.Builder().build()
                preview.setSurfaceProvider(previewView.surfaceProvider)
                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                    .build()
                analysis.setAnalyzer(analysisExecutor, ::analyze)
                try {
                    provider.unbindAll()
                    provider.bindToLifecycle(
                        this,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        analysis,
                    )
                } catch (_: Exception) {
                    finish()
                }
            },
            ContextCompat.getMainExecutor(this),
        )
    }

    private fun analyze(image: ImageProxy) {
        try {
            if (closed.get()) return
            val text = decode(image) ?: return
            if (!closed.compareAndSet(false, true)) return
            runOnUiThread {
                setResult(RESULT_OK, Intent().putExtra("link", text))
                finish()
            }
        } catch (_: Exception) {
        } finally {
            image.close()
        }
    }

    private fun decode(image: ImageProxy): String? {
        val luma = luminance(image) ?: return null
        val rotated = rotate(luma, image.width, image.height, image.imageInfo.rotationDegrees)
        val source = PlanarYUVLuminanceSource(
            rotated.bytes,
            rotated.width,
            rotated.height,
            0,
            0,
            rotated.width,
            rotated.height,
            false,
        )
        return try {
            reader.decodeWithState(BinaryBitmap(HybridBinarizer(source))).text
        } catch (_: NotFoundException) {
            null
        } finally {
            reader.reset()
        }
    }

    private fun luminance(image: ImageProxy): ByteArray? {
        val plane = image.planes.firstOrNull() ?: return null
        val width = image.width
        val height = image.height
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        val buffer = plane.buffer
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)
        if (pixelStride == 1 && rowStride == width && bytes.size >= width * height) {
            return bytes.copyOf(width * height)
        }
        val out = ByteArray(width * height)
        var outIndex = 0
        for (y in 0 until height) {
            var inIndex = y * rowStride
            for (x in 0 until width) {
                if (inIndex >= bytes.size) return null
                out[outIndex] = bytes[inIndex]
                outIndex += 1
                inIndex += pixelStride
            }
        }
        return out
    }

    private data class Frame(val bytes: ByteArray, val width: Int, val height: Int)

    private fun rotate(src: ByteArray, width: Int, height: Int, degrees: Int): Frame {
        val deg = ((degrees % 360) + 360) % 360
        if (deg == 0 || src.size < width * height) return Frame(src, width, height)
        if (deg == 180) {
            val out = ByteArray(width * height)
            val last = width * height - 1
            for (i in 0 until width * height) out[last - i] = src[i]
            return Frame(out, width, height)
        }
        val out = ByteArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val value = src[y * width + x]
                val newX: Int
                val newY: Int
                if (deg == 90) {
                    newX = height - 1 - y
                    newY = x
                } else {
                    newX = y
                    newY = width - 1 - x
                }
                out[newY * height + newX] = value
            }
        }
        return Frame(out, height, width)
    }
}
