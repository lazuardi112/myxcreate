// File: android/app/src/main/kotlin/com/example/myxcreate/MyAccessibilityService.kt
// GANTI package name di bawah sesuai applicationId Anda
package com.example.myxcreate

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import org.json.JSONObject
import java.io.BufferedOutputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MyAccessibilityService : AccessibilityService() {

    private val TAG = "MyAccessibilitySvc"
    private val executor = Executors.newSingleThreadExecutor()

    // Retry config
    private val MAX_RETRIES = 3
    private val BASE_BACKOFF_MS = 1000L // 1s, akan menjadi 1s, 2s, 4s

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "AccessibilityService connected (package=${applicationContext.packageName})")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        try {
            if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
                // Ambil paket pengirim
                val packageName = event.packageName?.toString() ?: ""

                // Ambil teks dari event.text
                val textSb = StringBuilder()
                val texts = event.text
                if (texts != null) {
                    for (t in texts) {
                        if (t != null) textSb.append(t)
                    }
                }

                // Coba ambil detail dari Notification jika tersedia (parcelableData)
                var title: String? = null
                var body: String? = null
                try {
                    val parcelable = event.parcelableData
                    if (parcelable is Notification) {
                        val extras: Bundle? = parcelable.extras
                        if (extras != null) {
                            title = extras.getString(Notification.EXTRA_TITLE) ?: extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
                            // EXTRA_TEXT bisa berupa CharSequence
                            val textCs = extras.getCharSequence(Notification.EXTRA_TEXT)
                            body = textCs?.toString()
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Cannot extract Notification parcelable: ${e.message}")
                }

                // Fallback: gunakan textSb kalau body kosong
                val finalTitle = title ?: ""
                val finalBody = when {
                    !body.isNullOrEmpty() -> body
                    textSb.isNotEmpty() -> textSb.toString()
                    else -> ""
                }

                val timestamp = System.currentTimeMillis()

                Log.d(TAG, "Notif received from=$packageName title='$finalTitle' body='$finalBody'")

                // Baca postUrl dari SharedPreferences Flutter
                val postUrl = readPostUrlFromPrefs()
                if (postUrl.isNullOrEmpty()) {
                    Log.w(TAG, "postUrl not configured (no POST will be sent).")
                    return
                }

                // Optional: ambil token/authorization jika ada
                val authToken = readAuthTokenFromPrefs()

                // Build JSON payload
                val payload = JSONObject()
                payload.put("app", packageName)
                payload.put("title", finalTitle)
                payload.put("text", finalBody)
                payload.put("timestamp", timestamp)

                // Kirim POST di background thread
                executor.execute {
                    postJsonWithRetry(postUrl, payload.toString(), authToken)
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
        } catch (ignored: Exception) {
        }
        Log.i(TAG, "AccessibilityService destroyed")
    }

    // ---------------- Helpers ----------------

    /**
     * Baca post URL dari SharedPreferences yang dipakai Flutter (file "FlutterSharedPreferences").
     * Flutter menyimpan key sesuai yang dipakai di kode Dart. Kita mencoba beberapa kemungkinan nama key.
     * Pastikan di Flutter Anda set key 'notif_post_url' (dalam contoh Dart Anda memang pakai key tersebut).
     */
    private fun readPostUrlFromPrefs(): String? {
        return try {
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            // Keys yang dicoba (urutkan sesuai prioritas)
            val candidates = listOf("notif_post_url", "flutter.notif_post_url", "post_url", "flutter.post_url")

            for (k in candidates) {
                val v = prefs.getString(k, null)
                if (!v.isNullOrEmpty()) {
                    Log.d(TAG, "Found postUrl using key='$k'")
                    return v
                }
            }

            // Jika tidak ditemukan, kembalikan null
            Log.d(TAG, "No postUrl found in FlutterSharedPreferences")
            null
        } catch (e: Exception) {
            Log.e(TAG, "readPostUrlFromPrefs error", e)
            null
        }
    }

    /**
     * Baca optional auth token dari prefs (jika Anda menyimpan)
     */
    private fun readAuthTokenFromPrefs(): String? {
        return try {
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            // coba beberapa key umum
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
            Log.e(TAG, "readAuthTokenFromPrefs error", e)
            null
        }
    }

    /**
     * POST JSON dengan retry/backoff sederhana.
     */
    private fun postJsonWithRetry(endpoint: String, jsonBody: String, authToken: String?) {
        var attempt = 0
        var backoff = BASE_BACKOFF_MS
        while (attempt < MAX_RETRIES) {
            attempt++
            try {
                val code = postJson(endpoint, jsonBody, authToken)
                Log.i(TAG, "POST attempt #$attempt to $endpoint -> HTTP $code")
                // treat 2xx as success
                if (code in 200..299) {
                    return
                } else {
                    Log.w(TAG, "Non-2xx response, will retry if attempts left")
                }
            } catch (e: Exception) {
                Log.e(TAG, "POST attempt #$attempt failed: ${e.message}")
            }

            // backoff sebelum retry (tidak blocking UI thread, karena di executor)
            try {
                Thread.sleep(backoff)
            } catch (ignored: InterruptedException) {
            }
            backoff *= 2
        }
        Log.e(TAG, "POST failed after $MAX_RETRIES attempts to $endpoint")
    }

    /**
     * Post JSON ke endpoint, return HTTP response code.
     */
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

            val responseCode = conn.responseCode
            responseCode
        } finally {
            conn?.disconnect()
        }
    }
}
