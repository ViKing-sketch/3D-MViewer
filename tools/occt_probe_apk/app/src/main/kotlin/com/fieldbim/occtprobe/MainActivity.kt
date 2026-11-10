package com.fieldbim.occtprobe

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.widget.Button
import android.widget.TextView
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        val output = findViewById<TextView>(R.id.output)
        output.text = header() + "Нажмите кнопку и пришлите весь текст с экрана."
        findViewById<Button>(R.id.run).setOnClickListener {
            output.text = "Запуск из nativeLibraryDir…"
            thread { publish(output, runExec()) }
        }
        findViewById<Button>(R.id.jni).setOnClickListener {
            output.text = "JNI System.loadLibrary…"
            thread { publish(output, runJni()) }
        }
    }

    private fun publish(output: TextView, text: String) {
        runOnUiThread { output.text = text }
    }

    private fun header(): String {
        val info = applicationInfo
        val bin = File(info.nativeLibraryDir, "libocct_probe.so")
        val jni = File(info.nativeLibraryDir, "libocct_probe_jni.so")
        @Suppress("DEPRECATION")
        val version = packageManager.getPackageInfo(packageName, 0).versionName
        return buildString {
            appendLine("version=$version")
            appendLine("sdk=${Build.VERSION.SDK_INT}")
            appendLine("release=${Build.VERSION.RELEASE}")
            appendLine("targetSdk=${info.targetSdkVersion}")
            appendLine("abis=${Build.SUPPORTED_ABIS.joinToString(",")}")
            appendLine("nativeLibraryDir=${info.nativeLibraryDir}")
            appendLine("filesDir=${filesDir.absolutePath}")
            appendLine("bin=${bin.absolutePath}")
            appendLine("bin_exists=${bin.exists()} bin_bytes=${if (bin.exists()) bin.length() else 0}")
            appendLine("jni=${jni.absolutePath}")
            appendLine("jni_exists=${jni.exists()} jni_bytes=${if (jni.exists()) jni.length() else 0}")
            appendLine("ld_library_path=${info.nativeLibraryDir}")
            appendLine()
        }
    }

    private fun runExec(): String {
        val nativeDir = applicationInfo.nativeLibraryDir
        val bin = File(nativeDir, "libocct_probe.so")
        val brep = File(cacheDir, "fbv-occt-box.bin")
        val trace = File(cacheDir, "probe-exec.log")
        val stdout = File(cacheDir, "probe-exec-stdout.txt")
        val stderr = File(cacheDir, "probe-exec-stderr.txt")
        brep.delete()
        trace.delete()
        stdout.delete()
        stderr.delete()
        if (!bin.exists()) {
            return header() + "launch=nativeLibraryDir\nmissing ${bin.absolutePath}\n"
        }
        return try {
            val process = ProcessBuilder(bin.absolutePath, brep.absolutePath, trace.absolutePath)
                .redirectOutput(ProcessBuilder.Redirect.to(stdout))
                .redirectError(ProcessBuilder.Redirect.to(stderr))
                .apply { environment()["LD_LIBRARY_PATH"] = nativeDir }
                .start()
            val finished = process.waitFor(90, TimeUnit.SECONDS)
            if (!finished) process.destroyForcibly()
            val code = if (finished) process.exitValue() else -1
            header() +
                "launch=nativeLibraryDir\n" +
                exitLine(code, finished) + "\n" +
                "--- stdout ---\n" + readText(stdout) +
                "--- stderr ---\n" + readText(stderr) +
                "--- trace ---\n" + readText(trace)
        } catch (error: Exception) {
            header() +
                "launch=nativeLibraryDir\n" +
                "error=${error.javaClass.simpleName}: ${error.message}\n" +
                "--- trace ---\n" + readText(trace)
        }
    }

    private fun runJni(): String {
        val brep = File(cacheDir, "fbv-occt-box-jni.bin")
        val trace = File(cacheDir, "probe-jni.log")
        val progress = File(cacheDir, "probe-jni-progress.txt")
        brep.delete()
        trace.delete()
        progress.delete()
        val latch = CountDownLatch(1)
        val reply = AtomicBoolean(false)
        val text = StringBuilder()
        lateinit var connection: ServiceConnection
        connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, service: IBinder) {
                try {
                    service.linkToDeath({
                        if (reply.compareAndSet(false, true)) latch.countDown()
                    }, 0)
                } catch (error: Exception) {
                    text.append("linkToDeath ${error.message}\n")
                }
                try {
                    Messenger(service).send(Message.obtain().apply {
                        replyTo = Messenger(Handler(Looper.getMainLooper()) { message ->
                            text.append(message.data.getString("text").orEmpty())
                            if (reply.compareAndSet(false, true)) latch.countDown()
                            true
                        })
                        data = Bundle().apply {
                            putString("brep", brep.absolutePath)
                            putString("trace", trace.absolutePath)
                            putString("progress", progress.absolutePath)
                        }
                    })
                } catch (error: Exception) {
                    text.append("send ${error.javaClass.simpleName}: ${error.message}\n")
                    if (reply.compareAndSet(false, true)) latch.countDown()
                }
            }

            override fun onServiceDisconnected(name: ComponentName) {
                if (reply.compareAndSet(false, true)) latch.countDown()
            }
        }
        val intent = Intent(this, JniProbeService::class.java)
            .putExtra("progress", progress.absolutePath)
        val bound = CountDownLatch(1)
        val bindOk = AtomicBoolean(false)
        runOnUiThread {
            bindOk.set(bindService(intent, connection, Context.BIND_AUTO_CREATE))
            bound.countDown()
        }
        bound.await(10, TimeUnit.SECONDS)
        if (!bindOk.get()) {
            return header() + "launch=jni\nbindService failed\n"
        }
        val finished = latch.await(90, TimeUnit.SECONDS)
        runOnUiThread {
            try {
                unbindService(connection)
            } catch (_: IllegalArgumentException) {
            }
        }
        val status = when {
            !finished -> "jni=timeout"
            text.isEmpty() -> "jni process died"
            else -> "jni reply"
        }
        return header() +
            "launch=jni\n" +
            "$status\n" +
            "--- jni ---\n" + text.toString() +
            "--- progress ---\n" + readText(progress) +
            "--- trace ---\n" + readText(trace)
    }

    private fun exitLine(code: Int, finished: Boolean): String {
        if (!finished) return "exit=timeout"
        if (code > 128) {
            val signal = code - 128
            val name = when (signal) {
                11 -> "SIGSEGV"
                6 -> "SIGABRT"
                7 -> "SIGBUS"
                4 -> "SIGILL"
                9 -> "SIGKILL"
                else -> ""
            }
            return "exit=$code signal=$signal $name".trimEnd()
        }
        return "exit=$code"
    }

    private fun readText(file: File): String {
        if (!file.exists()) return "(нет файла)\n"
        val text = file.readText()
        return if (text.endsWith("\n") || text.isEmpty()) text else text + "\n"
    }
}
