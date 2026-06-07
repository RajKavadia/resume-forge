package com.example.resumetailor.system

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.example.resumetailor.capture.OverlayCaptureService

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        Log.i("ResumeForge.Boot", "BOOT_COMPLETED received")
        OverlayCaptureService.start(context)
    }
}

