package com.example.myxcreate

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.util.Log
import android.app.NotificationChannel
import android.app.NotificationManager.IMPORTANCE_LOW
import android.os.Build

class ForegroundStarterService : Service() {
    private val TAG = "ForegroundStarter"
    private val CHANNEL_ID = "xc_foreground_channel"
    private val NOTIF_ID = 9999

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // PendingIntent untuk tombol Stop -> dikirim ke ControlReceiver
        val stopIntent = Intent(this, ControlReceiver::class.java).apply {
            action = "com.example.myxcreate.ACTION_STOP"
        }
        val stopPending = PendingIntent.getBroadcast(this, 0, stopIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

        val builder = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("XC Listener aktif")
            .setContentText("Menangkap notifikasi")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPending)

        val notif = builder.build()
        startForeground(NOTIF_ID, notif)
        Log.d(TAG, "ForegroundStarter started")
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "ForegroundStarter destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(CHANNEL_ID, "XC Background", IMPORTANCE_LOW)
            ch.description = "Foreground service to keep listener running"
            nm.createNotificationChannel(ch)
        }
    }
}
