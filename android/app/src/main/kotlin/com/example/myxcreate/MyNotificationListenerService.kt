package com.example.myxcreate   // Ganti sesuai packageName app kamu

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import okhttp3.*
import java.io.IOException
import java.util.concurrent.TimeUnit

class MyNotificationListenerService : NotificationListenerService() {
    companion object {
        private const val TAG = "MyNotifListenerSvc"
        private const val CHANNEL_ID = "xc_listener_channel"
        private const val CHANNEL_NAME = "XC Listener Service"
        private const val ONGOING_NOTIFICATION_ID = 9999

        // Keys — harus sama dengan Flutter SharedPreferences keys
        private const val K_PREFS_SELECTED_APPS = "xc_selected_apps"
        private const val K_PREFS_POST_URL = "xc_post_url"
        private const val K_PREFS_SAVED_NOTIFICATIONS = "xc_saved_notifications"
        private const val K_PREFS_POST_LOGS = "xc_post_logs"
    }

    private val gson = Gson()
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    override fun onCreate() {
        super.onCreate()
        createNotificationChannelIfNeeded()
        startAsForeground()
        Log.i(TAG, "Service created and promoted to foreground")
    }

    private fun createNotificationChannelIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW)
            channel.description = "XC listener foreground channel"
            nm.createNotificationChannel(channel)
        }
    }

    private fun startAsForeground(lastText: String = "Menangkap notifikasi") {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent ?: Intent(), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notif: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("XC Listener aktif")
            .setContentText(lastText)
            .setSmallIcon(getApplicationInfo().icon)
            .setOngoing(true)      // penting: ongoing -> tidak mudah di-swipe
            .setAutoCancel(false)
            .setContentIntent(pendingIntent)
            .build()

        startForeground(ONGOING_NOTIFICATION_ID, notif)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        try {
            val pkg = sbn.packageName ?: "unknown"
            val extras = sbn.notification.extras
            val title = extras.getString("android.title") ?: extras.getString("android.title.big") ?: ""
            val text = extras.getCharSequence("android.text")?.toString() ?: ""
            Log.i(TAG, "Posted: $pkg | $title | $text")

            // Check selected apps: if some selected, only handle those
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val selectedSet = prefs.getStringSet(K_PREFS_SELECTED_APPS, null) // null => no restriction
            if (selectedSet != null && selectedSet.isNotEmpty() && !selectedSet.contains(pkg)) {
                Log.i(TAG, "Ignored package (not selected): $pkg")
                return
            }

            // Build notification item (simple map)
            val itemMap = mapOf(
                "id" to sbn.id,
                "packageName" to pkg,
                "title" to title,
                "content" to text,
                "timestamp" to System.currentTimeMillis(),
                "hasRemoved" to false
            )

            // Save to prefs (prepend into JSON array)
            saveNotificationToPrefs(itemMap)

            // Update foreground notification text (show last app/title/count)
            val savedCount = getSavedNotificationCount(prefs)
            val lastText = "$pkg — ${if (title.isNotEmpty()) title else text} ($savedCount)"
            startAsForeground(lastText)

            // Show a one-shot local notification (optional)
            // We already have a foreground notif; but we can also call NotificationManager.notify for event
            showEventNotification(title, text)

            // Send POST if URL configured
            val postUrl = prefs.getString(K_PREFS_POST_URL, "") ?: ""
            if (postUrl.trim().isNotEmpty()) {
                postNotificationToUrl(postUrl.trim(), pkg, title, text)
            }
        } catch (e: Exception) {
            Log.e(TAG, "onNotificationPosted error: ${e.message}", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        try {
            val pkg = sbn.packageName ?: "unknown"
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            // Mark hasRemoved = true where id/package match (simple implementation)
            markNotificationRemovedInPrefs(sbn.id, pkg)
            Log.i(TAG, "Notification removed: $pkg id=${sbn.id}")
        } catch (e: Exception) {
            Log.e(TAG, "onNotificationRemoved error: ${e.message}", e)
        }
    }

    private fun showEventNotification(title: String?, text: String?) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val n = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(getApplicationInfo().icon)
            .setContentTitle(if (title.isNullOrEmpty()) "Notification" else title)
            .setContentText(if (text.isNullOrEmpty()) "" else text)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        val id = (System.currentTimeMillis() % 100000).toInt()
        nm.notify(id, n)
    }

    private fun getSavedNotificationCount(prefs: android.content.SharedPreferences): Int {
        val raw = prefs.getString(K_PREFS_SAVED_NOTIFICATIONS, null)
        if (raw.isNullOrEmpty()) return 0
        return try {
            val type = object : TypeToken<List<Map<String, Any>>>() {}.type
            val list: List<Map<String, Any>> = gson.fromJson(raw, type)
            list.size
        } catch (ex: Exception) {
            0
        }
    }

    private fun saveNotificationToPrefs(item: Map<String, Any?>) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString(K_PREFS_SAVED_NOTIFICATIONS, null)

        val list: MutableList<Map<String, Any?>> = if (!raw.isNullOrEmpty()) {
            try {
                val type = object : TypeToken<MutableList<Map<String, Any?>>>() {}.type
                gson.fromJson(raw, type)
            } catch (e: Exception) {
                mutableListOf()
            }
        } else {
            mutableListOf()
        }

        // prepend (newest first)
        list.add(0, item)
        val json = gson.toJson(list)
        prefs.edit().putString(K_PREFS_SAVED_NOTIFICATIONS, json).apply()
    }

    private fun markNotificationRemovedInPrefs(id: Int, pkg: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString(K_PREFS_SAVED_NOTIFICATIONS, null)
        if (raw.isNullOrEmpty()) return
        try {
            val type = object : TypeToken<MutableList<MutableMap<String, Any?>>>() {}.type
            val list: MutableList<MutableMap<String, Any?>> = gson.fromJson(raw, type)
            for (m in list) {
                val mid = (m["id"] as? Double)?.toInt() ?: (m["id"] as? Int)
                val mpkg = m["packageName"] as? String
                if (mid == id && mpkg == pkg) {
                    m["hasRemoved"] = true
                    break
                }
            }
            prefs.edit().putString(K_PREFS_SAVED_NOTIFICATIONS, gson.toJson(list)).apply()
        } catch (e: Exception) {
            Log.e(TAG, "markRemoved error: ${e.message}", e)
        }
    }

    private fun postNotificationToUrl(url: String, pkg: String, title: String?, text: String?) {
        // Build body as application/x-www-form-urlencoded: app={not_app_name}&title={not_title}&text={notification}
        val formBody = FormBody.Builder()
            .add("app", pkg)
            .add("title", title ?: "")
            .add("text", text ?: "")
            .build()

        val request = Request.Builder()
            .url(url)
            .post(formBody)
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(TAG, "POST failed: ${e.message}")
                savePostLogToPrefs(url, pkg, title, text, null, "", e.message ?: "unknown")
            }

            override fun onResponse(call: Call, response: Response) {
                val body = try { response.body?.string() ?: "" } catch (ex: Exception) { "" }
                Log.i(TAG, "POST success: ${response.code}")
                savePostLogToPrefs(url, pkg, title, text, response.code, body, "")
            }
        })
    }

    private fun savePostLogToPrefs(url: String, app: String, title: String?, text: String?, statusCode: Int?, responseBody: String, error: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString(K_PREFS_POST_LOGS, null)
        val list: MutableList<Map<String, Any?>> = if (!raw.isNullOrEmpty()) {
            try {
                val type = object : TypeToken<MutableList<Map<String, Any?>>>() {}.type
                gson.fromJson(raw, type)
            } catch (e: Exception) {
                mutableListOf()
            }
        } else {
            mutableListOf()
        }

        val entry = mapOf(
            "timestamp" to System.currentTimeMillis(),
            "url" to url,
            "app" to app,
            "title" to title,
            "text" to text,
            "statusCode" to statusCode,
            "responseBody" to responseBody,
            "error" to error
        )

        list.add(0, entry)
        prefs.edit().putString(K_PREFS_POST_LOGS, gson.toJson(list)).apply()
    }

    override fun onDestroy() {
        super.onDestroy()
        // don't stopForeground here necessarily; system will stop
        Log.i(TAG, "Service destroyed")
    }
}
