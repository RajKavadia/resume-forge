package com.example.resumetailor

import android.content.Intent
import android.net.Uri
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.example.resumetailor.capture.CaptureBridge
import com.example.resumetailor.storage.DownloadsBridge
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val tag = "ResumeForge.Main"
    private var deepLinkChannel: MethodChannel? = null
    private var deepLinkEvents: EventChannel? = null
    private var deepLinkSink: EventChannel.EventSink? = null
    private var initialLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.i(tag, "configureFlutterEngine")
        CaptureBridge.configure(flutterEngine, applicationContext)
        DownloadsBridge.configure(flutterEngine, applicationContext)
        deepLinkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "resumetailor/deeplink")
        deepLinkEvents = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "resumetailor/deeplink_events")
        deepLinkEvents?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                deepLinkSink = events
            }

            override fun onCancel(arguments: Any?) {
                deepLinkSink = null
            }
        })
        deepLinkChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    Log.i(tag, "getInitialLink requested: $initialLink")
                    result.success(initialLink)
                    initialLink = null
                }
                else -> result.notImplemented()
            }
        }
        handleIntent(intent, storeOnly = true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.i(tag, "onNewIntent: ${intent.data}")
        handleIntent(intent, storeOnly = false)
    }

    private fun handleIntent(intent: Intent?, storeOnly: Boolean) {
        val data: Uri? = intent?.data
        val text = intent?.getStringExtra(Intent.EXTRA_TEXT)
        val candidate = data?.toString() ?: text
        if (candidate != null && candidate.isNotBlank()) {
            Log.i(tag, "handleIntent storeOnly=$storeOnly link=$candidate")
            if (storeOnly) {
                initialLink = candidate
            } else {
                deepLinkSink?.success(candidate)
            }
        }
    }
}
