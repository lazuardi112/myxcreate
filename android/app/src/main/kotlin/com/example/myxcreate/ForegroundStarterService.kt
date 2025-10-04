package com.example.myxcreate

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ForegroundStarterService : Service() {
    companion object {
        private const val CHANNEL_ID = "xc_foreground_channel"
        private const val CHANNEL_NAME = "XC Foreground"
        private const val NOTIF_ID = 9998

        const val ACTION_START = "com.example.myxcreate.ACTION_START_LISTENER"
        const val ACTION_STOP = "com.example.myxcreate.ACTION_STOP_LISTENER"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForegroundWithActions("XC Listener running")
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW)
            channel.description = "Persistent XC notification"
            nm.createNotificationChannel(channel)
        }
    }

    private fun startForegroundWithActions(text: String) {
        val startIntent = Intent(this, ControlReceiver::class.java).apply { action = ACTION_START }
        val startPending = PendingIntent.getBroadcast(this, 1, startIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        val stopIntent = Intent(this, ControlReceiver::class.java).apply { action = ACTION_STOP }
        val stopPending = PendingIntent.getBroadcast(this, 2, stopIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("XC Listener")
            .setContentText(text)
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setAutoCancel(false)
            .addAction(android.R.drawable.ic_media_play, "Start", startPending)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopPending)
            .build()

        startForeground(NOTIF_ID, notif as Notification)
    }
}
