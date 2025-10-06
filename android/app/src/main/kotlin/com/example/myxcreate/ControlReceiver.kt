package com.example.myxcreate

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: ""
        Log.d("ControlReceiver", "received action: $action")
        // set enabled flag false di prefs dan stop ForegroundStarterService
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
        prefs.putBoolean("xc_listener_enabled", false)
        prefs.apply()

        // stop ForegroundStarterService
        try {
            val stop = Intent(context, ForegroundStarterService::class.java)
            context.stopService(stop)
        } catch (e: Exception) {
            Log.w("ControlReceiver", "stop service error: $e")
        }
    }
}
