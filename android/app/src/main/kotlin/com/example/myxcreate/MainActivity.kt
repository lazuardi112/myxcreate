package com.example.myxcreate

import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.myxcreate/xc_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForeground" -> {
                    startForegroundServiceNative()
                    result.success(true)
                }
                "stopForeground" -> {
                    stopForegroundServiceNative()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startForegroundServiceNative() {
        val intent = Intent(this, ForegroundStarterService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(this, intent)
        } else {
            startService(intent)
        }
    }

    private fun stopForegroundServiceNative() {
        val intent = Intent(this, ForegroundStarterService::class.java)
        stopService(intent)
    }
}
