package com.example.myxcreate

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import androidx.core.app.NotificationCompat

class AppAccessibilityService : AccessibilityService() {

    private val CHANNEL_ID = "xcapp_access_service_channel"
    private val NOTIF_ID = 1001

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("AppAccessibilityService", "Accessibility service connected")
        createForegroundNotification()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Anda bisa tangani event jika perlu. Untuk tujuan "keep alive" tidak wajib isi.
        if (event != null) {
            // contoh: log tipe event
            Log.d("AppAccessibilityService", "Event: ${event.eventType} from ${event.packageName}")
        }
    }

    override fun onInterrupt() {
        Log.d("AppAccessibilityService", "Accessibility service interrupted")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        Log.d("AppAccessibilityService", "onUnbind")
        return super.onUnbind(intent)
    }

    private fun createForegroundNotification() {
        val nm = getSystemService(NotificationManager::class.java)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "XCApp Accessibility",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Accessibility service to keep XCApp running"
            nm.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("XCApp - Layanan Aksesibilitas Aktif")
            .setContentText("Service berjalan untuk menjaga notifikasi di latar belakang")
            .setSmallIcon(getApplicationInfo().icon)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        // Jalankan service sebagai foreground agar proses lebih sulit dimatikan
        startForeground(NOTIF_ID, notification)
    }
}
