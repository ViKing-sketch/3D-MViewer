package com.fieldbim.field_bim_viewer

import android.app.Activity
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The access token never goes into `.fbv-sync.json`.
 * Bytes on disk are AES-GCM under a key that stays in the Android Keystore.
 */
class TokenBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "fbv/token")

    fun attach() {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "read" -> result.success(read())
                    "write" -> {
                        write(call.arguments as? String ?: "")
                        result.success(null)
                    }
                    "clear" -> {
                        clear()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("token", "token store failed", null)
            }
        }
    }

    private fun file(): File = File(activity.filesDir, "server.token")

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(ALIAS, null) as? SecretKey
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun write(token: String) {
        if (token.isEmpty()) {
            clear()
            return
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val iv = cipher.iv
        val encrypted = cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        val payload = ByteArray(1 + iv.size + encrypted.size)
        payload[0] = iv.size.toByte()
        System.arraycopy(iv, 0, payload, 1, iv.size)
        System.arraycopy(encrypted, 0, payload, 1 + iv.size, encrypted.size)
        file().writeBytes(payload)
    }

    private fun read(): String {
        val stored = file()
        if (!stored.isFile) return ""
        return try {
            val payload = stored.readBytes()
            if (payload.size < 2) return ""
            val ivLen = payload[0].toInt() and 0xFF
            if (ivLen <= 0 || payload.size <= 1 + ivLen) return ""
            val iv = payload.copyOfRange(1, 1 + ivLen)
            val encrypted = payload.copyOfRange(1 + ivLen, payload.size)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        } catch (_: Exception) {
            ""
        }
    }

    private fun clear() {
        val stored = file()
        if (stored.exists() && !stored.delete()) stored.writeBytes(ByteArray(0))
    }

    companion object {
        private const val ALIAS = "fbv.server.token"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
