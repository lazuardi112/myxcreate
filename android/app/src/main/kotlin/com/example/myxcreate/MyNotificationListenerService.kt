// android/app/src/main/kotlin/com/example/myxcreate/MyNotificationListenerService.kt
package com.example.myxcreate

import android.app.Notification
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.google.gson.Gson
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request

class MyNotificationListenerService : NotificationListenerService() {
    private val TAG = "MyNotifListener"
    private val prefsName = "myxcreate_prefs"
    private val gson = Gson()
    private val client = OkHttpClient()

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            val packageName = sbn.packageName ?: return
            val extras = sbn.notification.extras
            val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

            val sp = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            val enabled = sp.getBoolean("enabled", false)
            if (!enabled) return

            // read selected packages JSON
            val selectedJson = sp.getString("selectedPackagesJson", null)
            if (selectedJson != null) {
                val selected: List<String> = gson.fromJson(selectedJson, Array<String>::class.java).toList()
                if (selected.isNotEmpty() && !selected.contains(packageName)) {
                    // not in selected list -> ignore
                    return
                }
            }

            val postUrl = sp.getString("postUrl", "") ?: ""
            if (postUrl.isNotEmpty()) {
                // send POST via OkHttp
                val form = FormBody.Builder()
                    .add("app", packageName)
                    .add("title", title)
                    .add("text", text)
                    .build()

                val req = Request.Builder().url(postUrl).post(form).build()
                client.newCall(req).execute().use { resp ->
                    Log.i(TAG, "POST ${resp.code} -> ${resp.body?.string()}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "onNotificationPosted error", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // optional: handle removal
    }
}
