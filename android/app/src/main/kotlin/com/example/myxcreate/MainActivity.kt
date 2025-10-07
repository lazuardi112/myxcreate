// android/app/src/main/kotlin/com/example/myxcreate/MainActivity.kt
package com.example.myxcreate

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.content.SharedPreferences
import com.google.gson.Gson

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.myxcreate/xc_service"
    private val prefsName = "FlutterSharedPreferences" // matches plugin default? We'll use package-specific prefs instead
    private val nativePrefsName = "myxcreate_prefs"

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
                "updateSettings" -> {
                    // Expect payload map with selectedPackages, postUrl, enabled
                    val args = call.arguments as? Map<*, *>
                    if (args != null) {
                        saveSettingsToPrefs(args)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "updateSettings requires a map", null)
                    }
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

    private fun saveSettingsToPrefs(args: Map<*, *>) {
        val sp = getSharedPreferences(nativePrefsName, Context.MODE_PRIVATE)
        val editor = sp.edit()
        // selectedPackages is list
        val gson = Gson()
        val selected = args["selectedPackages"]
        if (selected != null) {
            editor.putString("selectedPackagesJson", gson.toJson(selected))
        }
        val postUrl = args["postUrl"] as? String
        if (postUrl != null) editor.putString("postUrl", postUrl)
        val enabled = args["enabled"] as? Boolean
        if (enabled != null) editor.putBoolean("enabled", enabled)
        editor.apply()
    }
}
