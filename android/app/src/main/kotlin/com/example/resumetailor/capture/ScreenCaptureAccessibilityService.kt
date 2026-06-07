package com.example.resumetailor.capture

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.view.accessibility.AccessibilityNodeInfo

class ScreenCaptureAccessibilityService : AccessibilityService() {
    private val tag = "ResumeForge.Accessibility"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val heartbeat = object : Runnable {
        override fun run() {
            Log.i(tag, "heartbeat running=true overlayShown=${overlayView != null}")
            CaptureBridge.emitStatus("Accessibility service alive")
            mainHandler.postDelayed(this, 10_000)
        }
    }
    private var lastRoot: AccessibilityNodeInfo? = null
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(tag, "onServiceConnected")
        CaptureBridge.emitStatus("Accessibility service connected")
        OverlayCaptureService.start(this)
        showControlOverlay()
        mainHandler.post(heartbeat)
    }

    override fun onAccessibilityEvent(event: android.view.accessibility.AccessibilityEvent?) {
        lastRoot = rootInActiveWindow ?: lastRoot
        Log.d(tag, "onAccessibilityEvent type=${event?.eventType} package=${event?.packageName}")
    }

    override fun onInterrupt() {
        // No-op
    }

    override fun onDestroy() {
        Log.i(tag, "onDestroy")
        mainHandler.removeCallbacks(heartbeat)
        removeControlOverlay()
        lastRoot?.recycle()
        lastRoot = null
        instance = null
        super.onDestroy()
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        Log.i(tag, "onUnbind")
        return super.onUnbind(intent)
    }

    private fun captureVisibleText(): String {
        val root = rootInActiveWindow ?: lastRoot ?: run {
            Log.w(tag, "captureVisibleText: no root available")
            return ""
        }
        val sb = StringBuilder()
        val visited = HashSet<String>(2048)
        collectText(root, sb, visited)
        Log.i(tag, "captureVisibleText length=${sb.length}")
        return sb.toString().trim()
    }

    private fun collectText(
        node: AccessibilityNodeInfo?,
        sb: StringBuilder,
        visited: MutableSet<String>
    ) {
        if (node == null) return

        val text = node.text?.toString()?.trim().orEmpty()
        val contentDesc = node.contentDescription?.toString()?.trim().orEmpty()

        fun add(line: String) {
            val normalized = line.replace(Regex("\\s+"), " ").trim()
            if (normalized.isEmpty()) return
            if (visited.add(normalized)) {
                sb.append(normalized).append('\n')
            }
        }

        if (text.isNotEmpty()) add(text)
        if (contentDesc.isNotEmpty() && contentDesc != text) add(contentDesc)

        for (i in 0 until node.childCount) {
            collectText(node.getChild(i), sb, visited)
        }
    }

    private fun swipeUp(onDone: (() -> Unit)? = null) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            onDone?.invoke()
            return
        }

        val displayMetrics = resources.displayMetrics
        val width = displayMetrics.widthPixels.toFloat()
        val height = displayMetrics.heightPixels.toFloat()

        val startX = width / 2f
        val startY = height * 0.75f
        val endY = height * 0.25f

        val path = Path().apply {
            moveTo(startX, startY)
            lineTo(startX, endY)
        }

        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 350))
            .build()

        dispatchGesture(
            gesture,
            object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    super.onCompleted(gestureDescription)
                    onDone?.invoke()
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    super.onCancelled(gestureDescription)
                    onDone?.invoke()
                }
            },
            null
        )
    }

    private fun captureAndScroll(iterations: Int = 6) {
        if (iterations <= 0) {
            Log.i(tag, "captureAndScroll finished")
            CaptureBridge.emitStatus("Capture session stopped")
            return
        }
        Log.i(tag, "captureAndScroll iterations=$iterations")
        CaptureBridge.emitStatus("Capture session active; remaining iterations=$iterations")
        val text = captureVisibleText()
        if (text.isNotBlank()) {
            CaptureBridge.emitCapturedText(text)
            CaptureBridge.emitStatus("Captured text (${text.length} chars)")
        } else {
            CaptureBridge.emitStatus("No readable text found on this screen")
        }

        mainHandler.postDelayed({
            swipeUp {
                Log.i(tag, "swipeUp completed")
                mainHandler.postDelayed({ captureAndScroll(iterations - 1) }, 450)
            }
        }, 250)
    }

    private fun captureSinglePage() {
        Log.i(tag, "captureSinglePage")
        CaptureBridge.emitStatus("Capturing current page")
        val text = captureVisibleText()
        if (text.isNotBlank()) {
            CaptureBridge.emitCapturedText(text)
            CaptureBridge.emitStatus("Captured text (${text.length} chars)")
        } else {
            CaptureBridge.emitStatus("No readable text found on this screen")
        }
    }

    private fun showControlOverlay() {
        if (overlayView != null) return

        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val button = Button(this).apply {
            text = "Screenshot"
            setPadding(36, 20, 36, 20)
            setBackgroundColor(0xCC111111.toInt())
            setTextColor(0xFFFFFFFF.toInt())
            setOnClickListener {
                Log.i(this@ScreenCaptureAccessibilityService.tag, "screenshot button tapped")
                captureSinglePage()
            }
        }

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 16
            y = 120
        }

        button.setOnTouchListener(DraggableTouchListener(layoutParams, wm, button))
        overlayView = button
        wm.addView(button, layoutParams)
        Log.i(tag, "control overlay shown")
    }

    private fun removeControlOverlay() {
        val wm = windowManager ?: return
        val view = overlayView ?: return
        try {
            wm.removeView(view)
        } catch (e: Exception) {
            Log.w(tag, "removeControlOverlay failed", e)
        }
        overlayView = null
        windowManager = null
        Log.i(tag, "control overlay removed")
    }

    private class DraggableTouchListener(
        private val layoutParams: WindowManager.LayoutParams,
        private val windowManager: WindowManager,
        private val view: View
    ) : View.OnTouchListener {
        private var initialX = 0
        private var initialY = 0
        private var initialTouchX = 0f
        private var initialTouchY = 0f
        private var isDragging = false

        override fun onTouch(v: View, event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = layoutParams.x
                    initialY = layoutParams.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    return false
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - initialTouchX).toInt()
                    val dy = (event.rawY - initialTouchY).toInt()
                    if (!isDragging && (kotlin.math.abs(dx) > 6 || kotlin.math.abs(dy) > 6)) {
                        isDragging = true
                        view.isPressed = false
                    }
                    if (isDragging) {
                        layoutParams.x = initialX - dx
                        layoutParams.y = initialY + dy
                        windowManager.updateViewLayout(v, layoutParams)
                        return true
                    }
                }

                MotionEvent.ACTION_UP -> {
                    if (isDragging) {
                        isDragging = false
                        return true
                    }
                }
            }
            return false
        }
    }

    companion object {
        @Volatile
        private var instance: ScreenCaptureAccessibilityService? = null

        fun requestCaptureAndScroll() {
            val svc = instance
            if (svc == null) {
                Log.w("ResumeForge.Accessibility", "requestCaptureAndScroll: service not enabled")
                CaptureBridge.emitStatus("Accessibility service not enabled")
                return
            }
            CaptureBridge.emitStatus("Starting screen capture")
            Log.i("ResumeForge.Accessibility", "requestCaptureAndScroll")
            svc.captureAndScroll()
        }
    }
}
