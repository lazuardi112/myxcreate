package com.example.myxcreate  // <-- GANTI sesuai package kamu

import android.app.*
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import android.content.Context

class ForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "xc_fg_channel"
        const val NOTIF_ID = 7451
        const val ACTION_START = "com.example.myxcreate.action.START"
        const val ACTION_STOP = "com.example.myxcreate.action.STOP"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        val notifIntent = Intent(this, Class.forName("${applicationContext.packageName}.MainActivity"))
        val pending = PendingIntent.getActivity(
            this, 0, notifIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Xcreate Listener")
            .setContentText("Listening notifications in background")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pending)
            .setOngoing(true)
            .build()

        startForeground(NOTIF_ID, notification)

        // START_STICKY agar system dapat restart service jika dimatikan (secara best-effort)
        return START_STICKY
    }

    override fun onDestroy() {
        stopForeground(true)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Xcreate Foreground"
            val chan = NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW)
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(chan)
        }
    }
}
