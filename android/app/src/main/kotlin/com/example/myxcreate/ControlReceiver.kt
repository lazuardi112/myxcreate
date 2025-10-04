package com.example.myxcreate

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ControlReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ControlReceiver"
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        private const val K_PREFS_ENABLED = "xc_listener_enabled"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        val prefs = context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
        when (action) {
            ForegroundStarterService.ACTION_START -> {
                prefs.edit().putBoolean(K_PREFS_ENABLED, true).apply()
                Log.i(TAG, "ControlReceiver: START -> enabled=true")
            }
            ForegroundStarterService.ACTION_STOP -> {
                prefs.edit().putBoolean(K_PREFS_ENABLED, false).apply()
                Log.i(TAG, "ControlReceiver: STOP -> enabled=false")
            }
            else -> {
                // ignore
            }
        }
    }
}
