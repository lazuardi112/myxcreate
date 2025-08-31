package com.xample.myxcreate

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class MyNotificationListenerService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        Log.d("NOTIF_LISTENER", "Notifikasi diterima: ${sbn.packageName}")
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        Log.d("NOTIF_LISTENER", "Notifikasi dihapus: ${sbn.packageName}")
    }
}
