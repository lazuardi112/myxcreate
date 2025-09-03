// File: android/app/src/main/kotlin/com/example/myxcreate/MyAccessibilityService.kt
package com.example.myxcreate

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedOutputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.LinkedHashSet
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MyAccessibilityService : AccessibilityService() {

    private val TAG = "MyAccessibilitySvc"
    private val executor = Executors.newSingleThreadExecutor()

    // Retry config
    private val MAX_RETRIES = 3
    private val BASE_BACKOFF_MS = 1000L // 1s -> 2s -> 4s

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "AccessibilityService connected (pkg=${applicationContext.packageName})")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        try {
            if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
                val packageName = event.packageName?.toString() ?: ""

                // gabungkan semua text dari event.text
                val textSb = StringBuilder()
                val texts = event.text
                if (texts != null) {
                    for (t in texts) {
                        if (t != null) textSb.append(t)
                    }
                }

                // coba ambil title/body dari parcelable Notification (jika tersedia)
                var title: String? = null
                var body: String? = null
                try {
                    val parcelable = event.parcelableData
                    if (parcelable is Notification) {
                        val extras: Bundle? = parcelable.extras
                        if (extras != null) {
                            // EXTRA_TITLE, EXTRA_TEXT
                            title = extras.getString(Notification.EXTRA_TITLE)
                                ?: extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
                            body = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                            // kadang ada bigText/summaryText
                            if (body.isNullOrEmpty()) {
                                body = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                                    ?: extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Can't extract Notification parcelable: ${e.message}")
                }

                val finalTitle = title ?: "(tanpa judul)"
                val finalBody = when {
                    !body.isNullOrEmpty() -> body!!
                    textSb.isNotEmpty() -> textSb.toString()
                    else -> "(kosong)"
                }

                val timestamp = System.currentTimeMillis()

                Log.d(TAG, "Notif recv from=$packageName title='$finalTitle' body='$finalBody'")

                // read postUrl and optional auth token from Flutter SharedPreferences
                val postUrl = readPostUrlFromPrefs()
                val authToken = readAuthTokenFromPrefs()

                // build payload
                val payload = JSONObject()
                payload.put("app", packageName)
                payload.put("title", finalTitle)
                payload.put("text", finalBody)
                payload.put("timestamp", timestamp)

                // save to prefs (native log) immediately — THIS now also updates notif_logs (string set) & last_notif_*
                saveLogToPrefs(finalTitle, finalBody, timestamp, packageName)

                // send broadcast so Dart can optionally listen (action com.example.myxcreate.NOTIF_EVENT)
                try {
                    val b = Intent("com.example.myxcreate.NOTIF_EVENT")
                    b.putExtra("title", finalTitle)
                    b.putExtra("text", finalBody)
                    b.putExtra("time", timestamp)
                    applicationContext.sendBroadcast(b)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed send broadcast: ${e.message}")
                }

                // Post to server (background)
                if (!postUrl.isNullOrEmpty()) {
                    executor.execute {
                        postJsonWithRetry(postUrl, payload.toString(), authToken)
                    }
                } else {
                    Log.w(TAG, "notif_post_url not configured - skipping POST")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception onAccessibilityEvent", e)
        }
    }

    override fun onInterrupt() {
        Log.i(TAG, "AccessibilityService interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            executor.shutdown()
            executor.awaitTermination(1, TimeUnit.SECONDS)
        } catch (ignored: Exception) {}
        Log.i(TAG, "AccessibilityService destroyed")
    }

    // ---------------- Helper: Read Post URL ----------------
    private fun readPostUrlFromPrefs(): String? {
        return try {
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val candidates = listOf("notif_post_url", "flutter.notif_post_url", "post_url", "flutter.post_url")
            for (k in candidates) {
                val v = prefs.getString(k, null)
                if (!v.isNullOrEmpty()) {
                    Log.d(TAG, "Found postUrl using key='$k'")
                    return v
                }
            }
            null
        } catch (e: Exception) {
            Log.e(TAG, "readPostUrlFromPrefs error: ${e.message}")
            null
        }
    }

    // ---------------- Helper: Read Auth Token (optional) ----------------
    private fun readAuthTokenFromPrefs(): String? {
        return try {
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val candidates = listOf("notif_auth_token", "flutter.notif_auth_token", "auth_token", "flutter.auth_token")
            for (k in candidates) {
                val v = prefs.getString(k, null)
                if (!v.isNullOrEmpty()) {
                    Log.d(TAG, "Found auth token using key='$k'")
                    return v
                }
            }
            null
        } catch (e: Exception) {
            Log.e(TAG, "readAuthTokenFromPrefs error: ${e.message}")
            null
        }
    }

    // ---------------- Helper: Save Log to SharedPreferences (native & compatible with Flutter) ----------------
    private fun saveLogToPrefs(title: String, text: String, timestamp: Long, packageName: String) {
        try {
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            // --- 1) notif_logs_native as JSON array string (keamanan urutan & mudah parsing) ---
            val existingJson = prefs.getString("notif_logs_native", null)
            val arr = if (!existingJson.isNullOrEmpty()) {
                try {
                    JSONArray(existingJson)
                } catch (e: Exception) {
                    JSONArray()
                }
            } else {
                JSONArray()
            }

            val entry = JSONObject()
            entry.put("app", packageName)
            entry.put("title", title)
            entry.put("text", text)
            entry.put("time", timestamp)

            // insert at start (most recent first)
            val newArr = JSONArray()
            newArr.put(entry)
            for (i in 0 until arr.length()) {
                newArr.put(arr.get(i))
            }

            // keep up to 1000 entries
            val max = 1000
            val trimmed = JSONArray()
            for (i in 0 until Math.min(newArr.length(), max)) {
                trimmed.put(newArr.get(i))
            }

            prefs.edit().putString("notif_logs_native", trimmed.toString()).apply()

            // --- 2) notif_logs as StringSet for Flutter getStringList compatibility ---
            // Flutter's SharedPreferences on Android maps stringList -> Set<String> under the hood.
            // We'll maintain a LinkedHashSet to help preserve insertion order.
            val existingSet = prefs.getStringSet("notif_logs", null)
            val list = ArrayList<String>()

            // Convert existing set -> list (if present). Note: set may not guarantee order, but usually works.
            if (existingSet != null) {
                // try to preserve previous order by adding all; if it was a LinkedHashSet before, order kept.
                for (s in existingSet) list.add(s)
            }

            // new log entry as JSON string (same as above)
            val logJsonString = entry.toString()

            // Insert at beginning
            list.add(0, logJsonString)

            // Trim to max
            if (list.size > max) {
                while (list.size > max) {
                    list.removeAt(list.size - 1)
                }
            }

            // Convert back to LinkedHashSet to preserve insertion order
            val newSet = LinkedHashSet<String>()
            for (s in list) newSet.add(s)

            prefs.edit().putStringSet("notif_logs", newSet).apply()

            // --- 3) also update last_notif_title & last_notif_text for quick access ---
            prefs.edit().putString("last_notif_title", title).putString("last_notif_text", text).apply()

            Log.d(TAG, "Saved native log (total=${trimmed.length()}) and updated notif_logs (size=${newSet.size})")
        } catch (e: Exception) {
            Log.e(TAG, "saveLogToPrefs error", e)
        }
    }

    // ---------------- Helper: POST JSON with retry ----------------
    private fun postJsonWithRetry(endpoint: String, jsonBody: String, authToken: String?) {
        var attempt = 0
        var backoff = BASE_BACKOFF_MS
        while (attempt < MAX_RETRIES) {
            attempt++
            try {
                val code = postJson(endpoint, jsonBody, authToken)
                Log.i(TAG, "POST attempt #$attempt to $endpoint -> HTTP $code")
                if (code in 200..299) {
                    // success
                    return
                } else {
                    Log.w(TAG, "Non-2xx response: $code")
                }
            } catch (e: Exception) {
                Log.e(TAG, "POST attempt #$attempt failed: ${e.message}")
            }

            try { Thread.sleep(backoff) } catch (ignored: InterruptedException) {}
            backoff *= 2
        }
        Log.e(TAG, "POST failed after $MAX_RETRIES attempts to $endpoint")
    }

    // ---------------- Helper: actual POST ----------------
    private fun postJson(endpoint: String, jsonBody: String, authToken: String?): Int {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL(endpoint)
            conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 15000
                requestMethod = "POST"
                doOutput = true
                setRequestProperty("Content-Type", "application/json; utf-8")
                setRequestProperty("Accept", "application/json")
                setRequestProperty("User-Agent", "MyXCreate-AccessibilityService/${Build.VERSION.SDK_INT}")
                if (!authToken.isNullOrEmpty()) {
                    setRequestProperty("Authorization", authToken)
                }
            }

            val out: OutputStream = BufferedOutputStream(conn.outputStream)
            val bytes = jsonBody.toByteArray(StandardCharsets.UTF_8)
            out.write(bytes)
            out.flush()
            out.close()

            conn.responseCode
        } finally {
            conn?.disconnect()
        }
    }
}
