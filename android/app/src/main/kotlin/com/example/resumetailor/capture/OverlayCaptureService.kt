package com.example.resumetailor.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageButton
import androidx.core.app.NotificationCompat
import com.example.resumetailor.MainActivity

class OverlayCaptureService : Service() {
    private val tag = "ResumeForge.Overlay"
    private var windowManager: WindowManager? = null
    private var overlayButton: View? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(tag, "onCreate")
        startAsForeground()
        showOverlay()
    }

    override fun onDestroy() {
        Log.i(tag, "onDestroy")
        removeOverlay()
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(tag, "onStartCommand flags=$flags startId=$startId")
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(tag, "onTaskRemoved")
        super.onTaskRemoved(rootIntent)
    }

    private fun startAsForeground() {
        val channelId = "capture_overlay"
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Screen Capture",
                NotificationManager.IMPORTANCE_LOW
            )
            notificationManager.createNotificationChannel(channel)
        }

        val activityIntent = Intent(this, MainActivity::class.java)
        val pendingIntentFlags =
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            activityIntent,
            pendingIntentFlags
        )

        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("ResumeForge AI")
            .setContentText("Tap the floating button to capture text & scroll")
            .setSmallIcon(android.R.drawable.ic_menu_search)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        try {
            Log.i(tag, "startForeground")
            startForeground(1001, notification)
        } catch (e: SecurityException) {
            Log.e(tag, "startForeground failed", e)
            // Android 13+ requires POST_NOTIFICATIONS runtime permission. If not granted,
            // the foreground notification may fail. Surface a status to Flutter.
            CaptureBridge.emitStatus("Notification permission required to keep capture running")
            stopSelf()
        }
    }

    private fun showOverlay() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.w(tag, "Overlay permission not granted")
            CaptureBridge.emitStatus("Overlay permission not granted")
            stopSelf()
            return
        }

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val button = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_upload)
            background = null
            setContentDescription("Capture screen text")
            setOnClickListener {
                Log.i(this@OverlayCaptureService.tag, "overlay button tapped")
                ScreenCaptureAccessibilityService.requestCaptureAndScroll()
            }
        }

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            x = 24
            y = 0
        }

        button.setOnTouchListener(DraggableTouchListener(layoutParams, windowManager!!))
        overlayButton = button
        windowManager?.addView(button, layoutParams)
    }

    private fun removeOverlay() {
        val wm = windowManager ?: return
        val view = overlayButton ?: return
        try {
            wm.removeView(view)
        } catch (_: Exception) {
        }
        overlayButton = null
        windowManager = null
    }

    private class DraggableTouchListener(
        private val layoutParams: WindowManager.LayoutParams,
        private val windowManager: WindowManager
    ) : View.OnTouchListener {
        private var initialX = 0
        private var initialY = 0
        private var initialTouchX = 0f
        private var initialTouchY = 0f

        override fun onTouch(v: View, event: MotionEvent): Boolean {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = layoutParams.x
                    initialY = layoutParams.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    return false
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - initialTouchX).toInt()
                    val dy = (event.rawY - initialTouchY).toInt()
                    layoutParams.x = initialX - dx
                    layoutParams.y = initialY + dy
                    windowManager.updateViewLayout(v, layoutParams)
                    return true
                }
            }
            return false
        }
    }

    companion object {
        fun start(context: Context) {
            Log.i("ResumeForge.Overlay", "start")
            val intent = Intent(context, OverlayCaptureService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            Log.i("ResumeForge.Overlay", "stop")
            context.stopService(Intent(context, OverlayCaptureService::class.java))
        }
    }
}
