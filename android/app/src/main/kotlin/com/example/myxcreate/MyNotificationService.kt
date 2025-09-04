package com.example.myxcreate

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.util.Log

class MyNotificationService : AccessibilityService() {
    private val TAG = "MyNotificationService"

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
            val pkgName = event.packageName?.toString() ?: "unknown"
            val text = event.text?.joinToString(" ") ?: ""

            Log.i(TAG, "Notif dari [$pkgName]: $text")
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "Notif service interrupted")
    }
}
