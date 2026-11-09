package com.fieldbim.occtprobe

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import java.io.File
import kotlin.concurrent.thread

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        val output = findViewById<TextView>(R.id.output)
        findViewById<Button>(R.id.run).setOnClickListener {
            output.text = "Запуск…"
            thread {
                val text = runProbe()
                runOnUiThread { output.text = text }
            }
        }
    }

    private fun runProbe(): String {
        val nativeDir = applicationInfo.nativeLibraryDir
        val extracted = File(nativeDir, "libocct_probe.so")
        val copied = File(filesDir, "occt_probe")
        val notes = StringBuilder()
        if (!extracted.exists()) {
            return "В пакете нет libocct_probe.so. Каталог: $nativeDir"
        }
        try {
            extracted.copyTo(copied, overwrite = true)
            copied.setExecutable(true)
        } catch (error: Exception) {
            notes.append("Копия в filesDir не удалась: ${error.message}\n")
        }
        val attempts = listOf(copied, extracted)
        for (bin in attempts) {
            if (!bin.exists()) continue
            try {
                val process = ProcessBuilder(bin.absolutePath)
                    .redirectErrorStream(true)
                    .apply { environment()["LD_LIBRARY_PATH"] = nativeDir }
                    .start()
                val text = process.inputStream.bufferedReader().readText()
                val code = process.waitFor()
                return text.trimEnd() + "\nexit=$code\nbin=${bin.absolutePath}"
            } catch (error: Exception) {
                notes.append("${bin.absolutePath}: ${error.message}\n")
            }
        }
        return notes.toString().ifEmpty { "Проба не запустилась" }
    }
}
