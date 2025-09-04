package com.example.myxcreate

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent
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
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var startedForeground = false

    companion object {
        private const val NOTIF_CHANNEL_ID = "xc_accessibility_channel"
        private const val NOTIF_CHANNEL_NAME = "XCreate Accessibility"
        private const val NOTIF_ID = 9801
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "onServiceConnected() - Accessibility service ready")

        // Konfigurasi event yang ingin didengar (notification + content/window changes)
        val info = AccessibilityServiceInfo()
        info.eventTypes = AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED or
                          AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                          AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.notificationTimeout = 100
        // dengarkan semua package (null = semua), bisa di-set pake package list
        info.packageNames = null
        // beberapa flag opsional
        info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS

        this.serviceInfo = info

        // Start foreground notification supaya service lebih jarang dibunuh oleh OS
        startForegroundIfNeeded()
    }

    private fun startForegroundIfNeeded() {
        if (startedForeground) return

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(NOTIF_CHANNEL_ID, NOTIF_CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW)
            ch.description = "Menjaga XCreate accessibility listener tetap aktif"
            nm.createNotificationChannel(ch)
        }

        // Optional: jika ingin membuka aplikasi saat notif diklik
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: Intent(this, javaClass)
        val pi = PendingIntent.getActivity(this, 0, intent, if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

        val nb = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, NOTIF_CHANNEL_ID)
        } else {
            android.app.Notification.Builder(this)
        }
        val notification = nb
            .setContentTitle("XCreate Notif Listener")
            .setContentText("Mendengarkan event notifikasi & accessibility")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()

        startForeground(NOTIF_ID, notification)
        startedForeground = true
        Log.i(TAG, "Service started in foreground")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        try {
            // Fokus pada notifikasi (TYPE_NOTIFICATION_STATE_CHANGED) karena ini untuk "incoming notifications"
            if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
                handleNotificationEvent(event)
            } else {
                // jika ingin, kamu bisa juga catat window/content events
                // handleGenericEvent(event)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error onAccessibilityEvent: ${e.message}", e)
        }
    }

    private fun handleNotificationEvent(event: AccessibilityEvent) {
        val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val defaultPrefs = getSharedPreferences(packageName + "_preferences", Context.MODE_PRIVATE) // fallback

        // ambil data notifikasi dari parcelable (umumnya android.app.Notification)
        var title = ""
        var text = ""
        try {
            val parcel = event.parcelableData
            if (parcel is Notification) {
                val extras = parcel.extras
                title = extras?.getString(Notification.EXTRA_TITLE) ?: ""
                // EXTRA_TEXT bisa berupa CharSequence
                val t = extras?.getCharSequence(Notification.EXTRA_TEXT)
                text = t?.toString() ?: ""
                // beberapa apps menyimpan bigText / textLines
                val bigText = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)
                if (bigText != null && bigText.toString().isNotEmpty()) {
                    text = bigText.toString()
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Tidak dapat extract Notification parcelable: ${e.message}")
        }

        // fallback: gunakan event.text jika kosong
        if (text.isEmpty()) {
            text = event.text?.joinToString(" ") ?: ""
        }
        if (title.isEmpty()) {
            title = event.packageName?.toString() ?: ""
        }

        val pkgName = event.packageName?.toString() ?: "unknown"
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())

        // simpan ke shared prefs (format JSON string agar Flutter mudah parse)
        val entry = JSONObject()
        entry.put("app", pkgName)
        entry.put("title", title)
        entry.put("text", text)
        entry.put("time", System.currentTimeMillis())
        entry.put("time_iso", timestamp)

        appendJsonArrayPref(prefs, "notif_logs_native", entry)
        appendJsonArrayPref(defaultPrefs, "notif_logs_native", entry) // juga simpan di fallback

        // Simpan last notification keys (nama key sesuai kode Flutter-mu sebelumnya)
        prefs.edit().putString("last_notif_title", title).putString("last_notif_text", text).apply()
        defaultPrefs.edit().putString("last_notif_title", title).putString("last_notif_text", text).apply()

        // POST ke server jika ada URL
        val postUrl = prefs.getString("notif_post_url", null) ?: defaultPrefs.getString("notif_post_url", null)
        if (!postUrl.isNullOrEmpty()) {
            // jalankan POST di background coroutine
            serviceScope.launch {
                performPost(postUrl, pkgName, title, text)
            }
        }
    }

    private fun appendJsonArrayPref(prefs: SharedPreferences, key: String, obj: JSONObject) {
        try {
            val existing = prefs.getString(key, null)
            val arr = if (existing != null && existing.isNotEmpty()) {
                JSONArray(existing)
            } else {
                JSONArray()
            }
            // insert di index 0 supaya paling baru ada di depan
            val newArr = JSONArray()
            newArr.put(obj)
            for (i in 0 until arr.length()) {
                newArr.put(arr.get(i))
            }
            prefs.edit().putString(key, newArr.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "appendJsonArrayPref error: ${e.message}", e)
        }
    }

    private suspend fun performPost(url: String, pkg: String, title: String, text: String) {
        try {
            val payload = JSONObject()
            payload.put("app", pkg)
            payload.put("title", title)
            payload.put("text", text)
            payload.put("timestamp", System.currentTimeMillis())

            val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()
            val body = payload.toString().toRequestBody(mediaType)

            val request = Request.Builder().url(url).post(body).build()
            client.newCall(request).execute().use { resp ->
                val respBody = resp.body?.string() ?: ""
                val log = "POST -> ${resp.code} : $respBody"
                Log.i(TAG, log)
                // Simpan ke post_logs (FlutterSharedPreferences)
                val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val postObj = JSONObject()
                postObj.put("url", url)
                postObj.put("body", payload)
                postObj.put("code", resp.code)
                postObj.put("response", respBody)
                postObj.put("timestamp", System.currentTimeMillis())
                appendJsonArrayPref(prefs, "post_logs", postObj)
            }
        } catch (e: Exception) {
            Log.e(TAG, "performPost error: ${e.message}", e)
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val errObj = JSONObject()
            errObj.put("url", url)
            errObj.put("error", e.message ?: "unknown")
            errObj.put("timestamp", System.currentTimeMillis())
            appendJsonArrayPref(prefs, "post_logs", errObj)
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "Accessibility service interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
        Log.i(TAG, "Service destroyed")
    }
}
