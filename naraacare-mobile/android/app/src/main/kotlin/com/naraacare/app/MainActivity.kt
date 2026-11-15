package com.naraacare.app

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

// FlutterFragmentActivity is required by local_auth (biometric prompt).
class MainActivity : FlutterFragmentActivity() {
    private val io = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "naraacare/downloads")
            .setMethodCallHandler { call, result ->
                if (call.method != "savePdf") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                io.execute {
                    val saved = path != null && name != null && savePdf(File(path), name)
                    Handler(Looper.getMainLooper()).post { result.success(saved) }
                }
            }
    }

    /**
     * Copies a report the app already downloaded into Downloads/NaraaCare (Android 10+, MediaStore:
     * no storage permission). Only PDFs from the app's own files folder, with a plain file name, are
     * accepted, so the channel cannot be used to copy anything else. False on older Android (the
     * app offers Share instead) or on any error.
     */
    private fun savePdf(source: File, name: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        if (!Regex("^[A-Za-z0-9._-]{1,100}\\.pdf$").matches(name)) return false
        val root = filesDir.parentFile?.canonicalFile ?: return false
        val file = source.canonicalFile
        if (!file.path.startsWith(root.path + File.separator) || !file.isFile) return false
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/NaraaCare")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return false
        return try {
            resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
                ?: throw IllegalStateException("no output stream")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            true
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            false
        }
    }
}
