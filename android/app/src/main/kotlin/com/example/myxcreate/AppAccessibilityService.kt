package com.example.myxcreate

import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

class AppNotificationService : NotificationListenerService() {

    private val CHANNEL_ID = "xcapp_notification_service_channel"
    private val NOTIF_ID = 1001
    private val PREF_NAME = "xcapp_notifications"
    private val PREF_KEY = "notifications"

    override fun onCreate() {
        super.onCreate()
        Log.d("AppNotificationService", "Notification service created")
        createForegroundNotification()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            val packageName = sbn.packageName ?: ""
            val title = sbn.notification.extras.getString("android.title") ?: ""
            val content = sbn.notification.extras.getCharSequence("android.text")?.toString() ?: ""

            val notifString = "[$packageName] $title - $content"
            Log.d("AppNotificationService", "New notification: $notifString")

            saveNotification(notifString)
        } catch (e: Exception) {
            Log.e("AppNotificationService", "Error saving notification", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // Optional: tangani jika notifikasi dihapus
        Log.d("AppNotificationService", "Notification removed: ${sbn.packageName}")
    }

    private fun createForegroundNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "XCApp Notifikasi Service",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Service untuk menerima notifikasi di background"
            nm.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("XCApp - Layanan Notifikasi Aktif")
            .setContentText("Menerima notifikasi di latar belakang")
            .setSmallIcon(applicationInfo.icon)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        startForeground(NOTIF_ID, notification)
    }

    private fun saveNotification(notif: String) {
        val prefs = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val current = prefs.getStringSet(PREF_KEY, mutableSetOf())?.toMutableSet() ?: mutableSetOf()
        current.add(notif)
        prefs.edit().putStringSet(PREF_KEY, current).apply()
    }
}
