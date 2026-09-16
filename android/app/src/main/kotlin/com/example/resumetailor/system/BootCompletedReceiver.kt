package com.example.resumetailor.system

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.example.resumetailor.capture.OverlayCaptureService

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        // Accessibility services and WorkManager are system-managed. Do not
        // start the overlay at boot: doing so bypasses the user's explicit
        // capture choice and can fail on Android background-start restrictions.
        // WorkManager restores persisted monitoring work independently.
        Log.i("ResumeForge.Boot", "BOOT_COMPLETED received; no overlay auto-start")
    }
}

