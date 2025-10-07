// android/app/src/main/kotlin/com/example/myxcreate/ForegroundStarterService.kt
package com.example.myxcreate

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ForegroundStarterService : Service() {
    private val CHANNEL_ID = "xc_native_foreground_channel"
    private val NOTIF_ID = 4001
    private val CONTROL_STOP = "com.example.myxcreate.ACTION_STOP_SERVICE"

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Build a persistent notification with STOP action
        val stopIntent = Intent(this, ControlReceiver::class.java).apply { action = CONTROL_STOP }
        val stopPending = PendingIntent.getBroadcast(this, 0, stopIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("XC Listener aktif")
            .setContentText("Menangkap notifikasi (tap STOP untuk hentikan)")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .addAction(NotificationCompat.Action.Builder(0, "STOP", stopPending).build())
            .build()

        startForeground(NOTIF_ID, notif)

        // ensure NotificationListenerService kept running / or Native listener reads settings
        return START_STICKY
    }

    override fun onDestroy() {
        stopForeground(true)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(CHANNEL_ID, "XC Native Foreground", NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            nm.createNotificationChannel(ch)
        }
    }
}
