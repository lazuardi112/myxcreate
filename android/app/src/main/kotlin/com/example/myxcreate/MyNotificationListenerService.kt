package com.example.myxcreate

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.SharedPreferences
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

        private const val K_PREFS_SELECTED_APPS = "xc_selected_apps"
        private const val K_PREFS_POST_URL = "xc_post_url"
        private const val K_PREFS_SAVED_NOTIFICATIONS = "xc_saved_notifications"
        private const val K_PREFS_POST_LOGS = "xc_post_logs"
        private const val K_PREFS_ENABLED = "xc_listener_enabled"
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
    }

    private val gson = Gson()
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForegroundPersistent("XC Listener siap")
        Log.i(TAG, "Service created")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW)
            channel.description = "XC listener foreground channel"
            nm.createNotificationChannel(channel)
        }
    }

    private fun startForegroundPersistent(text: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("XC Listener Service")
            .setContentText(text)
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
        startForeground(ONGOING_NOTIFICATION_ID, notif as Notification)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        try {
            if (sbn == null) return
            val prefs = getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
            val enabled = prefs.getBoolean(K_PREFS_ENABLED, false)
            if (!enabled) {
                Log.i(TAG, "Listener disabled by flag; ignoring")
                return
            }

            val pkg = sbn.packageName ?: "unknown"
            val extras = sbn.notification.extras
            val title = extras.getString("android.title") ?: ""
            val text = extras.getCharSequence("android.text")?.toString() ?: ""

            // selected apps logic (StringSet or JSON fallback)
            var allowed = true
            val selectedSet = prefs.getStringSet(K_PREFS_SELECTED_APPS, null)
            if (selectedSet != null && selectedSet.isNotEmpty()) {
                allowed = selectedSet.contains(pkg)
            } else {
                val raw = prefs.getString(K_PREFS_SELECTED_APPS, null)
                if (!raw.isNullOrEmpty()) {
                    try {
                        val listType = object : TypeToken<List<String>>() {}.type
                        val list: List<String> = gson.fromJson(raw, listType)
                        if (list.isNotEmpty()) allowed = list.contains(pkg)
                    } catch (_: Exception) { /* ignore */ }
                }
            }

            if (!allowed) {
                Log.i(TAG, "Ignored package $pkg (not selected)")
                return
            }

            saveNotificationToPrefs(sbn.id, pkg, title, text)

            val count = getSavedCount(prefs)
            startForegroundPersistent("$pkg — ${if (title.isNotBlank()) title else text} ($count)")

            showEventNotification(title, text)

            val postUrl = prefs.getString(K_PREFS_POST_URL, "") ?: ""
            if (postUrl.trim().isNotEmpty()) {
                postToUrl(postUrl.trim(), pkg, title, text)
            }
        } catch (e: Exception) {
            Log.e(TAG, "onNotificationPosted error", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        try {
            markNotificationRemoved(sbn.id, sbn.packageName ?: "unknown")
        } catch (e: Exception) {
            Log.e(TAG, "onNotificationRemoved error", e)
        }
    }

    private fun saveNotificationToPrefs(id: Int, pkg: String, title: String, text: String) {
        val prefs = getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
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
        val item = mapOf<String, Any?>(
            "id" to id,
            "packageName" to pkg,
            "title" to title,
            "content" to text,
            "timestamp" to System.currentTimeMillis(),
            "hasRemoved" to false
        )
        list.add(0, item)
        prefs.edit().putString(K_PREFS_SAVED_NOTIFICATIONS, gson.toJson(list)).apply()
    }

    private fun getSavedCount(prefs: SharedPreferences): Int {
        val raw = prefs.getString(K_PREFS_SAVED_NOTIFICATIONS, null) ?: return 0
        return try {
            val type = object : TypeToken<List<Map<String, Any?>>>() {}.type
            val list: List<Map<String, Any?>> = gson.fromJson(raw, type)
            list.size
        } catch (e: Exception) {
            0
        }
    }

    private fun markNotificationRemoved(id: Int, pkg: String) {
        val prefs = getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(K_PREFS_SAVED_NOTIFICATIONS, null) ?: return
        try {
            val type = object : TypeToken<MutableList<MutableMap<String, Any?>>>() {}.type
            val list: MutableList<MutableMap<String, Any?>> = gson.fromJson(raw, type)
            for (m in list) {
                val mid = when (val v = m["id"]) {
                    is Double -> v.toInt()
                    is Float -> v.toInt()
                    is Int -> v
                    else -> null
                }
                val mpkg = m["packageName"] as? String
                if (mid == id && mpkg == pkg) {
                    m["hasRemoved"] = true
                    break
                }
            }
            prefs.edit().putString(K_PREFS_SAVED_NOTIFICATIONS, gson.toJson(list)).apply()
        } catch (e: Exception) {
            Log.e(TAG, "markRemoved error", e)
        }
    }

    private fun showEventNotification(title: String?, body: String?) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title ?: "Notification")
            .setContentText(body ?: "")
            .setAutoCancel(true)
            .build()
        val id = (System.currentTimeMillis() % 100000).toInt()
        nm.notify(id, notif)
    }

    private fun postToUrl(url: String, pkg: String, title: String?, text: String?) {
        val form = FormBody.Builder()
            .add("app", pkg)
            .add("title", title ?: "")
            .add("text", text ?: "")
            .build()

        val req = Request.Builder()
            .url(url)
            .post(form)
            .build()

        client.newCall(req).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(TAG, "POST failed: ${e.message}")
                savePostLog(url, pkg, title, text, null, "", e.message ?: "unknown")
            }

            override fun onResponse(call: Call, response: Response) {
                val body = try { response.body?.string() ?: "" } catch (ex: Exception) { "" }
                Log.i(TAG, "POST success: ${response.code}")
                savePostLog(url, pkg, title, text, response.code, body, "")
            }
        })
    }

    private fun savePostLog(url: String, app: String, title: String?, text: String?, statusCode: Int?, responseBody: String, error: String) {
        val prefs = getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
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
}
