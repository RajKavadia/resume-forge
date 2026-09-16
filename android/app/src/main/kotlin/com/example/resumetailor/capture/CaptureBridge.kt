package com.example.resumetailor.capture

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object CaptureBridge {
    private const val METHOD_CHANNEL = "resumetailor/capture"
    private const val EVENT_CHANNEL = "resumetailor/capture_events"
    private const val TAG = "ResumeForge.Capture"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var appContext: Context? = null

    fun configure(engine: FlutterEngine, appContext: Context) {
        Log.i(TAG, "configure")
        this.appContext = appContext.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startOverlay" -> {
                        Log.i(TAG, "startOverlay")
                        OverlayCaptureService.start(appContext)
                        result.success(true)
                    }

                    "stopOverlay" -> {
                        Log.i(TAG, "stopOverlay")
                        OverlayCaptureService.stop(appContext)
                        result.success(true)
                    }

                    "triggerCaptureScroll" -> {
                        Log.i(TAG, "triggerCaptureScroll")
                        ScreenCaptureAccessibilityService.requestCaptureAndScroll()
                        result.success(true)
                    }

                    "openAccessibilitySettings" -> {
                        Log.i(TAG, "openAccessibilitySettings")
                        openAccessibilitySettings(appContext)
                        result.success(true)
                    }

                    "openOverlaySettings" -> {
                        Log.i(TAG, "openOverlaySettings")
                        openOverlaySettings(appContext)
                        result.success(true)
                    }

                    "openAppNotificationSettings" -> {
                        Log.i(TAG, "openAppNotificationSettings")
                        openAppNotificationSettings(appContext)
                        result.success(true)
                    }

                    "isAccessibilityEnabled" -> {
                        val enabled = isAccessibilityEnabled(appContext)
                        result.success(enabled)
                    }

                    "updateStatus" -> {
                        val message = call.argument<String>("message").orEmpty()
                        Log.i(TAG, "updateStatus message=$message")
                        if (message.isNotBlank()) {
                            emitStatus(message)
                        }
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    fun emitCapturedText(text: String) {
        Log.i(TAG, "emitCapturedText length=${text.length}")
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to "captured_text",
                    "text" to text
                )
            )
        }
    }

    fun emitStatus(message: String) {
        Log.i(TAG, "emitStatus message=$message")
        appContext?.let { StatusNotification.show(it, message) }
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to "status",
                    "message" to message
                )
            )
        }
    }

    private fun openAccessibilitySettings(context: Context) {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    private fun openOverlaySettings(context: Context) {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${context.packageName}")
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    private fun openAppNotificationSettings(context: Context) {
        val intent = Intent().apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                action = Settings.ACTION_APP_NOTIFICATION_SETTINGS
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            } else {
                action = "android.settings.APP_NOTIFICATION_SETTINGS"
                putExtra("app_package", context.packageName)
                putExtra("app_uid", context.applicationInfo.uid)
            }
        }
        context.startActivity(intent)
    }

    private fun isAccessibilityEnabled(context: Context): Boolean {
        val expected = "${context.packageName}/${context.packageName}.capture.ScreenCaptureAccessibilityService"
        val enabled = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
    }
}
