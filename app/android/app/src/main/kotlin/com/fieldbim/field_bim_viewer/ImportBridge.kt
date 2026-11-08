package com.fieldbim.field_bim_viewer

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * Copies a content URI from the system picker or a share intent into app storage.
 * The copy is streamed. The Dart side never sees the foreign URI.
 */
class ImportBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val launchPicker: () -> Unit,
    private val launchSave: (String) -> Unit,
) {
    private val channel = MethodChannel(messenger, "fbv/import")
    private val main = Handler(Looper.getMainLooper())
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSave: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private var pendingPath: String? = null

    fun attach() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "libraryDir" -> result.success(libraryDir().absolutePath)
                "takePending" -> {
                    val path = pendingPath
                    pendingPath = null
                    result.success(path)
                }
                "pick" -> {
                    if (pendingResult != null || pendingSave != null) {
                        result.error("busy", "import already in progress", null)
                    } else {
                        pendingResult = result
                        launchPicker()
                    }
                }
                "saveCsv" -> {
                    val name = call.argument<String>("name") ?: "spec.csv"
                    val text = call.argument<String>("text") ?: ""
                    if (pendingResult != null || pendingSave != null) {
                        result.error("busy", "import already in progress", null)
                    } else {
                        pendingSave = result
                        pendingBytes = text.toByteArray(Charsets.UTF_8)
                        launchSave(name)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onSavePicked(uri: Uri?) {
        val result = pendingSave
        val bytes = pendingBytes
        pendingSave = null
        pendingBytes = null
        if (uri == null || bytes == null) {
            result?.success(null)
            return
        }
        Thread {
            try {
                val output = activity.contentResolver.openOutputStream(uri)
                    ?: throw IOException("cannot write $uri")
                output.use { it.write(bytes) }
                main.post { result?.success(uri.toString()) }
            } catch (error: Exception) {
                val message = error.message ?: "save failed"
                main.post { result?.error("save", message, null) }
            }
        }.start()
    }

    fun onPicked(uri: Uri?) {
        val result = pendingResult
        pendingResult = null
        if (uri == null) {
            result?.success(null)
            return
        }
        import(uri, result)
    }

    fun consume(intent: Intent?) {
        val uri = uriOf(intent) ?: return
        intent?.action = null
        intent?.data = null
        intent?.removeExtra(Intent.EXTRA_STREAM)
        import(uri, null)
    }

    private fun import(uri: Uri, result: MethodChannel.Result?) {
        Thread {
            try {
                val path = copy(uri)
                main.post {
                    pendingPath = path
                    result?.success(path)
                    channel.invokeMethod("onOpened", path)
                }
            } catch (error: Exception) {
                val message = error.message ?: "import failed"
                main.post {
                    result?.error("import", message, null)
                    channel.invokeMethod("onFailed", message)
                }
            }
        }.start()
    }

    private fun copy(uri: Uri): String {
        val rawName = displayName(uri).ifBlank { "model.fbvpkg" }
        val safe = rawName.replace(Regex("[^A-Za-z0-9._\\- ]"), "_")
        val fileName = if (safe.endsWith(".fbvpkg", ignoreCase = true)) safe else "$safe.fbvpkg"
        var dest = File(libraryDir(), fileName)
        var suffix = 1
        while (dest.exists()) {
            val stem = fileName.removeSuffix(".fbvpkg")
            dest = File(libraryDir(), "$stem-$suffix.fbvpkg")
            suffix += 1
        }
        val input = activity.contentResolver.openInputStream(uri)
            ?: throw IOException("cannot read $uri")
        input.use { source ->
            dest.outputStream().use { out ->
                val buffer = ByteArray(1024 * 1024)
                while (true) {
                    val read = source.read(buffer)
                    if (read < 0) break
                    out.write(buffer, 0, read)
                }
            }
        }
        return dest.absolutePath
    }

    private fun displayName(uri: Uri): String {
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index) ?: ""
            }
        }
        return uri.lastPathSegment ?: ""
    }

    private fun libraryDir(): File {
        val dir = File(activity.filesDir, "library")
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("cannot create ${dir.path}")
        return dir
    }

    private fun uriOf(intent: Intent?): Uri? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> streamUri(intent)
            else -> null
        }
    }

    private fun streamUri(intent: Intent): Uri? {
        val extra = if (android.os.Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
        return extra as? Uri
    }
}
