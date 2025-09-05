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
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

class MyAccessibilityService : AccessibilityService() {
    private val TAG = "MyAccessibilityService"
    private val client = OkHttpClient()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        try {
            val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(this)
            val postUrl = prefs.getString("notif_post_url", null) ?: ""
            val togglesJson = prefs.getString("notif_app_toggles", null) ?: "{}"

            // parse toggles (flutter menyimpan JSON string)
            val toggles = try {
                JSONObject(togglesJson)
            } catch (e: Exception) {
                JSONObject()
            }

            // extract text
            val pkg = event.packageName?.toString() ?: "unknown"
            val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())

            val eventText = buildString {
                if (event.text != null && event.text.isNotEmpty()) {
                    append(event.text.joinToString(" "))
                } else {
                    val cd = event.contentDescription
                    if (cd != null) append(cd.toString())
                }
            }.trim()

            // check toggle: if present and false => skip
            if (toggles.has(pkg)) {
                val allowed = toggles.optBoolean(pkg, true)
                if (!allowed) {
                    Log.d(TAG, "Package $pkg toggled OFF, skip")
                    return
                }
            }
            // else if not present => default allow

            // save native logs into prefs as JSON array (notif_logs_native)
            saveNativeLog(prefs, pkg, eventText, timestamp)

            // post if configured and event has text
            if (postUrl.isNotEmpty() && eventText.isNotEmpty()) {
                scope.launch {
                    try {
                        val payloadObj = JSONObject()
                        payloadObj.put("package", pkg)
                        payloadObj.put("text", eventText)
                        payloadObj.put("time", timestamp)
                        val payload = payloadObj.toString()

                        val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()
                        val body = payload.toRequestBody(mediaType)
                        val request = Request.Builder().url(postUrl).post(body).build()
                        client.newCall(request).execute().use { resp ->
                            val respBody = resp.body?.string() ?: ""
                            val log = "POST ${resp.code} -> $respBody"
                            savePostLog(prefs, log)
                            Log.i(TAG, log)
                        }
                    } catch (ex: Exception) {
                        val err = "POST ERROR: ${ex.localizedMessage}"
                        savePostLog(prefs, err)
                        Log.e(TAG, err, ex)
                    }
                }
            }
        } catch (ex: Exception) {
            Log.e(TAG, "onAccessibilityEvent error", ex)
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "AccessibilityService interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }

    private fun saveNativeLog(prefs: SharedPreferences, pkg: String, text: String, timestamp: String) {
        try {
            val raw = prefs.getString("notif_logs_native", "[]")
            val arr = JSONArray(raw)
            val obj = JSONObject()
            obj.put("package", pkg)
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
}
