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
import org.json.JSONArray
import org.json.JSONObject

class AppNotificationService : NotificationListenerService() {

    companion object {
        private const val TAG = "AppNotificationService"
        private const val CHANNEL_ID = "xcapp_notif_service_channel"
        private const val FOREGROUND_ID = 101
        private const val PREF_NAME = "xcapp_notifications"
        private const val KEY_NOTIFS = "notifications"
    }

    private lateinit var prefs: SharedPreferences

    override fun onCreate() {
        super.onCreate()
        prefs = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        createForegroundNotification()
        Log.d(TAG, "Notification Service Created")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "Notification Listener Connected")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return

        val pkg = sbn.packageName
        val title = sbn.notification.extras.getString(Notification.EXTRA_TITLE) ?: ""
        val text = sbn.notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        val notifJson = JSONObject().apply {
            put("package", pkg)
            put("title", title)
            put("text", text)
            put("timestamp", System.currentTimeMillis())
        }

        Log.d(TAG, "Notif received: $notifJson")

        saveNotification(notifJson)
    }

    private fun saveNotification(notif: JSONObject) {
        val existing = prefs.getString(KEY_NOTIFS, null)
        val array = if (existing != null) JSONArray(existing) else JSONArray()
        array.put(notif)

        prefs.edit().putString(KEY_NOTIFS, array.toString()).apply()
    }

    private fun createForegroundNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "XCApp Notifications",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Menangkap notifikasi agar aplikasi tetap bekerja di background"
            nm.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("XCApp - Service Aktif")
            .setContentText("Service berjalan untuk menangkap notifikasi di background")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        startForeground(FOREGROUND_ID, notification)
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "Notification Listener Disconnected")
        // Restart service jika perlu
    }
}
