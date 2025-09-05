package com.example.myxcreate

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.content.SharedPreferences
import android.preference.PreferenceManager
import android.util.Log
import kotlinx.coroutines.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.text.SimpleDateFormat
import java.util.*

class MyAccessibilityService : AccessibilityService() {
    private val TAG = "MyAccessibilityService"
    private val client = OkHttpClient()
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(this)

        // ambil daftar aplikasi yang diizinkan dari XcappPage (disimpan di SharedPreferences)
        val allowedApps = prefs.getStringSet("allowed_apps", emptySet()) ?: emptySet()
        val postUrl = prefs.getString("notif_post_url", null)

        val eventText = event.text?.joinToString(" ") ?: ""
        val pkgName = event.packageName?.toString() ?: "unknown"
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())

        val logEntry = "[$timestamp][$pkgName] $eventText"

        // simpan semua event notifikasi, walaupun tidak dipost
        saveLogToPrefs(prefs, logEntry)

        // cek apakah aplikasi ini termasuk dalam daftar yang dipilih user
        if (!allowedApps.contains(pkgName)) {
            Log.i(TAG, "Lewati event dari $pkgName (tidak diizinkan)")
            return
        }

        // jika ada URL dan teks notifikasi valid -> lakukan POST
        if (!postUrl.isNullOrEmpty() && eventText.isNotEmpty()) {
            serviceScope.launch {
                try {
                    val payload = """{"package":"$pkgName","text":"$eventText","time":"$timestamp"}"""
                    val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()
                    val body = payload.toRequestBody(mediaType)

                    val request = Request.Builder()
                        .url(postUrl)
                        .post(body)
                        .build()

                    client.newCall(request).execute().use { response ->
                        val respMsg = response.body?.string() ?: "no response"
                        val postLog = "[$timestamp] POST -> ${response.code} : $respMsg"
                        savePostLogToPrefs(prefs, postLog)
                        Log.i(TAG, postLog)
                    }
                } catch (e: Exception) {
                    val err = "[$timestamp] POST ERROR: ${e.message}"
                    savePostLogToPrefs(prefs, err)
                    Log.e(TAG, err, e)
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

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
    }
}
