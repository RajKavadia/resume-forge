package com.example.resumetailor.storage

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream

object DownloadsBridge {
    private const val CHANNEL = "resumetailor/downloads"
    private const val TAG = "ResumeForge.Downloads"

    fun configure(engine: FlutterEngine, appContext: Context) {
        Log.i(TAG, "configure")
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveHtml" -> {
                        val fileName = call.argument<String>("fileName").orEmpty()
                        val html = call.argument<String>("html").orEmpty()
                        val year = call.argument<Int>("year") ?: 0
                        val month = call.argument<Int>("month") ?: 0
                        val day = call.argument<Int>("day") ?: 0

                        if (fileName.isBlank() || html.isBlank()) {
                            result.error("invalid_args", "fileName/html required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val uri = saveToDownloads(
                                context = appContext,
                                relativeDir = "ResumeForgeAI/%04d-%02d-%02d".format(year, month, day),
                                fileName = fileName,
                                mimeType = "text/html",
                                bytes = html.toByteArray(Charsets.UTF_8)
                            )
                            result.success(uri.toString())
                        } catch (e: Exception) {
                            Log.e(TAG, "saveHtml failed", e)
                            result.error("save_failed", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToDownloads(
        context: Context,
        relativeDir: String,
        fileName: String,
        mimeType: String,
        bytes: ByteArray
    ): Uri {
        val resolver = context.contentResolver
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Files.getContentUri("external")
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + relativeDir)
            }
        }

        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore insert returned null")

        var out: OutputStream? = null
        try {
            out = resolver.openOutputStream(uri)
                ?: throw IllegalStateException("openOutputStream returned null")
            out.write(bytes)
            out.flush()
        } catch (e: Exception) {
            try {
                resolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            throw e
        } finally {
            try {
                out?.close()
            } catch (_: Exception) {
            }
        }

        Log.i(TAG, "Saved file to Downloads uri=$uri")
        return uri
    }
}

