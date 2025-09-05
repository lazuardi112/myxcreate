package com.example.myxcreate

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import android.content.SharedPreferences
import android.preference.PreferenceManager
import kotlinx.coroutines.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

class MyNotificationListenerService : NotificationListenerService() {
    private val TAG = "MyNotificationListener"
    private val client = OkHttpClient()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        try {
            val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(this)
            val postUrl = prefs.getString("notif_post_url", null) ?: ""
            val pkg = sbn.packageName ?: "unknown"
            val ticker = sbn.notification.tickerText?.toString() ?: ""
            val extras = sbn.notification.extras
            val title = extras?.getString("android.title") ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ticker
            val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())

            // save native logs
            saveNativeLog(prefs, pkg, title, text, timestamp)

            if (postUrl?.isNotEmpty() == true) {
                scope.launch {
                    try {
                        val payload = JSONObject()
                        payload.put("package", pkg)
                        payload.put("title", title)
                        payload.put("text", text)
                        payload.put("time", timestamp)
                        val body = payload.toString().toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull())
                        val req = Request.Builder().url(postUrl).post(body).build()
                        client.newCall(req).execute().use { resp ->
                            val respBody = resp.body?.string() ?: ""
                            val log = "POST_NOTIF ${resp.code} -> $respBody"
                            savePostLog(prefs, log)
                            Log.i(TAG, log)
                        }
                    } catch (e: Exception) {
                        val err = "POST_NOTIFY ERROR: ${e.localizedMessage}"
                        savePostLog(prefs, err)
                        Log.e(TAG, err, e)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "onNotificationPosted error", e)
        }
    }

    private fun saveNativeLog(prefs: SharedPreferences, pkg: String, title: String, text: String, timestamp: String) {
        try {
            val raw = prefs.getString("notif_logs_native", "[]")
            val arr = JSONArray(raw)
            val obj = JSONObject()
            obj.put("package", pkg)
            obj.put("title", title)
            obj.put("text", text)
            obj.put("time", timestamp)
            arr.put(obj)
            prefs.edit().putString("notif_logs_native", arr.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "saveNativeLog error", e)
        }
    }

    private fun savePostLog(prefs: SharedPreferences, log: String) {
        try {
            val raw = prefs.getString("post_logs", "[]")
            val arr = JSONArray(raw)
            val obj = JSONObject()
            obj.put("log", log)
            obj.put("time", SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date()))
            arr.put(obj)
            prefs.edit().putString("post_logs", arr.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "savePostLog error", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }
}
