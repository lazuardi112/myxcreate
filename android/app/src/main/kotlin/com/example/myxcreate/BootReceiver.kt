package com.example.myxcreate

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val enabled = prefs.getBoolean("xc_listener_enabled", false)
            if (enabled) {
                try {
                    val i = Intent(context, ForegroundStarterService::class.java)
                    ContextCompat.startForegroundService(context, i)
                    Log.d("BootReceiver", "Started ForegroundStarterService on boot")
                } catch (e: Exception) {
                    Log.w("BootReceiver", "failed start on boot: $e")
                }
            }
        }
    }
}
