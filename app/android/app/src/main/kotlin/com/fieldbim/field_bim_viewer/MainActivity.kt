package com.fieldbim.field_bim_viewer

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bridge: ImportBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "fbv/filament",
            FilamentViewFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
        val imported = ImportBridge(this, flutterEngine.dartExecutor.binaryMessenger, ::launchPicker)
        imported.attach()
        bridge = imported
        imported.consume(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        bridge?.consume(intent)
    }

    @Deprecated("AndroidX Activity Result is unavailable on FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != OPEN_PACKAGE) return
        val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
        bridge?.onPicked(uri)
    }

    private fun launchPicker() {
        val pick = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(pick, OPEN_PACKAGE)
    }

    companion object {
        private const val OPEN_PACKAGE = 0xFB71
    }
}
