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
        Log.i(TAG, "AccessibilityService connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
            handleNotification(event)
        }
    }

    private fun handleNotification(event: AccessibilityEvent) {
        try {
            val packageName = event.packageName?.toString() ?: "unknown"

            // gabungkan semua text dari event.text
            val textSb = StringBuilder()
            event.text?.forEach { t -> if (t != null) textSb.append(t) }

            // ambil title/body dari Notification jika tersedia
            var title: String? = null
            var body: String? = null
            try {
                val parcelable = event.parcelableData
                if (parcelable is Notification) {
                    val extras: Bundle? = parcelable.extras
                    title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
                    body = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                    if (body.isNullOrEmpty()) {
                        body = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                            ?: extras?.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Can't extract Notification: ${e.message}")
            }

            val finalTitle = title ?: "(tanpa judul)"
            val finalBody = body ?: if (textSb.isNotEmpty()) textSb.toString() else "(kosong)"
            val timestamp = System.currentTimeMillis()

            Log.d(TAG, "Notif recv from=$packageName title='$finalTitle' body='$finalBody'")

            // save log ke SharedPreferences
            saveLogToPrefs(finalTitle, finalBody, timestamp, packageName)

            // kirim broadcast supaya Flutter bisa menerima
            sendBroadcastToFlutter(finalTitle, finalBody, timestamp)

            // POST ke server jika ada URL
            val postUrl = readPref("notif_post_url")
            val authToken = readPref("notif_auth_token")
            if (!postUrl.isNullOrEmpty()) {
                executor.execute {
                    postJsonWithRetry(postUrl, finalTitle, finalBody, timestamp, packageName, authToken)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "handleNotification error", e)
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

    // ================== Helpers ==================

    private fun sendBroadcastToFlutter(title: String, text: String, timestamp: Long) {
        try {
            val intent = Intent("com.example.myxcreate.NOTIF_EVENT")
            intent.putExtra("title", title)
            intent.putExtra("text", text)
            intent.putExtra("time", timestamp)
            applicationContext.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Failed send broadcast: ${e.message}")
        }
    }

    private fun readPref(key: String): String? {
        return try {
            val prefs = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )
            prefs.getString(key, null)
        } catch (e: Exception) {
            null
        }
    }

    private fun saveLogToPrefs(title: String, text: String, timestamp: Long, packageName: String) {
        try {
            val prefs = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )

            // 1) notif_logs_native (JSONArray)
            val existingJson = prefs.getString("notif_logs_native", "[]")
            val arr = try {
                JSONArray(existingJson)
            } catch (e: Exception) {
                JSONArray()
            }

            val entry = JSONObject().apply {
                put("app", packageName)
                put("title", title)
                put("text", text)
                put("time", timestamp)
            }

            val newArr = JSONArray().apply {
                put(entry)
                for (i in 0 until arr.length()) put(arr.get(i))
            }

            val max = 1000
            val trimmed = JSONArray()
            for (i in 0 until Math.min(newArr.length(), max)) trimmed.put(newArr.get(i))

            prefs.edit().putString("notif_logs_native", trimmed.toString()).apply()

            // 2) notif_logs as LinkedHashSet untuk Flutter
            val existingSet = prefs.getStringSet("notif_logs", LinkedHashSet<String>())!!
            val newSet = LinkedHashSet<String>()
            newSet.add(entry.toString())
            newSet.addAll(existingSet)
            while (newSet.size > max) {
                val it = newSet.iterator()
                if (it.hasNext()) it.next(); it.remove()
            }
            prefs.edit().putStringSet("notif_logs", newSet).apply()

            // 3) last_notif_title & last_notif_text
            prefs.edit().putString("last_notif_title", title)
            prefs.edit().putString("last_notif_text", text).apply()

        } catch (e: Exception) {
            Log.e(TAG, "saveLogToPrefs error", e)
        }
    }

    private fun postJsonWithRetry(
        urlStr: String,
        title: String,
        text: String,
        timestamp: Long,
        packageName: String,
        authToken: String?
    ) {
        var attempt = 0
        var backoff = BASE_BACKOFF_MS
        while (attempt < MAX_RETRIES) {
            attempt++
            try {
                val code = postJson(urlStr, title, text, timestamp, packageName, authToken)
                Log.i(TAG, "POST attempt #$attempt -> HTTP $code")
                if (code in 200..299) return
            } catch (e: Exception) {
                Log.e(TAG, "POST attempt #$attempt failed: ${e.message}")
            }
            try { Thread.sleep(backoff) } catch (ignored: InterruptedException) {}
            backoff *= 2
        }
        Log.e(TAG, "POST failed after $MAX_RETRIES attempts to $urlStr")
    }

    private fun postJson(
        urlStr: String,
        title: String,
        text: String,
        timestamp: Long,
        packageName: String,
        authToken: String?
    ): Int {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL(urlStr)
            conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 15000
                requestMethod = "POST"
                doOutput = true
                setRequestProperty("Content-Type", "application/json; utf-8")
                setRequestProperty("Accept", "application/json")
                setRequestProperty("User-Agent", "MyXCreate-AccessibilityService/${Build.VERSION.SDK_INT}")
                if (!authToken.isNullOrEmpty()) setRequestProperty("Authorization", authToken)
            }

            val payload = JSONObject().apply {
                put("app", packageName)
                put("title", title)
                put("text", text)
                put("timestamp", timestamp)
            }

            val out: OutputStream = BufferedOutputStream(conn.outputStream)
            out.write(payload.toString().toByteArray(StandardCharsets.UTF_8))
            out.flush()
            out.close()

            conn.responseCode
        } finally {
            conn?.disconnect()
        }
    }
}
