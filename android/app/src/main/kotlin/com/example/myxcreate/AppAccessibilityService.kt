package com.example.myxcreate

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import androidx.core.app.NotificationCompat

class AppAccessibilityService : AccessibilityService() {

    private val CHANNEL_ID = "xcapp_access_service_channel"
    private val NOTIF_ID = 1001
    private val PREF_NAME = "xcapp_notifications"
    private val PREF_KEY = "notifications_list"

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("AppAccessibilityService", "Accessibility service connected")
        createForegroundNotification()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        try {
            when (event.eventType) {
                AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED -> {
                    // Ambil teks notifikasi (bisa beberapa bagian)
                    val packageName = event.packageName?.toString() ?: "unknown_pkg"

                    // event.text bisa berisi beberapa CharSequence, gabungkan jadi satu
                    val combinedText = buildString {
                        val list = event.text
                        if (list != null && list.isNotEmpty()) {
                            for (cs in list) {
                                if (!cs.isNullOrBlank()) {
                                    if (isNotEmpty()) append(" ")
                                    append(cs.toString())
                                }
                            }
                        }
                    }.ifEmpty { "Tidak ada teks" }

                    // Jika ada title di extras (tidak selalu tersedia di AccessibilityEvent)
                    // NOTE: AccessibilityEvent tidak selalu membawa extras seperti Notification objects.
                    val notifString = "[$packageName] $combinedText"

                    Log.d("AppAccessibilityService", "Captured notif: $notifString")

                    // Simpan ke SharedPreferences
                    saveNotificationToPrefs(notifString)
                }

                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                    // Opsional: hanya log
                    Log.d("AppAccessibilityService", "Window state changed: ${event.packageName}")
                }
            }
        } catch (e: Exception) {
            Log.e("AppAccessibilityService", "Error handling accessibility event", e)
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
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "XCApp Accessibility",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = getString(R.string.accessibility_service_description_notif)
            nm.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.foreground_service_title))
            .setContentText(getString(R.string.foreground_service_content))
            .setSmallIcon(applicationInfo.icon)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        // Start as foreground to reduce chance service dibunuh oleh OS
        startForeground(NOTIF_ID, notification)
    }

    private fun saveNotificationToPrefs(notif: String) {
        try {
            val prefs = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            // Menggunakan LinkedHashSet supaya urutan insert tetap terjaga
            val current = prefs.getStringSet(PREF_KEY, linkedSetOf())?.toMutableSet() ?: linkedSetOf()
            // Insert di awal secara semantik: karena Set tidak punya index, kita recreate set
            // dengan notif terbaru di depan: gunakan LinkedHashSet dan rebuild
            val newSet = linkedSetOf<String>()
            newSet.add(notif)
            newSet.addAll(current)
            // Batasi jumlah notifikasi disimpan (mis. 200)
            val limited = newSet.take(200).toCollection(linkedSetOf())
            prefs.edit().putStringSet(PREF_KEY, limited).apply()
        } catch (e: Exception) {
            Log.e("AppAccessibilityService", "Failed saving notif to prefs", e)
        }
    }
}
