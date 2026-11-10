package com.fieldbim.field_bim_viewer

import android.content.Context
import android.os.Build
import java.io.File

// Loads the OCCT probe from nativeLibraryDir. The library is packaged as a
// JNI .so and extracted with the APK. Nothing is copied into filesDir: that
// copy is what SIGSEGV'd (exit 139) on Android 12 before the probe was loaded
// from nativeLibraryDir.
class OcctProbe {
    private external fun nativeRun(brep: String, trace: String): String

    private external fun nativeReadBrep(path: String, maxBytes: Int, maxMillis: Int): String

    fun run(context: Context): String {
        val info = context.applicationInfo
        val nativeDir = info.nativeLibraryDir
        val jni = File(nativeDir, "libocct_probe_jni.so")
        val brep = File(context.cacheDir, "fbv-occt-box.bin")
        val trace = File(context.cacheDir, "fbv-occt-box.log")
        brep.delete()
        trace.delete()
        val header = StringBuilder()
        @Suppress("DEPRECATION")
        val version = context.packageManager.getPackageInfo(context.packageName, 0).versionName
        header.append("version=$version\n")
        header.append("sdk=${Build.VERSION.SDK_INT}\n")
        header.append("release=${Build.VERSION.RELEASE}\n")
        header.append("targetSdk=${info.targetSdkVersion}\n")
        header.append("abis=${Build.SUPPORTED_ABIS.joinToString(",")}\n")
        header.append("nativeLibraryDir=$nativeDir\n")
        header.append("jni=${jni.absolutePath}\n")
        header.append("jni_exists=${jni.exists()} jni_bytes=${if (jni.exists()) jni.length() else 0}\n")
        header.append("filesDir=${context.filesDir.absolutePath}\n")
        header.append("files_copy=no\n")
        header.append("launch=loadLibrary\n")
        if (!jni.exists()) {
            return header.toString() + "missing ${jni.absolutePath}\n"
        }
        return try {
            System.loadLibrary("occt_probe_jni")
            header.append(nativeRun(brep.absolutePath, trace.absolutePath))
            header.append("--- trace ---\n")
            header.append(if (trace.exists()) trace.readText() else "(нет файла)\n")
            header.toString()
        } catch (error: Throwable) {
            header.toString() + "load failed ${error.javaClass.name}: ${error.message}\n"
        }
    }

    // Reads one BinTools file already stored in the package. Failure is a
    // string, not a thrown exception, so the viewer can keep the mesh.
    fun readBrep(path: String, maxBytes: Int, maxMillis: Int): String {
        return try {
            System.loadLibrary("occt_probe_jni")
            nativeReadBrep(path, maxBytes, maxMillis)
        } catch (error: Throwable) {
            "read=fail reason=jni ${error.javaClass.name}: ${error.message}\n"
        }
    }
}
