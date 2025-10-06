package com.example.myxcreate

import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — menangani MethodChannel dari Flutter:
 *  - "startForeground" -> memulai ForegroundStarterService (agar service native tetap hidup)
 *  - "stopForeground"  -> menghentikan ForegroundStarterService
 *
 * Pastikan kelas ForegroundStarterService ada di package yang sama dan dideklarasikan
 * di AndroidManifest.xml. Gunakan applicationContext saat memulai/stop service untuk menghindari
 * masalah ketika Activity sedang tidak aktif.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.example.myxcreate/xc_service"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForeground" -> {
                        val ok = startForegroundServiceNative()
                        result.success(ok)
                    }
                    "stopForeground" -> {
                        val ok = stopForegroundServiceNative()
                        result.success(ok)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Start ForegroundStarterService in a safe way.
     * Returns true if the start request was issued successfully, false otherwise.
     */
    private fun startForegroundServiceNative(): Boolean {
        return try {
            val intent = Intent(applicationContext, ForegroundStarterService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(applicationContext, intent)
            } else {
                applicationContext.startService(intent)
            }
            Log.i(TAG, "Requested startForegroundService")
            true
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start ForegroundStarterService", t)
            false
        }
    }

    /**
     * Stop ForegroundStarterService.
     * Returns true if stop request issued, false if an error occurred.
     */
    private fun stopForegroundServiceNative(): Boolean {
        return try {
            val intent = Intent(applicationContext, ForegroundStarterService::class.java)
            val stopped = applicationContext.stopService(intent)
            Log.i(TAG, "Requested stopForegroundService - result: $stopped")
            stopped
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to stop ForegroundStarterService", t)
            false
        }
    }
}
