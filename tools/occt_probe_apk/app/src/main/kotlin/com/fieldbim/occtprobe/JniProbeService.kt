package com.fieldbim.occtprobe

import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import java.io.File

class JniProbeService : Service() {
    private external fun nativeRun(brep: String, trace: String): String

    private val handler = Handler(Looper.getMainLooper()) { message ->
        val brep = message.data.getString("brep").orEmpty()
        val trace = message.data.getString("trace").orEmpty()
        val progress = File(message.data.getString("progress").orEmpty())
        fun note(line: String) {
            progress.appendText(line + "\n")
        }
        note("jni handler sdk=${Build.VERSION.SDK_INT}")
        val text = try {
            note("before loadLibrary occt_probe_jni")
            System.loadLibrary("occt_probe_jni")
            note("loadLibrary ok")
            nativeRun(brep, trace)
        } catch (error: Throwable) {
            note("load failed ${error.javaClass.name}: ${error.message}")
            "load failed ${error.javaClass.name}: ${error.message}\n"
        }
        try {
            val reply = Message.obtain()
            reply.data = Bundle().apply { putString("text", text) }
            message.replyTo?.send(reply)
        } catch (_: Exception) {
        }
        true
    }

    private val messenger = Messenger(handler)

    override fun onBind(intent: Intent): IBinder {
        val progress = intent.getStringExtra("progress")
        if (!progress.isNullOrEmpty()) {
            File(progress).writeText(
                "jni onBind sdk=${Build.VERSION.SDK_INT} abis=${Build.SUPPORTED_ABIS.joinToString(",")}\n"
            )
        }
        return messenger.binder
    }
}
